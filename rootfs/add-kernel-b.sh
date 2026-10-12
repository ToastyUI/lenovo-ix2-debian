#!/bin/bash
set -euo pipefail
R=/root/ix2/rootfs; O=/root/ix2/kb/out; A=7.1.9-kirkwood-tld-1; B=7.1.9-ix2perf-1
mount --bind /proc "$R/proc"; mount --bind /sys "$R/sys"; mount --bind /dev "$R/dev"
trap 'umount -l "$R/dev" "$R/sys" "$R/proc" 2>/dev/null || true' EXIT
cp $O/linux-image-${B}_1_armel.deb "$R/tmp/"
chroot "$R" dpkg -i "/tmp/linux-image-${B}_1_armel.deb" 2>&1 | grep -vE "^\(Reading|^Preparing|^Unpacking"
rm -f "$R/tmp/"*.deb
chroot "$R" bash -c "[ -f /boot/initrd.img-$B ] || update-initramfs -c -k $B"
cd "$R/boot"
# A bewaren onder eigen naam
cp -f uImage uImage.A; cp -f uInitrd uInitrd.A
# B maken met de ix2-ng DTB uit de eigen build
cp $O/kirkwood-lenovo-ix2-ng.dtb dts/kirkwood-lenovo-ix2-ng.ix2perf.dtb
cat vmlinuz-$B dts/kirkwood-lenovo-ix2-ng.ix2perf.dtb > zImage.B.fdt
mkimage -A arm -O linux -T kernel  -C none -a 0x00008000 -e 0x00008000 -n "Linux-$B" -d zImage.B.fdt uImage.B >/dev/null
mkimage -A arm -O linux -T ramdisk -C gzip -a 0x00000000 -e 0x00000000 -n "initramfs-$B" -d initrd.img-$B uInitrd.B >/dev/null
rm -f zImage.B.fdt
# wisselscript
cat > "$R/usr/local/sbin/kies-kernel" <<'K'
#!/bin/sh
# Gebruik: kies-kernel A|B   (A = bodhi, B = eigen ix2perf met MGLRU). Daarna: reboot
set -e; k="$1"; cd /boot
case "$k" in A|B) ;; *) echo "gebruik: kies-kernel A|B (nu: $(cat /boot/kernel-keuze 2>/dev/null || echo A))"; exit 1;; esac
cp -f "uImage.$k" uImage; cp -f "uInitrd.$k" uInitrd; sync
echo "$k" > /boot/kernel-keuze; sync
echo "Kernel $k gekozen. Herstart met: reboot"
K
chmod +x "$R/usr/local/sbin/kies-kernel"; echo A > "$R/boot/kernel-keuze"
ls -la "$R/boot" | grep -E "uImage|uInitrd|initrd.img|vmlinuz|keuze"
ls "$R/usr/lib/modules/"
