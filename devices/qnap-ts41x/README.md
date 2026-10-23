# QNAP TS-41x (TS-410 / TS-412 / TS-419P / TS-419U)

Debian 13 armel on the QNAP TS-41x, booted from the disks by the stock U-Boot, with stock QTS
kept in flash as an automatic fallback. Same rootfs, kernel configs and tuning as the ix2-ng
in the top-level of this repository.

**Status: kit, tested in simulation, not yet booted on a TS-412.** See "Tested" below.
Step-by-step guide (Dutch): [docs/handleiding.md](docs/handleiding.md).

| | |
|---|---|
| Hardware | Marvell 88F6281 1.2 GHz (ARMv5TE), 256 MB (TS-412) / 512 MB (TS-419P), 16 MB SPI NOR, 4 bays on a PCIe Marvell 88SX7042, PIC microcontroller on `/dev/ttyS1` |
| DTB | `kirkwood-ts419-6281.dtb` (mainline; no bodhi patch needed) |
| Kernel | vanilla 7.1.9 + `kernel/config-7.1.9-ix2c-1` (or `-ix2perf-1` for B) |
| Boot | U-Boot reads one multi-image (zImage+DTB+initramfs) with `ide read` from partition 2 (QTS swap) of every disk; one-shot guard falls back to QTS |
| Rootfs | USB stick, label `rootfs` |
| LEDs/fan/power | `ts41x-pic` / `ts41x-picd` (byte codes from qcontrol); `qnap-poweroff` in the kernel cuts power |

## Layout

```
tools/ts412-inventory.sh     read-only inventory on stock QTS (flash dumps, U-Boot, disks, SMART)
tools/ts412-analyze.py       verdict: which boot route this unit's U-Boot supports
tools/qnap-uboot-env.py      offline U-Boot env editor (CRC-checked, round-trip verified)
tools/ts41x-bootplan.py      env changes: stage1 (saveenv probe), stage2 (arm Debian), restore
tools/ts41x-mkimage.sh       multi-image builder; marks the U-Boot flash partition read-only in the DTB
tools/ts41x-install-boot.sh  writes the image to every disk (busybox-compatible, dry run by default)
kernel/build-kernel.sh       cross-build the kernel .deb
build-rootfs.sh              debootstrap rootfs + boot image
config/                      PIC/LED/alert scripts, systemd units, kernel hooks, service examples
tests/run-sim-tests.sh       simulation tests (env tools vs libubootenv, loop disks, PIC over a pty)
```

## Why one multi-image instead of uImage + uInitrd

Old U-Boot (1.1.x) resets the board when a separate ramdisk image has a bad header; a kernel
image with a bad header only makes `bootm` return. With one multi-image there is one header
and one CRC over kernel and initramfs, so any corruption ends in `bootm` returning and the QTS
fallback running in the same boot. Every executed U-Boot variable is kept under 200 characters,
because old U-Boot rejects command lines longer than its console buffer.

## Tested (simulation)

Reproduce with `sudo tests/run-sim-tests.sh path/to/kirkwood-ts419-6281.dtb` (16 checks).

- `qnap-uboot-env.py`: reads a TS-419P env written by libubootenv's `fw_setenv` identically
  to `fw_printenv`; its own output is read back correctly by `fw_printenv`; corrupt dumps refused;
  bytes after the env area untouched.
- `ts41x-bootplan.py`: refuses stage2 without stage1, refuses while the saveenv probe is pending,
  `restore` gives back exactly the original set of variables.
- `ts41x-install-boot.sh` under busybox sh on four loop disks with the QTS partition layout: same
  LBA as the analyzer, read-back verified, refuses overlapping partitions, differing layouts,
  non-multi images. (The active-swap guard is not exercised by the tests.)
- `ts41x-picd` / `ts41x-pic` against a pty pair: temperature -> fan curve with hysteresis,
  fan error -> red LED + alert, power button -> poweroff.
- Kernel 7.1.9 with kernel C config cross-compiles for the TS-419 DTB (see docs/kernel.md).
- All packages exist in Debian 13 armel.

## Not tested

Booting on real hardware; whether U-Boot sees the PCIe bays; whether `saveenv` persists
(stage1 checks it safely); whether the PIC sends temperatures unsolicited.

## Credits

PIC byte codes: qcontrol by Ian Campbell (GPL). Flash layout, env geometry and QTS recovery:
amouiche/qnap_mtd_resize_for_bullseye. Debian on QNAP: Martin Michlmayr. Kernel base config: bodhi.
