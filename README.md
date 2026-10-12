# lenovo-ix2-debian

Debian 13 (trixie) on a **Lenovo ix2 (ix2-ng)** NAS, booted from a USB stick, with a stock-firmware fallback.

| | |
|---|---|
| Hardware | Marvell Kirkwood 88F6282 (ARMv5TE, 1 core), 256 MB RAM, 512 KB SPI flash (U-Boot 0.0.8), 2× SATA, 1× USB 2.0, 1 GbE |
| Userland | Debian 13 armel, minimal (debootstrap `minbase`, ~420 MB) |
| Kernel A | bodhi's `7.1.9-kirkwood-tld-1` (forum.doozan.com) |
| Kernel B | `7.1.9-ix2perf-1`: same source, patch and config as A, plus MGLRU, PSI and zram LZ4/ZSTD recompression. **Default**: 13–31% faster reads |
| Storage | md RAID 1 (internal bitmap) + ext4 `fast_commit` on the data partitions; the LifeLine system array and boot sectors are left intact |
| Sharing | NFS v4.2 only; SMB via ksmbd (in-kernel) or Samba 4.22 |

## Layout

```
docs/       handleiding.md (Dutch step-by-step guide), kernel-options.md, benchmarks.md
bench/      fio scripts used for docs/benchmarks.md
rootfs/     build.sh (debootstrap rootfs + kernel A), tune.sh / tune2.sh (performance tuning), add-kernel-b.sh
kernel/     build-kernel.sh, full configs for A and B, config.diff (A -> B)
uboot/      fw_setenv-usb-boot.sh (USB boot with fallback), redacted U-Boot environments
config/     live configuration from the running ix2 (etc/, usr-local-sbin/)
```

Binary artifacts (kernel B `.deb`, `uImage`/`uInitrd` for A and B, DTB) are attached to the GitHub **Release**, not stored in git.

## Boot flow

1. U-Boot runs `usb reset; run usb_bootcmd` and loads `/uImage` + `/uInitrd` from the stick's ext2 partition.
2. If that fails, `mw 0x800000 0 1` guarantees `bootm` fails cleanly and U-Boot runs `bootcmd_stock` (stock LifeLine from disk).
3. Pull the stick to get LifeLine back. **If LifeLine ever offers to "initialize" storage, decline: it would wipe the data array.**

Switch kernels on the ix2 with `kies-kernel A` or `kies-kernel B`, then `reboot`.

## Credits and licenses

- Kernel sources: kernel.org, GPL-2.0. Kirkwood patch, base config and kernel A packages: **bodhi**, [forum.doozan.com](https://forum.doozan.com/read.php?2,12096) (GPL-2.0).
- Debian packages: their respective licenses.
- Scripts and documentation in this repository: private, all rights reserved.
