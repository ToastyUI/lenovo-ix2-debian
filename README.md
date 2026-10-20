# Lenovo ix2 Debian — community open-source upgrade

An independent community project providing build scripts, configuration examples and documentation to run Debian 13 (trixie) on a **Lenovo ix2 (ix2-ng)** NAS, booted from a USB stick, with a stock-firmware fallback.

| | |
|---|---|
| Hardware | Marvell Kirkwood 88F6282 (ARMv5TE, 1 core), 256 MB RAM, 512 KB SPI flash (U-Boot 0.0.8), 2× SATA, 1× USB 2.0, 1 GbE |
| Userland | Debian 13 armel, minimal (debootstrap `minbase`, ~420 MB) |
| Kernel A | bodhi's `7.1.9-kirkwood-tld-1` (forum.doozan.com) |
| Kernel B | `7.1.9-ix2perf-1`: same source, patch and config as A, plus MGLRU, PSI and zram LZ4/ZSTD recompression |
| Kernel C | `7.1.9-ix2c-1`: B minus kernel hardening and tracing. **Default**: NFS reads ~100–108 MiB/s (+35% over B, +53% over A) |
| Storage | md RAID 1 (internal bitmap) + ext4 `fast_commit` on the data partitions; the LifeLine system array and boot sectors are left intact |
| Sharing | NFS v4.2 only; SMB via ksmbd (in-kernel) or Samba 4.22 |

## Layout

```
docs/       handleiding.md (Dutch step-by-step guide), kernel-options.md, benchmarks.md
bench/      fio scripts used for docs/benchmarks.md
rootfs/     build.sh (debootstrap rootfs + kernel A), tune.sh / tune2.sh (performance tuning), add-kernel-b.sh, add-kernel-c-live.sh
kernel/     build-kernel.sh (B), build-kernel-c.sh (C), full configs, config.diff (A -> B), config-B-to-C.diff
uboot/      fw_setenv-usb-boot.sh (USB boot with fallback), redacted U-Boot environments
config/     sanitized configuration examples (etc/, usr-local-sbin/)
```

Binary artifacts are attached to the GitHub **Release**, not stored in git. Historical initramfs files and Git history require a separate privacy review before public release; the sanitized source tree alone does not establish that those artifacts are safe to publish.

## Boot flow

1. U-Boot runs `usb reset; run usb_bootcmd` and loads `/uImage` + `/uInitrd` from the stick's ext2 partition.
2. If that fails, `mw 0x800000 0 1` guarantees `bootm` fails cleanly and U-Boot runs `bootcmd_stock` (stock LifeLine from disk).
3. Pull the stick to get LifeLine back. **If LifeLine ever offers to "initialize" storage, decline: it would wipe the data array.**

Switch kernels on the ix2 with `kies-kernel A`, `B` or `C`, then `reboot`. C trades kernel hardening for speed; use B on anything less trusted than a home LAN.

## Credits and licenses

- Kernel sources: kernel.org, GPL-2.0. Kirkwood patch, base config and kernel A packages: **bodhi**, [forum.doozan.com](https://forum.doozan.com/read.php?2,12096) (GPL-2.0).
- Debian packages: their respective licenses.
- Original project scripts and documentation: MIT, see [LICENSE](LICENSE). Upstream kernel configurations, patches, packages and other third-party material retain their original licenses; the MIT license does not relicense them.

## Project status and getting started

Maintained under the ToastyUI GitHub account. This is an experimental upgrade
project for Lenovo ix2-ng hardware, not an official Lenovo firmware release.
The existing benchmarks describe one development device, not guaranteed results.

1. Read [the installation guide](docs/handleiding.md) and back up your data and original boot environment locally.
2. Review the scripts before running them as root. Build in a disposable Linux environment.
3. Supply your own SSH public key to the rootfs builder. Never publish private keys or personalized rootfs images.
4. Replace documentation-only addresses (`192.0.2.0/24`), sample MACs and `nasuser` with your own settings. Benchmark scripts deliberately contain non-operational example addresses.
5. Review [kernel options](docs/kernel-options.md). Kernel C reduces hardening and is a performance experiment, not a security upgrade.

Debian runs from the USB stick; the internal LifeLine system stays on the SATA disks.
The LifeLine fallback only remains available while its original disk layout and
system partitions remain intact. The installation guide preserves those partitions and does not recreate the internal RAID.

## Contributing and security

See [CONTRIBUTING.md](CONTRIBUTING.md) for contributions and [SECURITY.md](SECURITY.md)
for reporting concerns. No CVE history, independent audit, adoption figures or
formal security-maintainer appointment is claimed by this project.

LifeLine SSH (enabled through `/diagnostics.html`): user `root`, password `soho`
immediately followed by the administrator password set by the user, with no space,
on the firmware used by this project. Debian on USB instead uses your SSH key.
See the [step-by-step guide](docs/handleiding.md) for setup and rollback.

## RAID monitoring, LEDs, disk idle and mail

See [monitoring setup](docs/monitoring.md) for existing RAID preservation, the
LED service, 20-minute disk idle and Gmail-backed mdadm warnings. Sanitized
configuration templates are included; provide credentials only on your NAS.
The development chat records successful Gmail SMTP acceptance on 2026-10-14.
This is not a newly executed hardware or mail test. Proxmox uplink watchdogs are
outside this NAS project's scope.

## Measured performance

Historical measurements on one ix2, not guaranteed results:

| Test | Result |
|---|---|
| Gigabit network | 929–941 Mbit/s |
| Local sequential disk read / write (kernel A) | 149 / 121 MiB/s |
| NFS sequential read, kernel A / B / C | 69.9 / 79.0 / 106.9 MiB/s |
| NFS sequential read, C with 16 server threads | 108.2 MiB/s |
| NFS app write, C with 16 server threads | 41.5 MiB/s |
| Cold NFS random 4K read, C with 16 threads | 620 IOPS |

[Full benchmarks and methodology](docs/benchmarks.md) include local fio, NFS,
network throughput, memory pressure, zram and runtime tuning. Earlier NFS random
read comparisons were cache-biased; use the corrected cold-cache results.
Kernel C sacrifices hardening; these results are not a recommendation to disable
protections. SMB comparisons remain unmeasured in the published results.
