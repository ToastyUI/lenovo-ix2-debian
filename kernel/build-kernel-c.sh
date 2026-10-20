#!/bin/bash
# Bouwt kernel C "ix2c" = kernel B + hardening/debug uit (minder CPU per byte op de ARMv5-kern).
# Gebruikt dezelfde bron en bodhi-patch als B (in /root/ix2/kb).
set -euo pipefail
W=/root/ix2/kc; K=/root/ix2/k; V=7.1.9; LV="-ix2c-1"
export ARCH=arm CROSS_COMPILE=arm-linux-gnueabi- KDEB_PKGVERSION=1
mkdir -p $W; cd $W
echo "[1/5] gepatchte bron van B kopieren $(date +%T)"
rm -rf linux-$V; cp -a /root/ix2/kb/linux-$V .; cd linux-$V
ls arch/arm/boot/dts/marvell/kirkwood-lenovo-ix2-ng.dts
echo "[2/5] config: B + hardening/debug uit $(date +%T)"
scripts/config --set-str LOCALVERSION "$LV" \
  --disable INIT_ON_ALLOC_DEFAULT_ON --disable INIT_ON_FREE_DEFAULT_ON \
  --disable HARDENED_USERCOPY --disable SLAB_FREELIST_HARDENED --disable SLAB_FREELIST_RANDOM \
  --disable SHUFFLE_PAGE_ALLOCATOR --disable RANDOM_KMALLOC_CACHES \
  --disable RANDOMIZE_KSTACK_OFFSET --disable RANDOMIZE_KSTACK_OFFSET_DEFAULT \
  --disable STACKPROTECTOR_STRONG --enable STACKPROTECTOR \
  --disable CPU_SW_DOMAIN_PAN \
  --disable AUDIT --disable SECURITY_SELINUX \
  --disable FTRACE --disable SCHEDSTATS --disable DYNAMIC_DEBUG --disable KALLSYMS_ALL --disable KSM
make olddefconfig >/dev/null
for o in LOCALVERSION INIT_ON_ALLOC_DEFAULT_ON HARDENED_USERCOPY SLAB_FREELIST_HARDENED RANDOM_KMALLOC_CACHES STACKPROTECTOR STACKPROTECTOR_STRONG CPU_SW_DOMAIN_PAN AUDIT FTRACE SCHEDSTATS LRU_GEN PSI ZRAM_MULTI_COMP CC_OPTIMIZE_FOR_SIZE; do grep -E "^(# )?CONFIG_$o[= ]" .config || echo "CONFIG_$o ontbreekt"; done
echo "[3/5] bouwen (7 cores, lage prioriteit) $(date +%T)"
nice -n 19 ionice -c3 make -j7 bindeb-pkg DPKG_FLAGS=-d >../build.out 2>&1 || { tail -40 ../build.out; exit 1; }
echo "[4/5] DTB, zImage, config apart zetten $(date +%T)"
mkdir -p $W/out; cp arch/arm/boot/zImage $W/out/zImage-$V$LV
cp arch/arm/boot/dts/marvell/kirkwood-lenovo-ix2-ng.dtb $W/out/
cp .config $W/out/config-$V$LV
cp ../linux-image-$V${LV}_*_armel.deb $W/out/
echo "[5/5] klaar $(date +%T)"; ls -la $W/out
