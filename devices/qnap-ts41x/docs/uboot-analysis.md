# What the TS-41x stock U-Boot can do (from QNAP's GPL source)

Determined without the hardware, from QNAP's own GPL release
**GPL_QTS-4.3.x-20161219.tar.gz** (QTS 4.3.3, the TS-412's final firmware line),
`GPL_TS/src/u-boot-1.1.4/`, board **mv_kw** (Kirkwood 88F6281). The real unit's
`strings /dev/mtdblock0` (inventory step) is still the final confirmation for that
exact flash, but this is what QNAP built and shipped.

## Command set (`include/configs/mv_kw.h`, `CONFIG_CMD_BASIC`)

mv_kw does **not** define `MV_TINY_IMAGE`, so the full `#else` branch applies.
It defines `MV_INCLUDE_INTEG_SATA`, so the SATA-gated commands stay in.

| Command | Present | Source |
|---|---|---|
| `run`, `setenv`, `saveenv`, `bootm`, `mw`, `cp.l` | yes | `CFG_CMD_RUN` in the non-TINY branch; env/memory always |
| `ide reset` / `ide read` | yes | `CFG_CMD_IDE`, kept by `MV_INCLUDE_INTEG_SATA` |
| `ext2load ide 0:1 <addr> /path` | yes | `CFG_CMD_EXT2`; `cmd_ext2.c get_dev()` has the `ide` branch |
| `dhcp`, `ping`, `tftpboot`, `bootp` | yes | `CFG_CMD_DHCP`/`CFG_CMD_NET` |
| `nand`, `i2c`, `pci`, `jffs2`, `date` | yes | respective `CFG_CMD_*` |
| **`usb` (any usb subcommand)** | **NO** | no `CFG_CMD_USB` in any branch |
| **`ext2load usb` / `fatload usb`** | **NO** | `cmd_ext2.c`: the `usb` branch is `#if CFG_CMD_USB && CONFIG_USB_STORAGE`, neither defined |
| `fatload` (generally) | no | `CFG_CMD_FAT` only via `MV_MMC`, not set |

`MV_INCLUDE_USB` is defined, but it only compiles the USB HAL and sets host/device
mode from the `usb0Mode` env var (`mv_kw/mv_main.c`); it does **not** add a `usb`
boot command. Ident string: `" Marvell version: 3.4.4"` (no `-TINY`).

## Consequences for this kit

- **USB boot is not possible on the stock bootloader.** `ts41x-bootplan.py --usb`
  therefore does not apply to a TS-41x running its own U-Boot. It is kept only for a
  reflashed/custom U-Boot that adds `CFG_CMD_USB`; the analyzer and `--usb` warn about this.
- **The disk route is fully supported**: `ide read` of the raw boot area (default,
  leaves the QTS partition table intact) and `run`/`saveenv` for the one-shot guard.
- **Cleaner disk option, also source-confirmed:** `ext2load ide 0:1 0x800000 /boot.uimg`
  reads the image from an ext2 filesystem on a SATA disk, so no raw-sector area is needed.
  It requires a small ext2 partition on a disk (so it suits a disk fully given to Debian,
  not the keep-QTS-intact case). See `ts41x-bootplan.py --disk-ext2`.
