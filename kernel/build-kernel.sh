#!/bin/bash
# Bouwt kernel B "ix2perf" voor de Lenovo ix2-ng: vanilla 7.1.9 + bodhi-patch + bodhi-config + MGLRU/PSI/geen preempt.
set -euo pipefail
W=/root/ix2/kb; K=/root/ix2/k; V=7.1.9; SHA=3271a4ae3897b38352980f2b0975bae61bca81c644d186221c5ae928bcc072b0
export ARCH=arm CROSS_COMPILE=arm-linux-gnueabi- KDEB_PKGVERSION=1
cd $W
echo "[1/6] bron downloaden $(date +%T)"
[ -f linux-$V.tar.xz ] || wget -q https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-$V.tar.xz
echo "$SHA  linux-$V.tar.xz" | sha256sum -c -
echo "[2/6] uitpakken + bodhi-patch $(date +%T)"
rm -rf linux-$V; tar -xf linux-$V.tar.xz; cd linux-$V
patch -p1 --quiet < $K/linux-$V-kirkwood-tld-1.patch
ls arch/arm/boot/dts/marvell/kirkwood-lenovo-ix2-ng.dts
echo "[3/6] config: bodhi + MGLRU + PSI + zram lz4/zstd/recompress $(date +%T)"
cp $K/config-$V-kirkwood-tld-1 .config
scripts/config --set-str LOCALVERSION "-ix2perf-1" --enable LRU_GEN --enable LRU_GEN_ENABLED --enable PSI --enable ZRAM_BACKEND_LZ4 --enable ZRAM_BACKEND_ZSTD --enable ZRAM_MULTI_COMP --enable ZRAM_TRACK_ENTRY_ACTIME
make olddefconfig >/dev/null
for o in LRU_GEN LRU_GEN_ENABLED PSI ZRAM_BACKEND_LZ4 ZRAM_BACKEND_ZSTD ZRAM_MULTI_COMP ZRAM_TRACK_ENTRY_ACTIME PREEMPT_VOLUNTARY LOCALVERSION; do grep -E "^(# )?CONFIG_$o[= ]" .config || echo "CONFIG_$o ontbreekt"; done
echo "[4/6] bouwen (7 cores, lage prioriteit) $(date +%T)"
nice -n 19 ionice -c3 make -j7 bindeb-pkg DPKG_FLAGS=-d >../build.out 2>&1 || { tail -40 ../build.out; exit 1; }
echo "[5/6] DTB en zImage apart zetten $(date +%T)"
mkdir -p $W/out; cp arch/arm/boot/zImage $W/out/zImage-$V-ix2perf-1
cp arch/arm/boot/dts/marvell/kirkwood-lenovo-ix2-ng.dtb $W/out/
cp ../linux-image-$V-ix2perf-1_*_armel.deb $W/out/
echo "[6/6] klaar $(date +%T)"; ls -la $W/out
