#!/bin/bash
# Build a minimal Debian 13 (trixie) armel rootfs for the QNAP TS-41x (TS-410/412/419P/...),
# plus the U-Boot boot image (kernel + DTB + initramfs as one multi-image).
#
#   sudo devices/qnap-ts41x/build-rootfs.sh <linux-image-*.deb> <authorized_keys> [workdir]
#
# Run on an x86/arm64 Debian/Ubuntu host as root, preferably in a throwaway VM/container.
# Needs: debootstrap, qemu-user-static + binfmt-support (armel chroot), u-boot-tools,
# device-tree-compiler, zstd. Output in <workdir>/out: rootfs.tar.zst, rootfs.tar.gz (for QTS) and boot.uimg.
#
# Services are installed but only the base ones are enabled; transmission, minidlna,
# WireGuard and the photo SFTP account need site-specific settings first (see docs/handleiding.md).
set -euo pipefail
KDEB=$(readlink -f "${1:?linux-image .deb}")
KEYS=$(readlink -f "${2:?authorized_keys}")
W=$(readlink -f "${3:-/root/ts41x}")
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
R=$W/rootfs OUT=$W/out
DTB=kirkwood-ts419-6281.dtb
export DEBIAN_FRONTEND=noninteractive LC_ALL=C
[ "$(id -u)" = 0 ] || { echo "run as root" >&2; exit 1; }
for t in debootstrap mkimage fdtget fdtput zstd; do
  command -v "$t" >/dev/null || { echo "missing tool: $t" >&2; exit 1; }
done
[ -e /proc/sys/fs/binfmt_misc/qemu-arm ] || { echo "no qemu-arm binfmt handler (install qemu-user-static binfmt-support)" >&2; exit 1; }
mkdir -p "$W" "$OUT"

echo "[1/8] debootstrap trixie armel (minbase) $(date +%T)"
rm -rf "$R"; mkdir -p "$R"
debootstrap --arch=armel --variant=minbase \
  --include=systemd-sysv,udev,kmod,dbus,initramfs-tools,systemd-resolved,systemd-timesyncd,systemd-zram-generator,openssh-server,openssh-sftp-server,nfs-kernel-server,ksmbd-tools,mdadm,lvm2,smartmontools,hd-idle,nftables,libubootenv-tool,u-boot-tools,device-tree-compiler,unattended-upgrades,ca-certificates,msmtp-mta,iproute2,iputils-ping,nano,less,sudo,e2fsprogs,cpio,zstd,coreutils,util-linux \
  trixie "$R" http://deb.debian.org/debian

echo "[2/8] extra packages (installed, not yet enabled) $(date +%T)"
cat >"$R/etc/apt/sources.list" <<S
deb http://deb.debian.org/debian trixie main
deb http://deb.debian.org/debian trixie-updates main
deb http://security.debian.org/debian-security trixie-security main
S
mount --bind /proc "$R/proc"; mount --bind /sys "$R/sys"; mount --bind /dev "$R/dev"; mount --bind /dev/pts "$R/dev/pts"
trap 'umount "$R/dev/pts" "$R/dev" "$R/sys" "$R/proc" 2>/dev/null || true' EXIT
printf '#!/bin/sh\nexit 101\n' >"$R/usr/sbin/policy-rc.d"; chmod +x "$R/usr/sbin/policy-rc.d"
chroot "$R" apt-get update -qq
chroot "$R" apt-get install -y -qq --no-install-recommends transmission-daemon minidlna wireguard-tools qrencode

echo "[3/8] base configuration $(date +%T)"
echo nas >"$R/etc/hostname"
printf '127.0.0.1\tlocalhost\n127.0.1.1\tnas\n' >"$R/etc/hosts"
cat >"$R/etc/fstab" <<F
LABEL=rootfs  /     ext4   defaults,noatime,commit=60  0 1
tmpfs         /tmp  tmpfs  defaults,size=32m           0 0
# data array, see docs/handleiding.md, e.g.:
# /dev/vg288/lv1  /srv/data  ext4  noatime,nofail,x-systemd.device-timeout=60s  0 2
F
ln -sf /usr/share/zoneinfo/Europe/Amsterdam "$R/etc/localtime"; echo Europe/Amsterdam >"$R/etc/timezone"
mkdir -p "$R/etc/systemd/network"
printf '[Match]\nType=ether\n[Network]\nDHCP=yes\n' >"$R/etc/systemd/network/10-wired.network"
install -d -m 700 "$R/root/.ssh"; install -m 600 "$KEYS" "$R/root/.ssh/authorized_keys"
sed -i 's/^COMPRESS=.*/COMPRESS=xz/' "$R/etc/initramfs-tools/initramfs.conf"
grep -q '^COMPRESS=' "$R/etc/initramfs-tools/initramfs.conf" || echo COMPRESS=xz >>"$R/etc/initramfs-tools/initramfs.conf"
mkdir -p "$R/srv/data"
# Optional for a first install without a working key: TS41X_TEMP_ROOTPW=1 sets root/root and
# allows password login from private addresses only. Remove after the first login (see file).
if [ "${TS41X_TEMP_ROOTPW:-}" = 1 ]; then
  echo root:root | chroot "$R" chpasswd
  cat >"$R/etc/ssh/sshd_config.d/05-temp-root-password.conf" <<P
# TEMPORARY: root/root over SSH from private addresses only. After the first login:
#   rm /etc/ssh/sshd_config.d/05-temp-root-password.conf && passwd root && systemctl reload ssh
Match Address 10.0.0.0/8,172.16.0.0/12,192.168.0.0/16
    PermitRootLogin yes
    PasswordAuthentication yes
P
  echo "WARNING: temporary root password 'root' enabled for LAN SSH logins"
fi

echo "[4/8] shared Kirkwood/256 MB tuning from the repo $(date +%T)"
for f in etc/systemd/zram-generator.conf etc/sysctl.d/90-ix2.conf etc/systemd/journald.conf.d/ix2.conf \
         etc/nfs.conf.d/ix2.conf etc/systemd/system/nfs-server.service.d/10-blocksize.conf; do
  install -D -m 644 "$REPO/config/$f" "$R/${f/ix2/kirkwood}"
done

echo "[5/8] TS-41x files $(date +%T)"
(cd "$HERE/config" && find etc -type f) | while read -r f; do
  install -D -m 644 "$HERE/config/$f" "$R/$f"
done
chmod 755 "$R/etc/kernel/postinst.d/zz-ts41x-boot" "$R/etc/initramfs/post-update.d/ts41x-boot" \
  "$R/etc/initramfs-tools/hooks/ts41x-pic" "$R"/etc/initramfs-tools/scripts/*/ts41x-pic
install -m 755 "$HERE"/config/usr-local-sbin/* "$R/usr/local/sbin/"
install -m 755 "$HERE/tools/ts41x-mkimage.sh" "$R/usr/local/sbin/ts41x-mkimage"
install -m 755 "$HERE/tools/ts41x-install-boot.sh" "$R/usr/local/sbin/ts41x-install-boot"
# No /etc/ts41x/boot.conf here on purpose: without it the kernel hook never touches disks,
# so installing the kernel in this chroot cannot write to the BUILD HOST's disks.
cp "$R/etc/mdadm/mdadm.conf.example" "$R/etc/mdadm/mdadm.conf"
# Home LAN for the firewall, e.g. TS41X_LAN=192.168.2.0/24 (without it SSH stays closed)
if [ -n "${TS41X_LAN:-}" ]; then
  sed -i "s|^define LAN = .*|define LAN = { $TS41X_LAN }|" "$R/etc/nftables.conf"
fi

echo "[6/8] services $(date +%T)"
chroot "$R" systemctl enable systemd-networkd systemd-resolved systemd-timesyncd ssh nftables \
  smartmontools hd-idle ts41x-picd ts41x-leds ts41x-boot-ok ts41x-ssh-hostkeys >/dev/null 2>&1
chroot "$R" systemctl disable transmission-daemon minidlna >/dev/null 2>&1 || true
ln -sf /run/systemd/resolve/stub-resolv.conf "$R/etc/resolv.conf"

echo "[7/8] kernel $(basename "$KDEB") $(date +%T)"
cp "$KDEB" "$R/tmp/k.deb"
chroot "$R" dpkg -i /tmp/k.deb   # boot hook skips: no boot.conf, and not running on a TS-41x
kver=$(dpkg-deb -f "$KDEB" Package | sed 's/^linux-image-//')
[ -f "$R/boot/initrd.img-$kver" ] || chroot "$R" update-initramfs -c -k "$kver"
rm -f "$R/tmp/k.deb" "$R/usr/sbin/policy-rc.d"

echo "[8/8] boot image + rootfs tarball $(date +%T)"
dtb=$(find "$R/usr/lib/linux-image-$kver" -name "$DTB" | head -1)
"$HERE/tools/ts41x-mkimage.sh" "$R/boot/vmlinuz-$kver" "$dtb" "$R/boot/initrd.img-$kver" "$OUT/boot.uimg" "Debian $kver"
chroot "$R" apt-get clean
rm -rf "$R/var/lib/apt/lists/"* "$R/usr/share/doc/"* "$R/usr/share/man/"*
# The tarball is shared between units: no SSH host keys (ts41x-ssh-hostkeys makes them on
# first boot) and an empty machine-id (systemd fills it on first boot).
rm -f "$R"/etc/ssh/ssh_host_*; : >"$R/etc/machine-id"
# unmount the chroot mounts first (recursive: /sys can carry submounts such as efivars)
umount -R "$R/dev" "$R/sys" "$R/proc" 2>/dev/null || true
trap - EXIT
tar -C "$R" --numeric-owner --one-file-system -cf - . | zstd -q -T0 -o "$OUT/rootfs.tar.zst"
# .tar.gz for unpacking on stock QTS, whose busybox tar has no zstd
tar -C "$R" --numeric-owner --one-file-system -cf - . | gzip -6 >"$OUT/rootfs.tar.gz"
(cd "$OUT" && sha256sum boot.uimg rootfs.tar.zst rootfs.tar.gz >SHA256SUMS)
ls -l "$OUT"
