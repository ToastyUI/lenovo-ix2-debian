#!/bin/sh
# Prepare the Debian root on partition 3 of the disks, from stock QTS (no dock needed).
# Partition 3 of every disk becomes one RAID 1 (metadata 1.2, homehost ts41x-debian, so only
# Debian's mdadm.conf assembles it) with an ext4 filesystem labelled rootfs. Partitions 1, 2
# and 4 (QTS system arrays md9/md13 and swap md4) stay untouched. The rootfs comes in on
# stdin, because /tmp on QTS is a RAM disk too small for it:
#
#   cat ts41x-prep-qts.sh | ssh admin@NAS 'cat > /tmp/prep.sh'
#   ssh admin@NAS 'sh /tmp/prep.sh'                                   # dry run: checks only
#   ssh admin@NAS 'sh /tmp/prep.sh --write' < rootfs.tar.gz           # wipes partition 3!
#
# Options: --disks "sda sdb" (default: every non-USB sd? disk), --write.
# The SSH keys in QTS's /root/.ssh/authorized_keys are copied into the Debian root.
set -eu
MD=/dev/md100 MNT=/tmp/ts41x-root HOMEHOST=ts41x-debian
DISKS='' WRITE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --disks) DISKS="$2"; shift 2 ;;
    --write) WRITE=1; shift ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
done
die() { echo "ERROR: $*" >&2; exit 1; }
part() { case "$1" in *[0-9]) echo "${1}p$2" ;; *) echo "$1$2" ;; esac; }  # sda3, loop0p3
# TS41X_SIM=1: simulation tests on loop disks (tests/run-sim-tests.sh)
[ -f /etc/config/uLinux.conf ] || [ "${TS41X_SIM:-}" = 1 ] || die "this is not QTS"
[ "$(id -u)" = 0 ] || die "run as admin (uid 0)"
for t in mdadm mke2fs tar gzip mount; do command -v $t >/dev/null || die "missing tool: $t"; done

if [ -z "$DISKS" ]; then
  for d in /sys/block/sd?; do
    readlink -f "$d/device" | grep -q usb && continue
    DISKS="$DISKS ${d##*/}"
  done
fi
set -- $DISKS
[ $# -ge 2 ] || die "need at least 2 disks for RAID 1 (found: $DISKS)"

# --- every partition 3: same start and size, not in use, no md superblock, no filesystem in use
ref=''
for d in $DISKS; do
  p3=$(part "$d" 3); p=/sys/block/$d/$p3
  [ -d "$p" ] || die "/dev/$p3 does not exist"
  geo="$(cat "$p/start") $(cat "$p/size")"
  [ -z "$ref" ] && ref=$geo
  [ "$geo" = "$ref" ] || die "/dev/$p3 is at '$geo', first disk at '$ref': layouts differ"
  grep -q " $p3\[" /proc/mdstat && die "/dev/$p3 is in an active array (/proc/mdstat)"
  grep -q "^/dev/$p3 " /proc/mounts && die "/dev/$p3 is mounted"
  mdadm --examine "/dev/$p3" >/dev/null 2>&1 && die "/dev/$p3 has an md superblock: old array? check by hand"
  echo "ok: /dev/$p3 start $(echo $geo | cut -d' ' -f1), $(( $(echo $geo | cut -d' ' -f2) / 2048 )) MiB, free"
done
[ -e $MD ] && grep -q "^${MD#/dev/} " /proc/mdstat && die "$MD already exists"
parts=''; for d in $DISKS; do parts="$parts /dev/$(part "$d" 3)"; done
echo "plan: RAID 1 $MD over$parts, ext4 label rootfs, unpack rootfs from stdin"
[ "$WRITE" = 1 ] || { echo "dry run: nothing written (add --write and feed rootfs.tar.gz on stdin)"; exit 0; }
[ -t 0 ] && die "--write needs rootfs.tar.gz on stdin"

echo "[1/5] RAID 1 $(date +%T)"
mdadm --create $MD --run --auto=md --level=1 --raid-devices=$# --metadata=1.2 \
  --homehost=$HOMEHOST --name=root $parts
echo "[2/5] ext4 $(date +%T)"
# explicit features: QTS's mke2fs 1.42 may have no ext4 entry in mke2fs.conf
mke2fs -q -F -j -L rootfs -m 1 -I 256 -O extent,flex_bg,uninit_bg,dir_nlink,extra_isize,large_file,huge_file $MD
mkdir -p $MNT
mount -t ext4 $MD $MNT
trap 'umount $MNT 2>/dev/null || true' EXIT
echo "[3/5] unpacking rootfs from stdin $(date +%T)"
gzip -dc | tar -xf - -C $MNT
[ -x $MNT/sbin/init ] || [ -L $MNT/sbin/init ] || die "rootfs unpacked but /sbin/init missing"
echo "[4/5] keys, mdadm.conf, boot.conf $(date +%T)"
for k in /root/.ssh/authorized_keys /etc/config/ssh/authorized_keys; do
  [ -s "$k" ] && cat "$k" >>$MNT/root/.ssh/authorized_keys
done
chmod 600 $MNT/root/.ssh/authorized_keys
mdadm --detail --brief $MD >>$MNT/etc/mdadm/mdadm.conf
mkdir -p $MNT/etc/ts41x
sed "s|^DISKS=.*|DISKS=\"$(echo $DISKS)\"|" $MNT/etc/ts41x/boot.conf.example >$MNT/etc/ts41x/boot.conf
echo "[5/5] sync $(date +%T)"
sync; umount $MNT; trap - EXIT
echo "done. $MD keeps resyncing in the background (hours); that is fine, also across a reboot."
cat /proc/mdstat
