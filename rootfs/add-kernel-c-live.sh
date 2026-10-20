#!/bin/bash
# Installeert kernel C (7.1.9-ix2c-1) op de draaiende ix2 (stick in de NAS), vanaf een machine
# die Proxmox (bouwhost, u-boot-tools) en via Proxmox de ix2 bereikt. Wisselen: kies-kernel C; reboot
set -euo pipefail
KEY=~/.ssh/id_ed25519; KH=${KH:-$HOME/.ssh/known_hosts_ix2}; C=7.1.9-ix2c-1; O=/root/ix2/kc/out
PVE() { ssh -i $KEY -o BatchMode=yes root@192.0.2.2 "$@"; }
IX2() { ssh -i $KEY -o BatchMode=yes -o UserKnownHostsFile=$KH \
        -o "ProxyCommand=ssh -i $KEY -o BatchMode=yes -W %h:%p root@192.0.2.2" root@192.0.2.100 "$@"; }
echo "[1/4] pakket + DTB naar de ix2"
PVE "cat $O/linux-image-${C}_1_armel.deb" | IX2 "cat > /tmp/k.deb"
PVE "cat $O/kirkwood-lenovo-ix2-ng.dtb"   | IX2 "cat > /boot/dts/kirkwood-lenovo-ix2-ng.ix2c.dtb"
echo "[2/4] dpkg -i + initramfs op de ix2 (traag op ARMv5)"
IX2 "dpkg -i /tmp/k.deb | tail -2; rm /tmp/k.deb; [ -f /boot/initrd.img-$C ] || update-initramfs -c -k $C; ls -la /boot/vmlinuz-$C /boot/initrd.img-$C"
echo "[3/4] uImage.C / uInitrd.C maken op Proxmox"
T=/root/ix2/kc/uimg; PVE "rm -rf $T; mkdir -p $T"
IX2 "cat /boot/vmlinuz-$C /boot/dts/kirkwood-lenovo-ix2-ng.ix2c.dtb" | PVE "cat > $T/zImage.fdt"
IX2 "cat /boot/initrd.img-$C" | PVE "cat > $T/initrd"
PVE "cd $T && mkimage -A arm -O linux -T kernel -C none -a 0x00008000 -e 0x00008000 -n Linux-$C -d zImage.fdt uImage.C >/dev/null \
  && mkimage -A arm -O linux -T ramdisk -C gzip -a 0 -e 0 -n initramfs-$C -d initrd uInitrd.C >/dev/null && sha256sum uImage.C uInitrd.C"
PVE "cat $T/uImage.C"  | IX2 "cat > /boot/uImage.C"
PVE "cat $T/uInitrd.C" | IX2 "cat > /boot/uInitrd.C"
IX2 "sync; sha256sum /boot/uImage.C /boot/uInitrd.C"
echo "[4/4] kies-kernel uitbreiden met C"
IX2 "sed -i 's/A|B) ;;/A|B|C) ;;/; s/kies-kernel A|B /kies-kernel A|B|C /; s/^  B) alg=/  B|C) alg=/; s/(A = bodhi, B = eigen ix2perf met MGLRU)/(A = bodhi, B = ix2perf MGLRU, C = B zonder hardening)/' /usr/local/sbin/kies-kernel; grep -nE 'A\|B|alg=' /usr/local/sbin/kies-kernel"
