#!/bin/sh
# Read-only inventory of a QNAP TS-41x running stock QTS.
# Writes NOTHING to flash or disks: it only reads /proc, /sys, the MTD partitions and disk metadata.
#
# Run from your PC (QTS has ssh but no scp/sftp):
#   ssh admin@NAS 'sh -s' < tools/ts412-inventory.sh > ts412-inventory.tar
#   python3 tools/ts412-analyze.py ts412-inventory.tar
#
# Everything diagnostic goes to stderr; stdout carries only the tar stream.
set -u
OUT=/tmp/ts412-inventory.$$
mkdir -p "$OUT" || exit 1
log() { echo "[inventory] $*" >&2; }
run() { # run <file> <command...>: capture stdout+stderr, never fail
  f="$1"; shift
  { echo "\$ $*"; "$@"; echo "[exit $?]"; } >"$OUT/$f" 2>&1
}
have() { command -v "$1" >/dev/null 2>&1; }

log "system"
run uname.txt uname -a
run id.txt id
run cpuinfo.txt cat /proc/cpuinfo
run meminfo.txt cat /proc/meminfo
run cmdline.txt cat /proc/cmdline
run version.txt cat /etc/version /etc/default_config/uLinux.conf
have getcfg && { getcfg System Version; getcfg System "Build Number"; getcfg System Model; } >"$OUT/qts-version.txt" 2>&1
run dmesg.txt dmesg
run interfaces.txt ifconfig -a
run ttys.txt ls -l /dev/ttyS0 /dev/ttyS1

log "flash (read-only copies of mtd0..mtd5)"
run mtd.txt cat /proc/mtd
for n in 0 1 2 3 4 5; do
  [ -e /dev/mtdblock$n ] && cat /dev/mtdblock$n >"$OUT/mtd$n.bin" 2>/dev/null
done
have md5sum && (cd "$OUT" && md5sum mtd?.bin >mtd.md5 2>&1)

log "disks, partitions, RAID, LVM"
run partitions.txt cat /proc/partitions
run mdstat.txt cat /proc/mdstat
for d in /sys/block/sd?; do
  [ -d "$d" ] || continue
  dev=${d##*/}
  {
    echo "disk=$dev size_sectors=$(cat "$d/size") model=$(cat "$d/device/model" 2>/dev/null)"
    for p in "$d"/"$dev"[0-9]*; do
      [ -d "$p" ] && echo "part=${p##*/} start=$(cat "$p/start") size=$(cat "$p/size")"
    done
  } >>"$OUT/layout.txt" 2>&1
  have smartctl && run "smart-$dev.txt" smartctl -a "/dev/$dev"
  have fdisk && run "fdisk-$dev.txt" fdisk -l "/dev/$dev"
done
for md in /dev/md*; do
  [ -b "$md" ] || continue
  have mdadm && run "mdadm-${md##*/}.txt" mdadm --detail "$md"
done
have pvs && run lvm.txt sh -c 'pvs; vgs; lvs'
run mounts.txt cat /proc/mounts
run df.txt df -h

log "packing"
(cd /tmp && tar cf - "${OUT##*/}") || log "tar failed"
rm -rf "$OUT"
log "done"
