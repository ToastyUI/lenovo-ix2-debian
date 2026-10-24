#!/bin/bash
# shellcheck disable=SC2015,SC2016  # ok/bad always return 0; the stub script body is meant literal
# Simulation tests for the TS-41x kit. Run as root on a Debian/Ubuntu x86 box (uses loop devices).
# Needs: python3 libubootenv-tool u-boot-tools device-tree-compiler busybox fdisk socat util-linux
#   sudo devices/qnap-ts41x/tests/run-sim-tests.sh [path/to/kirkwood-ts419-6281.dtb]
# Without a DTB the mkimage/installer tests are skipped.
set -euo pipefail
K=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); LOOPS=""
cleanup() { for l in $LOOPS; do losetup -d "$l" 2>/dev/null || true; done; rm -rf "$T"; }
trap cleanup EXIT
pass=0; fail=0
ok()  { echo "PASS $*"; pass=$((pass+1)); }
bad() { echo "FAIL $*"; fail=$((fail+1)); }
blank_env() { python3 -c "
import zlib,sys;b=b'\0'*(0x1000-4);open(sys.argv[1],'wb').write((zlib.crc32(b)&0xffffffff).to_bytes(4,'little')+b+b'\xff'*(0x40000-0x1000))" "$1"; }
fwcfg() { printf '%s 0x0 0x1000 0x40000 1\n' "$1" >"$1.cfg"; }

echo "== U-Boot env tool vs libubootenv"
cat >"$T/stock.txt" <<'E'
baudrate=115200
bootcmd=uart1 0x68;cp.l 0xf8200000 0x800000 0x80000;cp.l 0xf8400000 0xa00000 0x240000;bootm 0x800000
bootargs=console=ttyS0,115200 root=/dev/ram initrd=0xa00000,0x900000 ramdisk=32768
bootdelay=3
ethaddr=00:00:00:00:00:01
standalone=fsload 0x2000000 $(image_name);setenv bootargs $(console) root=/dev/mtdblock0 rw; bootm 0x2000000;
E
blank_env "$T/orig.bin"; fwcfg "$T/orig.bin"; fw_setenv -c "$T/orig.bin.cfg" -s "$T/stock.txt"
diff <(python3 "$K/tools/qnap-uboot-env.py" show "$T/orig.bin" 2>/dev/null | sort) <(fw_printenv -c "$T/orig.bin.cfg" | sort) >/dev/null \
  && ok "show == fw_printenv" || bad "show != fw_printenv"
python3 "$K/tools/ts41x-bootplan.py" stage2 --env "$T/orig.bin" --lba 0x800 -o "$T/x" 2>/dev/null && bad "stage2 without stage1 accepted" || ok "stage2 refused before stage1"
python3 "$K/tools/ts41x-bootplan.py" stage1 --env "$T/orig.bin" -o "$T/s1.txt" 2>/dev/null
python3 "$K/tools/qnap-uboot-env.py" set "$T/orig.bin" -s "$T/s1.txt" -o "$T/s1.bin" 2>/dev/null
cp "$T/s1.bin" "$T/c.bin"; fwcfg "$T/c.bin"
[ "$(fw_printenv -c "$T/c.bin.cfg" -n ts_probe_saveenv)" = pending ] && ok "stage1 readable by fw_printenv" || bad "stage1 not readable"
python3 "$K/tools/ts41x-bootplan.py" stage2 --env "$T/s1.bin" --lba 0x800 -o "$T/x" 2>/dev/null && bad "stage2 accepted with probe pending" || ok "stage2 refused while probe pending"
printf 'ts_probe_saveenv=ok\nbootcmd=run bootcmd_stock\n' >"$T/sim.txt"   # what U-Boot's probe does
python3 "$K/tools/qnap-uboot-env.py" set "$T/s1.bin" -s "$T/sim.txt" -o "$T/ok.bin" 2>/dev/null
python3 "$K/tools/ts41x-bootplan.py" stage2 --env "$T/ok.bin" --lba 0x1035a8 -o "$T/s2.txt" 2>/dev/null && ok "stage2 generated"
awk -F= '/^(bootcmd|ts_hdd|ts_boot)/{ if (length($0)-length($1)-1 > 200) exit 1 }' "$T/s2.txt" && ok "executed vars <= 200 chars" || bad "command too long"
python3 "$K/tools/ts41x-bootplan.py" stage2 --env "$T/ok.bin" --usb --lba 0x1035a8 --pic-led -o "$T/s2u.txt" 2>/dev/null \
  && grep -q '^bootcmd_debian=setenv bootcmd run bootcmd_fallback; saveenv; uart1 0x58; run ts_usb; run ts_hdd; run bootcmd_fallback$' "$T/s2u.txt" \
  && ok "stage2 --usb --lba: disarm, then USB, then disks, then QTS" || bad "usb chain"
awk -F= '/^(bootcmd|ts_usb|ts_hdd|ts_boot)/{ if (length($0)-length($1)-1 > 200) exit 1 }' "$T/s2u.txt" && ok "usb chain vars <= 200 chars" || bad "usb chain too long"
python3 "$K/tools/ts41x-bootplan.py" stage2 --env "$T/ok.bin" --disk-ext2 0:1 -o "$T/s2e.txt" 2>/dev/null \
  && grep -q '^ts_ext2=ide reset; mw 0x800000 0 1; ext2load ide 0:1 0x800000 /boot.uimg; run ts_boot$' "$T/s2e.txt" \
  && ok "stage2 --disk-ext2: ext2load ide from a SATA disk" || bad "disk-ext2 chain"
python3 "$K/tools/ts41x-bootplan.py" stage2 --env "$T/ok.bin" --usb -o "$T/s2w.txt" 2>"$T/warn.txt" \
  && grep -qi "no 'usb' command" "$T/warn.txt" && ok "stage2 --usb warns it is unavailable on stock U-Boot" || bad "usb warning"
python3 "$K/tools/ts41x-bootplan.py" stage2 --env "$T/ok.bin" -o "$T/x" 2>/dev/null && bad "stage2 without source accepted" || ok "stage2 refused without a source"
python3 "$K/tools/qnap-uboot-env.py" set "$T/ok.bin" -s "$T/s2.txt" -o "$T/s2.bin" 2>/dev/null
python3 "$K/tools/ts41x-bootplan.py" restore --env "$T/s2.bin" -o "$T/r.txt" 2>/dev/null
python3 "$K/tools/qnap-uboot-env.py" set "$T/s2.bin" -s "$T/r.txt" -o "$T/r.bin" 2>/dev/null
diff <(python3 "$K/tools/qnap-uboot-env.py" show "$T/orig.bin" 2>/dev/null | sort) <(python3 "$K/tools/qnap-uboot-env.py" show "$T/r.bin" 2>/dev/null | sort) >/dev/null \
  && ok "restore == original" || bad "restore differs"
cp "$T/r.bin" "$T/bad.bin"; printf X | dd of="$T/bad.bin" bs=1 seek=99 conv=notrunc 2>/dev/null
python3 "$K/tools/qnap-uboot-env.py" show "$T/bad.bin" >/dev/null 2>&1 && bad "corrupt env accepted" || ok "corrupt env refused"

DTB=${1:-}
if [ -n "$DTB" ]; then
  echo "== mkimage + installer on loop disks (QTS layout)"
  head -c 3000000 /dev/urandom >"$T/zImage"; head -c 6000000 /dev/urandom >"$T/initrd"
  bash "$K/tools/ts41x-mkimage.sh" "$T/zImage" "$DTB" "$T/initrd" "$T/boot.uimg" test >/dev/null && ok "multi-image built"
  disks=""
  for i in 0 1 2 3; do
    truncate -s 1500M "$T/d$i"
    printf 'label: dos\nstart=40, size=1060224, type=83\nstart=1060264, size=1060224, type=82\nstart=2120488, type=83\n' | sfdisk -q "$T/d$i"
    L=$(losetup -fP --show "$T/d$i"); LOOPS="$LOOPS $L"; partx -a "$L" 2>/dev/null || true; disks="$disks ${L#/dev/}"
  done
  sleep 1
  busybox sh "$K/tools/ts41x-install-boot.sh" --image "$T/boot.uimg" --mode qts --disks "$disks" --write >"$T/inst.log" 2>&1 \
    && [ "$(grep -c verified "$T/inst.log")" = 4 ] && ok "written + verified on 4 disks" || { cat "$T/inst.log"; bad "install"; }
  grep -q "lba 0x1035a8" "$T/inst.log" && ok "LBA 0x1035a8 as expected" || bad "unexpected LBA"
  # shellcheck disable=SC2086
  first=$(echo $disks | cut -d' ' -f4)   # check the last disk independently
  dd if="/dev/$first" bs=512 skip=1062312 count=$(( ($(stat -c%s "$T/boot.uimg")+511)/512 )) 2>/dev/null \
    | head -c "$(stat -c%s "$T/boot.uimg")" | cmp -s - "$T/boot.uimg" && ok "independent read-back" || bad "read-back"
  busybox sh "$K/tools/ts41x-install-boot.sh" --image "$T/zImage" --mode qts --disks "$disks" >/dev/null 2>&1 && bad "non-uImage accepted" || ok "non-uImage refused"
  busybox sh "$K/tools/ts41x-install-boot.sh" --image "$T/boot.uimg" --mode raw --disks "$disks" >/dev/null 2>&1 && bad "overlap accepted" || ok "raw overlap refused"
fi

echo "== PIC over a pty pair"
export TS41X_PIC_TTY="$T/pic"
mkdir -p "$T/bin" /run/lock; printf '#!/bin/sh\necho "$0 $*" >>%s/log\n' "$T" | tee "$T/bin/logger" >"$T/bin/systemctl"; chmod +x "$T/bin/"*
socat pty,raw,echo=0,link="$T/pic" pty,raw,echo=0,link="$T/host" & sp=$!; sleep 1
(stdbuf -o0 od -An -v -tx1 -w1 "$T/host" >"$T/sent") & op=$!
cp "$K/config/usr-local-sbin/"ts41x-* /usr/local/sbin/   # picd calls the others by absolute path
PATH="$T/bin:$PATH" timeout 6 /usr/local/sbin/ts41x-picd & pd=$!; sleep 1
printf '\xa3' >"$T/host"; sleep .5; printf '\xb4' >"$T/host"; sleep .5; printf '\x40' >"$T/host"; sleep 1.5
kill $pd $op $sp 2>/dev/null || true; wait 2>/dev/null || true
sent=$(tr -d ' \n' <"$T/sent")
[ "$sent" = "313350" ] && ok "35C->silence, 52C->medium, button->beep (sent $sent)" || bad "PIC bytes $sent"
grep -q "systemctl poweroff" "$T/log" && ok "power button -> poweroff" || bad "no poweroff"

echo "== $pass passed, $fail failed"; [ "$fail" = 0 ]
