#!/bin/bash
# Build the boot image U-Boot loads from disk: one uImage of type "multi" with
# (zImage + appended DTB) as part 1 and the initramfs as part 2.
# One image = one CRC over everything: a half-written or missing initrd makes bootm
# return with an error (fallback to QTS) instead of booting a broken system.
#
#   ts41x-mkimage.sh <zImage|vmlinuz> <dtb> <initrd.img> <out.uimg> [name]
#
# The DTB gets a "read-only" flag on the U-Boot flash partition, so Debian cannot
# overwrite the bootloader by accident. Needs: mkimage (u-boot-tools), fdtput (device-tree-compiler).
set -euo pipefail
[ $# -ge 4 ] || { sed -n '2,10p' "$0"; exit 2; }
ZIMG=$1 DTB=$2 INITRD=$3 OUT=$4 NAME=${5:-Debian TS-41x}
MAX=$((0x18000 * 512))
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

cp "$DTB" "$tmp/board.dtb"
UBOOT_PART=/ocp@f1000000/spi@10600/m25p128@0/partition@0
[ "$(fdtget "$tmp/board.dtb" $UBOOT_PART label)" = "U-Boot" ] || { echo "unexpected DTB layout: $UBOOT_PART is not U-Boot" >&2; exit 1; }
fdtput -t s "$tmp/board.dtb" $UBOOT_PART read-only ""
cat "$ZIMG" "$tmp/board.dtb" >"$tmp/zImage.fdt"
mkimage -A arm -O linux -T multi -C none -a 0x00008000 -e 0x00008000 -n "${NAME:0:31}" \
  -d "$tmp/zImage.fdt:$INITRD" "$OUT" >/dev/null
size=$(stat -c %s "$OUT")
[ "$size" -le "$MAX" ] || { echo "image $size bytes > area $MAX" >&2; rm -f "$OUT"; exit 1; }
mkimage -l "$OUT"
