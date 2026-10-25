#!/bin/sh
# Write the Debian multi-image (kernel+DTB+initrd) to the raw boot area of every disk.
# Runs on stock QTS (busybox) for the first install, and on Debian for kernel updates.
#
#   ts41x-install-boot.sh --image boot.uimg --mode qts  [--disks "sda sdb sdc sdd"] [--write]
#   ts41x-install-boot.sh --image boot.uimg --mode raw  [--disks ...] [--write]
#
# --mode qts  area = 1 MiB into partition 2 (QTS swap, md256). QTS data stays untouched.
#             QTS must not be swapping on it while we write: run "swapoff -a" first on QTS.
# --mode raw  area = sector 2048..100351, i.e. before partition 1 on disks partitioned by
#             this project (first partition at 128 MiB). Refuses if anything overlaps.
# Without --write it only prints what it would do (dry run).
#
# Every disk gets the same image at the same LBA, so U-Boot can boot from any bay.
# Prints the LBA in hex for ts41x-bootplan.py (stage2 --lba ...).
set -eu
AREA_OFFSET=2048        # sectors (1 MiB) into the area
AREA_SECTORS=98304      # 0x18000 = 48 MiB, must match ts41x-bootplan.py
IMG='' MODE='' DISKS='' WRITE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --image) IMG="$2"; shift 2 ;;
    --mode)  MODE="$2"; shift 2 ;;
    --disks) DISKS="$2"; shift 2 ;;
    --write) WRITE=1; shift ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
done
die() { echo "ERROR: $*" >&2; exit 1; }
# Must also run under QTS's busybox 1.01: no od, no printf, no readlink -f, maybe no "command".
have() { command -v "$1" >/dev/null 2>&1 || which "$1" >/dev/null 2>&1; }
hex() { # hex FILE SKIP COUNT: those bytes as lowercase hex
  if have od; then dd if="$1" bs=1 skip="$2" count="$3" 2>/dev/null | od -An -tx1 | tr -d ' \n'
  else dd if="$1" bs=1 skip="$2" count="$3" 2>/dev/null | hexdump -v -e '1/1 "%02x"'; fi
}
part() { case "$1" in *[0-9]) echo "${1}p$2" ;; *) echo "$1$2" ;; esac; }  # sda2, loop0p2, nvme..
[ -f "$IMG" ] || die "--image missing or not a file"
case "$MODE" in qts|raw) ;; *) die "--mode qts|raw required" ;; esac

# --- check the image: uImage magic 27051956, type 4 (multi), fits in the area
magic=$(hex "$IMG" 0 4)
[ "$magic" = "27051956" ] || die "$IMG is not a uImage (magic $magic)"
itype=$(hex "$IMG" 30 1)
[ "$itype" = "04" ] || die "$IMG is uImage type $itype, expected 4 (multi: kernel+initrd)"
bytes=$(wc -c <"$IMG" | tr -d ' ')
sectors=$(( (bytes + 511) / 512 ))
[ "$sectors" -le "$AREA_SECTORS" ] || die "image is $sectors sectors, area holds $AREA_SECTORS"

# --- disks: default = every sd? disk that is not USB
if [ -z "$DISKS" ]; then
  for d in /sys/block/sd?; do
    [ -e "$d" ] || continue
    readlink "$d/device" | grep -q usb && continue
    DISKS="$DISKS ${d##*/}"
  done
fi
[ -n "$DISKS" ] || die "no disks found"

LBA=
for dev in $DISKS; do
  sys=/sys/block/$dev
  [ -d "$sys" ] || die "$dev: no such disk"
  if [ "$MODE" = qts ]; then
    p2=$(part "$dev" 2)
    [ -d "$sys/$p2" ] || die "$dev: no partition 2 (not a QTS layout?)"
    pstart=$(cat "$sys/$p2/start"); psize=$(cat "$sys/$p2/size")
    lba=$((pstart + AREA_OFFSET))
    [ $((lba + AREA_SECTORS)) -le $((pstart + psize)) ] || die "$dev: partition 2 too small"
    # QTS swaps on an md over all partitions 2 (md4, md256, ...): refuse any active swap but zram
    active=$(awk 'NR > 1 && $1 !~ /zram/ { print $1 }' /proc/swaps)
    [ -z "$active" ] || die "swap is active ($(echo $active)): run 'swapoff -a' first"
  else
    lba=$AREA_OFFSET
    for p in "$sys/$dev"*[0-9]; do
      [ "$p" = "$sys/$dev" ] && continue
      [ -d "$p" ] || continue
      ps=$(cat "$p/start")
      [ "$ps" -ge $((lba + AREA_SECTORS)) ] || die "$dev: ${p##*/} starts at $ps, overlaps the raw area"
    done
  fi
  [ -z "$LBA" ] && LBA=$lba
  [ "$lba" = "$LBA" ] || die "$dev: area at $lba but other disks use $LBA; U-Boot needs one LBA for all bays"
done
[ "$LBA" -lt 268435456 ] || die "area beyond LBA28; old U-Boot cannot read it"

LBAHEX=$(echo "$LBA" | awk '{ printf "0x%x", $1 }')
echo "image   $IMG ($bytes bytes, $sectors sectors, multi)"
echo "mode    $MODE"
echo "disks  $DISKS"
echo "LBA     $LBA ($LBAHEX), area $AREA_SECTORS sectors"
if [ "$WRITE" != 1 ]; then echo "dry run: add --write to write"; exit 0; fi

# padded copy next to the image: /tmp on QTS is a 32 MB RAM disk, keep the image on /mnt/HDA_ROOT
pad=$IMG.pad.$$
dd if="$IMG" of="$pad" bs=512 conv=sync 2>/dev/null || { rm -f "$pad"; die "cannot write $pad (disk full?)"; }
for dev in $DISKS; do
  echo "writing /dev/$dev at $LBA"
  dd if="$pad" of="/dev/$dev" bs=512 seek="$LBA" conv=notrunc 2>/dev/null
done
sync
echo 3 >/proc/sys/vm/drop_caches 2>/dev/null || true
for dev in $DISKS; do
  if dd if="/dev/$dev" bs=512 skip="$LBA" count="$sectors" 2>/dev/null | cmp -s - "$pad"; then
    echo "verified /dev/$dev"
  else
    rm -f "$pad"; die "read-back of /dev/$dev differs"
  fi
done
rm -f "$pad"
echo "done. U-Boot: ts41x-bootplan.py stage2 --lba $LBAHEX"
