# Kernel options: Original vs A vs B

- **Original** = LifeLine's stock kernel, Linux **2.6.31.8** (2009 code base, Lenovo build Oct 2018), Marvell LSP `KW_LSP_5.1.3_patch25`. Values marked *?* are inferred from the version (config not available).
- **A** = bodhi's `7.1.9-kirkwood-tld-1`.
- **B** = `7.1.9-ix2perf-1` = A + the options marked ★. See `kernel/config.diff`.
- **C** = `7.1.9-ix2c-1` = B minus hardening and debug/tracing (marked ◆). See `kernel/config-B-to-C.diff`. **Default.**

## Boot compatibility (A and B)

| Option | What it does | Why it matters on the ix2 |
|---|---|---|
| `ARM_APPENDED_DTB` | Finds a device tree appended to the zImage | Stock U-Boot cannot pass a DTB; we append `kirkwood-lenovo-ix2-ng.dtb` |
| `ARM_ATAG_DTB_COMPAT` (+ `CMDLINE_FROM_BOOTLOADER`) | Converts U-Boot ATAGs into the DT; uses U-Boot `bootargs` | Kernel command line stays controllable from U-Boot variables |
| `MACH_KIRKWOOD`, `CPU_FEROCEON` | Kirkwood SoC, Feroceon ARMv5TE core | The 88F6282 CPU |

## Scheduling and build profile (A and B)

| Option | Meaning |
|---|---|
| `HZ=100` | 100 timer interrupts/s: less overhead on one slow core |
| `PREEMPT_VOLUNTARY` | Best throughput profile available; `PREEMPT_NONE` no longer exists for ARM in 7.x |
| `CC_OPTIMIZE_FOR_SIZE` (`-Os`) | Smaller code fits the 16 KB L1 caches better; often faster on this CPU |

## Memory management

| Feature | Original | A | B |
|---|---|---|---|
| Page reclaim | classic 2-list LRU | classic 2-list LRU | ★ **MGLRU** (`LRU_GEN`, `LRU_GEN_ENABLED`) |
| zram | none (zram arrived in 2.6.33) | LZO / LZO-RLE only | ★ LZ4 + ZSTD, `ZRAM_MULTI_COMP` recompression, `ZRAM_TRACK_ENTRY_ACTIME` |
| Pressure metrics | none | none | ★ **PSI** (`/proc/pressure/*`), enables `systemd-oomd` |

**MGLRU**: tracks page age in generations; evicts the right pages under memory pressure, fewer stalls and less thrashing. Built for low-RAM Chromebooks and Android.

**zram on B**: compress with LZ4 (fast, cheap on CPU); recompress idle pages with ZSTD (~30–50% smaller). Speed for hot data, capacity for cold data.

## Storage and sharing

| Feature | Original | A / B |
|---|---|---|
| RAID | md RAID 1 | md RAID 1 + internal write-intent bitmap |
| Filesystem | LifeLine LVM volume *?* | ext4 `fast_commit` (5.10+), `metadata_csum`, `orphan_file` |
| Block layer | legacy single-queue (CFQ/deadline) | multi-queue, `mq-deadline` |
| Async I/O | classic | `io_uring` available |
| NFS server | v3 / early v4.0 *?* | **v4.2 only**: server-side copy; NFSD I/O modes (buffered / DONTCACHE / DIRECT, 6.18+, experimental) |
| SMB server | Samba (SMB1-era defaults *?*) | ksmbd (in-kernel SMB3) or Samba 4.22; SMB2.10 minimum |

## Hardening and debug (C only) ◆

| Option (disabled in C) | What it costs on this CPU |
|---|---|
| `INIT_ON_ALLOC_DEFAULT_ON` | Zeroes every allocated page, including page-cache pages that are overwritten by disk data right after. At ~100 MiB/s that is an extra ~100 MiB/s of memset on a 1.6 GHz ARMv5 core. **Biggest single win.** |
| `HARDENED_USERCOPY` | Bounds checks on every copy between kernel and user space |
| `SLAB_FREELIST_HARDENED`, `SLAB_FREELIST_RANDOM`, `RANDOM_KMALLOC_CACHES`, `SHUFFLE_PAGE_ALLOCATOR` | Pointer obfuscation and randomisation in the allocators |
| `STACKPROTECTOR_STRONG` → `STACKPROTECTOR` | Canary only in functions with character arrays, not in almost every function |
| `AUDIT`, `SECURITY_SELINUX` | Syscall audit hooks; SELinux was built but never active |
| `FTRACE` (+ all tracers), `DYNAMIC_DEBUG`, `KALLSYMS_ALL`, `KSM` | Tracing hooks, debug metadata, unused page merging |

Kept: `STRICT_KERNEL_RWX`, `VMAP_STACK`, `CPU_SW_DOMAIN_PAN` and `SCHEDSTATS` (the last two could not be disabled; they are forced by other options).

**Trade-off**: C has fewer defences against kernel memory-safety bugs. That is acceptable for a NAS on a trusted home LAN that is not reachable from the internet; it is not for an exposed server.

## Bottom line

- **Original → A**: 17 years of kernel development, security fixes, zram, modern block layer, ext4 `fast_commit`, NFS v4.2, ksmbd, current userland, line-rate gigabit.
- **A → B**: MGLRU, PSI, better zram. Reads 13–31% faster; mixed under memory pressure.
- **B → C**: less CPU per byte. NFS reads up to +35%, app writes +16%, and +22% NFS read under memory pressure. See `docs/benchmarks.md`.
