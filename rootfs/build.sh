#!/bin/bash
# Bouwt een minimale Debian 13 (trixie) armel rootfs voor de Lenovo ix2-ng,
# met de kernel van bodhi (7.1.9-kirkwood-tld-1, doozan-forum).
# Draaien op de Proxmox-host als root, of liever in een wegwerp-VM/-container.
# Verwacht in /root/ix2: map k/ met het uitgepakte bodhi-kernelpakket en authorized_keys.
set -euo pipefail
W=/root/ix2; R=$W/rootfs; K=$W/k; KVER=7.1.9-kirkwood-tld-1
export DEBIAN_FRONTEND=noninteractive LC_ALL=C

echo "[1/7] debootstrap trixie armel (minbase) $(date +%T)"
rm -rf "$R"; mkdir -p "$R"
debootstrap --arch=armel --variant=minbase \
  --include=systemd-sysv,udev,kmod,dbus,initramfs-tools,systemd-resolved,systemd-timesyncd,openssh-server,nfs-kernel-server,mdadm,smartmontools,nftables,libubootenv-tool,unattended-upgrades,ca-certificates,iproute2,iputils-ping,nano,less,sudo,e2fsprogs,cpio,zstd \
  trixie "$R" http://deb.debian.org/debian

echo "[2/7] basisconfiguratie $(date +%T)"
cat > "$R/etc/apt/sources.list" <<S
deb http://deb.debian.org/debian trixie main
deb http://deb.debian.org/debian trixie-updates main
deb http://security.debian.org/debian-security trixie-security main
S
echo ix2 > "$R/etc/hostname"
printf '127.0.0.1\tlocalhost\n127.0.1.1\tix2\n' > "$R/etc/hosts"
cat > "$R/etc/fstab" <<F
LABEL=rootfs  /      ext4  defaults,noatime,commit=60  0 1
LABEL=BOOT    /boot  ext2  defaults,noatime            0 2
tmpfs         /tmp   tmpfs defaults,size=32m           0 0
F
ln -sf /usr/share/zoneinfo/Europe/Amsterdam "$R/etc/localtime"; echo Europe/Amsterdam > "$R/etc/timezone"

# Netwerk: elk ethernet-apparaat via DHCP (de naam kan eth0 of end0 zijn)
mkdir -p "$R/etc/systemd/network"
cat > "$R/etc/systemd/network/10-wired.network" <<N
[Match]
Type=ether
[Network]
DHCP=yes
N

# SSH: root alleen met sleutel
mkdir -p "$R/root/.ssh"; cp "$W/authorized_keys" "$R/root/.ssh/authorized_keys"
chmod 700 "$R/root/.ssh"; chmod 600 "$R/root/.ssh/authorized_keys"
mkdir -p "$R/etc/ssh/sshd_config.d"
printf 'PermitRootLogin prohibit-password\nPasswordAuthentication no\n' > "$R/etc/ssh/sshd_config.d/10-ix2.conf"

# U-Boot env in SPI-flash: in de DTB is mtd2 = "u-boot env" (0x7f000), mtd1 = "u-boot env2" (0x7e000)
printf '/dev/mtd2  0x0  0x1000  0x1000\n/dev/mtd1  0x0  0x1000  0x1000\n' > "$R/etc/fw_env.config"

# initramfs met gzip (past bij U-Boot en de kernel)
sed -i 's/^COMPRESS=.*/COMPRESS=gzip/' "$R/etc/initramfs-tools/initramfs.conf"
grep -q '^COMPRESS=' "$R/etc/initramfs-tools/initramfs.conf" || echo COMPRESS=gzip >> "$R/etc/initramfs-tools/initramfs.conf"

# Ventilator-/temperatuurchip ADT7473
echo adt7475 > "$R/etc/modules-load.d/ix2-fan.conf"

echo "[3/7] diensten aanzetten $(date +%T)"
chroot "$R" systemctl enable systemd-networkd systemd-resolved systemd-timesyncd ssh nftables >/dev/null 2>&1 || true
ln -sf /run/systemd/resolve/stub-resolv.conf "$R/etc/resolv.conf"

echo "[4/7] kernel $KVER installeren $(date +%T)"
cp "$K/linux-image-${KVER}_1_armel.deb" "$R/tmp/"
mount --bind /proc "$R/proc"; mount --bind /sys "$R/sys"; mount --bind /dev "$R/dev"
trap 'umount "$R/dev" "$R/sys" "$R/proc" 2>/dev/null || true' EXIT
chroot "$R" dpkg -i "/tmp/linux-image-${KVER}_1_armel.deb"
chroot "$R" bash -c "[ -f /boot/initrd.img-$KVER ] || update-initramfs -c -k $KVER"
rm -f "$R/tmp/"*.deb

echo "[5/7] uImage + uInitrd met DTB ix2-ng $(date +%T)"
mkdir -p "$R/boot/dts"
tar -xf "$K/linux-dtb-${KVER}.tar" -C "$R/boot" dts/kirkwood-lenovo-ix2-ng.dtb
cp "$R/boot/vmlinuz-$KVER" "$R/boot/zImage.fdt" 2>/dev/null || cp "$K/zImage-$KVER" "$R/boot/zImage.fdt"
cat "$R/boot/dts/kirkwood-lenovo-ix2-ng.dtb" >> "$R/boot/zImage.fdt"
mkimage -A arm -O linux -T kernel  -C none -a 0x00008000 -e 0x00008000 -n "Linux-$KVER" -d "$R/boot/zImage.fdt" "$R/boot/uImage"
mkimage -A arm -O linux -T ramdisk -C gzip -a 0x00000000 -e 0x00000000 -n "initramfs-$KVER" -d "$R/boot/initrd.img-$KVER" "$R/boot/uInitrd"

echo "[6/7] opruimen $(date +%T)"
chroot "$R" apt-get clean
rm -rf "$R/var/lib/apt/lists/"* "$R/usr/share/doc/"* "$R/usr/share/man/"* 2>/dev/null || true

echo "[7/7] klaar $(date +%T)"
du -sh "$R"; ls -la "$R/boot"
