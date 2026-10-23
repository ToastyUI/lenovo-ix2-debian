#!/bin/bash
# Kernel for the QNAP TS-41x/TS-21x: vanilla Linux 7.1.9 with the ix2 kernel C (or B) config.
# No bodhi patch is needed: kirkwood-ts419-*.dts and kirkwood-ts219-*.dts are in mainline,
# and the config already has everything these boards use (sata_mv incl. the PCIe 88SX7042,
# PCI_MVEBU, s35390a RTC, qnap-poweroff, mv643xx_eth, SPI NOR, ATAG/appended-DTB support).
#
#   devices/qnap-ts41x/kernel/build-kernel.sh [C|B] [workdir]     (default C)
# Build deps: gcc-arm-linux-gnueabi bc bison flex libssl-dev libelf-dev debhelper rsync cpio kmod
# Output: <workdir>/out/linux-image-7.1.9-ts41x<c|b>-1_*_armel.deb, zImage, DTBs, .config
set -euo pipefail
VARIANT=${1:-C}; W=${2:-/root/ts41x/kernel}
V=7.1.9 SHA=3271a4ae3897b38352980f2b0975bae61bca81c644d186221c5ae928bcc072b0
REPO=$(cd "$(dirname "$0")/../../.." && pwd)
case $VARIANT in
  C) CFG=$REPO/kernel/config-7.1.9-ix2c-1; LV=-ts41xc-1 ;;
  B) CFG=$REPO/kernel/config-7.1.9-ix2perf-1; LV=-ts41xb-1 ;;
  *) echo "variant C or B" >&2; exit 2 ;;
esac
export ARCH=arm CROSS_COMPILE=arm-linux-gnueabi- KDEB_PKGVERSION=1
mkdir -p "$W"; cd "$W"
[ -f linux-$V.tar.xz ] || wget -q https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-$V.tar.xz
echo "$SHA  linux-$V.tar.xz" | sha256sum -c -
rm -rf linux-$V; tar -xf linux-$V.tar.xz; cd linux-$V
cp "$CFG" .config
scripts/config --set-str LOCALVERSION "$LV"
make olddefconfig >/dev/null
for o in SATA_MV PCI_MVEBU RTC_DRV_S35390A POWER_RESET_QNAP ARM_APPENDED_DTB ARM_ATAG_DTB_COMPAT MD_RAID10 WIREGUARD; do
  grep -q "^CONFIG_$o=y" .config || { echo "CONFIG_$o missing" >&2; exit 1; }
done
nice -n 19 make -j"$(nproc)" bindeb-pkg DPKG_FLAGS=-d >../build.out 2>&1 || { tail -40 ../build.out; exit 1; }
make -j"$(nproc)" dtbs >/dev/null
mkdir -p "$W/out"
cp arch/arm/boot/zImage "$W/out/zImage-$V$LV"
cp arch/arm/boot/dts/marvell/kirkwood-ts{2,4}19-628{1,2}.dtb "$W/out/"
cp .config "$W/out/config-$V$LV"
cp ../linux-image-$V${LV}_*_armel.deb "$W/out/"
ls -la "$W/out"
