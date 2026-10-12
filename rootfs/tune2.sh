#!/bin/bash
set -euo pipefail
R=/root/ix2/rootfs; export DEBIAN_FRONTEND=noninteractive LC_ALL=C
mount --bind /proc "$R/proc"; mount --bind /sys "$R/sys"; mount --bind /dev "$R/dev"
trap 'umount -l "$R/dev" "$R/sys" "$R/proc" 2>/dev/null || true; rm -f "$R/etc/resolv.conf"; ln -sf /run/systemd/resolve/stub-resolv.conf "$R/etc/resolv.conf"' EXIT
rm -f "$R/etc/resolv.conf"; cp /etc/resolv.conf "$R/etc/resolv.conf"
# zram: lz4 (snel op ARMv5)
sed -i "s/^compression-algorithm.*/compression-algorithm = lz4/" "$R/etc/systemd/zram-generator.conf"
printf "zram\nlz4\nlz4_compress\n" > "$R/etc/modules-load.d/zram.conf"
# ksmbd: installeren, afstellen, NIET aanzetten (Samba is standaard)
chroot "$R" apt-get update -qq
chroot "$R" apt-get install -y -qq --no-install-recommends ksmbd-tools >/dev/null
chroot "$R" apt-get clean
mkdir -p "$R/etc/ksmbd"
cat > "$R/etc/ksmbd/ksmbd.conf" <<'K'
; ksmbd (SMB3-server in de kernel) voor de ix2. Shares volgen na het RAID (fase 6).
; Aanzetten voor de vergelijkingstest: systemctl stop smbd; systemctl start ksmbd
[global]
	server string = ix2
	workgroup = WORKGROUP
	server min protocol = SMB2_10
	server signing = auto
	smb3 encryption = no
	durable handles = yes
	map to guest = never
	smb2 max read = 4MB
	smb2 max write = 4MB
	smb2 max trans = 4MB
	tcp port = 445
K
for u in ksmbd.service; do rm -f "$R/etc/systemd/system/multi-user.target.wants/$u"; done
rm -rf "$R/var/lib/apt/lists/"* "$R/usr/share/doc/"* "$R/usr/share/man/"* 2>/dev/null || true
echo "zram: $(grep compression "$R/etc/systemd/zram-generator.conf")"
echo "ksmbd-tools: $(grep -A1 "^Package: ksmbd-tools$" "$R/var/lib/dpkg/status" | grep -c "install ok installed") (1=ok)"
echo "ksmbd aan bij boot: $(ls "$R/etc/systemd/system/multi-user.target.wants/" | grep -c ksmbd) (0=uit)"
echo "smbd aan bij boot: $(ls "$R/etc/systemd/system/multi-user.target.wants/" | grep -c smbd)"
