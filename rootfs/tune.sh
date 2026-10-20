#!/bin/bash
# Prestatie-afstelling voor de ix2-rootfs (deel A), in de wegwerpcontainer.
# Werkt op /root/ix2/rootfs (armel, via qemu-binfmt). Daarna uInitrd opnieuw maken.
set -euo pipefail
R=/root/ix2/rootfs; KVER=7.1.9-kirkwood-tld-1
export DEBIAN_FRONTEND=noninteractive LC_ALL=C

echo "[1/8] chroot voorbereiden $(date +%T)"
mount --bind /proc "$R/proc"; mount --bind /sys "$R/sys"; mount --bind /dev "$R/dev"
trap 'umount -l "$R/dev" "$R/sys" "$R/proc" 2>/dev/null || true' EXIT
cp /etc/resolv.conf "$R/etc/resolv.conf.bouw"; mv "$R/etc/resolv.conf" "$R/etc/resolv.conf.link"; cp /etc/resolv.conf "$R/etc/resolv.conf"

echo "[2/8] pakketten: zram, samba, meettools $(date +%T)"
chroot "$R" apt-get update -qq
chroot "$R" apt-get install -y -qq --no-install-recommends \
  systemd-zram-generator samba hdparm fio iperf3 ethtool lm-sensors >/dev/null
chroot "$R" apt-get clean

echo "[3/8] zram-swap (zstd, halve RAM) $(date +%T)"
cat > "$R/etc/systemd/zram-generator.conf" <<'E'
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
swap-priority = 100
E
echo zram > "$R/etc/modules-load.d/zram.conf"

echo "[4/8] logboek alleen in RAM $(date +%T)"
mkdir -p "$R/etc/systemd/journald.conf.d"
printf '[Journal]\nStorage=volatile\nRuntimeMaxUse=16M\n' > "$R/etc/systemd/journald.conf.d/ix2.conf"

echo "[5/8] NFS alleen v4.2, 4 threads; rpcbind/statd uit $(date +%T)"
mkdir -p "$R/etc/nfs.conf.d"
cat > "$R/etc/nfs.conf.d/ix2.conf" <<'E'
[nfsd]
vers3=n
vers4.0=n
vers4.1=n
vers4.2=y
threads=4
E
for u in rpcbind.service rpcbind.socket rpc-statd.service nfs-client.target remote-fs.target e2scrub_reap.service nmbd.service samba-ad-dc.service; do
  ln -sf /dev/null "$R/etc/systemd/system/$u"
done

echo "[6/8] sysctl: geheugen, schrijven, netwerkbuffers $(date +%T)"
cat > "$R/etc/sysctl.d/90-ix2.conf" <<'E'
# zram: swap is goedkoop (gecomprimeerd in RAM)
vm.swappiness = 100
vm.vfs_cache_pressure = 50
vm.min_free_kbytes = 8192
# klein en gelijkmatig wegschrijven (256 MB RAM)
vm.dirty_background_bytes = 4194304
vm.dirty_bytes = 16777216
# netwerkbuffers voor NFS/SMB over 1 GbE
net.core.rmem_max = 4194304
net.core.wmem_max = 4194304
net.ipv4.tcp_rmem = 4096 131072 4194304
net.ipv4.tcp_wmem = 4096 131072 4194304
net.core.netdev_max_backlog = 2000
E

echo "[7/8] schijven: mq-deadline + readahead $(date +%T)"
echo mq-deadline > "$R/etc/modules-load.d/mq-deadline.conf"
cat > "$R/etc/udev/rules.d/60-ix2-disks.rules" <<'E'
# draaiende schijven: mq-deadline (lichter dan BFQ op ARMv5) en 2 MB readahead
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="mq-deadline", ATTR{queue/read_ahead_kb}="2048"
# RAID-apparaat: 4 MB readahead
ACTION=="add|change", KERNEL=="md[0-9]*", ATTR{bdi/read_ahead_kb}="4096"
E
cat > "$R/etc/samba/smb.conf" <<'E'
# ix2: Samba afgesteld voor Kirkwood ARMv5 (256 MB). Shares volgen na het RAID (fase 6).
[global]
   server string = ix2
   workgroup = WORKGROUP
   server role = standalone server
   map to guest = never
   # alleen moderne protocollen; iPhone/macOS gebruiken SMB3
   server min protocol = SMB2_10
   disable netbios = yes
   smb ports = 445
   # ondertekening/versleuteling: Samba-standaard (onderhandelen). Op het eigen netwerk staat
   # het dan uit; onderweg versleutelt ZeroTier. Niet forceren: sommige macOS-versies eisen signing.
   # zero-copy en async I/O
   use sendfile = yes
   min receivefile size = 16384
   aio read size = 1
   aio write size = 1
   socket options = TCP_NODELAY IPTOS_LOWDELAY
   # Mac/iPhone: Apple-metadata in xattrs, snelle Finder
   vfs objects = catia fruit streams_xattr
   fruit:metadata = stream
   fruit:model = MacSamba
   fruit:posix_rename = yes
   fruit:veto_appledouble = no
   fruit:nfs_aces = no
   fruit:wipe_intentionally_left_blank_rfork = yes
   fruit:delete_empty_adfiles = yes
   # geen printers
   load printers = no
   printing = bsd
   printcap name = /dev/null
   disable spoolss = yes
   logging = systemd
   log level = 1
E

echo "[8/8] terugzetten resolv + uInitrd opnieuw $(date +%T)"
rm -f "$R/etc/resolv.conf" "$R/etc/resolv.conf.bouw"; mv "$R/etc/resolv.conf.link" "$R/etc/resolv.conf"
chroot "$R" bash -c "update-initramfs -u -k $KVER" || true
mkimage -A arm -O linux -T ramdisk -C gzip -a 0x00000000 -e 0x00000000 -n "initramfs-$KVER" \
  -d "$R/boot/initrd.img-$KVER" "$R/boot/uInitrd" >/dev/null
rm -rf "$R/var/lib/apt/lists/"* "$R/usr/share/doc/"* "$R/usr/share/man/"* 2>/dev/null || true
echo "klaar $(date +%T)"; du -sh --exclude=proc --exclude=sys --exclude=dev "$R"; ls -la "$R/boot/uInitrd"
