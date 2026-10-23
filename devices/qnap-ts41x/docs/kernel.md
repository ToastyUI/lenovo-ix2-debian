# Kernel for the TS-41x

Measured on 2026-10-24 in a cross-build (gcc 13.3 arm-linux-gnueabi), not yet booted:

| | |
|---|---|
| Source | vanilla linux-7.1.9.tar.xz, sha256 `3271a4ae…c072b0` (same tarball as the ix2 kernels) |
| Config | `kernel/config-7.1.9-ix2c-1` + `LOCALVERSION=-ts41xc-1`; `olddefconfig` only drops `RTC_DRV_HT1382` (ix2 RTC from the bodhi patch) |
| DTB | `kirkwood-ts419-6281.dtb` builds from mainline, 10,454 bytes |
| zImage | 5,040,536 bytes (XZ) |

The DTB covers what the board needs: UART0 console, UART1 for the PIC plus the
`qnap,power-off` node, s35390a RTC on I2C, SPI NOR with the six QNAP partitions, the SoC SATA
ports and PCIe (for the 88SX7042 that drives the four bays), both GbE ports, reset and
USB-copy buttons. Its memory node says 512 MB (TS-419P); on the 256 MB TS-412 the size from
U-Boot's ATAGs wins because `ARM_ATAG_DTB_COMPAT=y`.

## Consequence for the boot route

- Route A (this kit, image on disk): no size limit worth mentioning (48 MiB area).
- Route B (kernel in flash via qnap_mtd_resize): the kernel partition is 2 MiB stock and
  3 MiB after resizing. This 4.8 MiB zImage does **not** fit. Route B would need a trimmed
  config (Debian's own bookworm marvell kernel was 2.55 MiB, with most drivers as modules).
