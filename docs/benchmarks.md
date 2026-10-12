# Benchmarks

Lenovo ix2 (88F6282, 256 MB), 2× WD Red WD20EFRX 2 TB in md RAID 1 (internal bitmap), ext4 `fast_commit`, Debian 13.
Client: LXC container on Proxmox in the same L2 network (`vmbr2`), 1 GbE.
fio: 2 GB test file (larger than RAM), libaio.

## Kernel A (`7.1.9-kirkwood-tld-1`), 2026-10-12

Scripts: `bench/disk-bench.sh` (runs on the ix2), `bench/nfs-bench-*.sh` (run from a machine that can reach Proxmox).

### Network (iperf3, 15 s)

| Direction | Throughput | Retransmits |
|---|---|---|
| client → ix2 (ix2 receives) | 929 Mbit/s | 0 |
| ix2 → client (ix2 sends) | 941 Mbit/s | 0 |

Note: an earlier run showed 5 Mbit/s towards the ix2. Cause: TX timeouts in the Proxmox host's USB NIC (RTL8153, `r8152`, "NETDEV WATCHDOG"). Replacing it with a second RTL8153 unit fixed it.

### Disk / RAID (fio)

| Test | Result | CPU |
|---|---|---|
| Sequential write 1M, direct, QD8 | 121 MiB/s | sys 27% |
| Sequential read 1M, direct, QD8 | 149 MiB/s | sys 28% |
| Random read 4k, direct, QD16 | 616 IOPS | sys 6% |
| Random write 4k, direct, QD16 | 416 IOPS | sys 6% |
| Write 4k + fsync each, QD1 | 18 IOPS (72 KiB/s) | iowait 95% |
| Buffered sequential read 1M | 117 MiB/s | **sys 82%** (CPU-bound page-cache copy) |
| Raw single disk read 1M | 147 MiB/s | |

- fsync: `fast_commit` is used (361 commits, 0 ineligible) but each commit averages ~51 ms: two 5400 rpm drives must flush their caches. Worst case; real workloads fsync per file.
- Buffered I/O is CPU-bound near 1 GbE line rate; NFS/SMB will likely top out around 100–117 MB/s.
- Memory after the run: 73 MB used; zram held 7 MB in 2 MB (3.5:1).

## Kernel A vs B: local disk (fio, same suite)

| Test | A | B |
|---|---|---|
| Sequential write 1M, direct | 121 MiB/s | 121 MiB/s |
| Sequential read 1M, direct | 149 MiB/s | 147 MiB/s |
| Random read 4k, QD16 | 616 IOPS | 627 IOPS |
| Random write 4k, QD16 | 416 IOPS | 423 IOPS |
| Write 4k + fsync | 18 IOPS | 19 IOPS |
| **Buffered sequential read 1M** | 117 MiB/s (sys 82%) | **132 MiB/s** (sys 88%) **+13%** |

Direct I/O is disk-bound and identical. Buffered (page-cache) reads gain 13% on B; MGLRU is the only reclaim-related change.

## NFS v4.2 (Proxmox host → ix2), 2026-10-12

Client: Proxmox host with a temporary address on the NAS bridge (direct L2, not routed through OPNsense), `vers=4.2,soft`. 2 GB file, 30 s per test.
"direct" = fio O_DIRECT, QD8 (1M) / QD16 (4k). "app" = normal buffered client I/O with `fsync` at the end (what Immich/Finder do).

### Kernel A: server-side options

| Server setting | Seq write | Seq read | Rand read 4k | Rand write 4k |
|---|---|---|---|---|
| Default (nfsd picks **32 KB** rsize/wsize at 256 MB RAM), `sync` | 22.5 MiB/s | 40.3 MiB/s | 862 IOPS | 43 IOPS |
| + DONTCACHE read+write | 9.9 | 49.4 | 1322 | 44 |
| **`max_block_size` 1 MB**, `sync` | 21.6 | **69.9** | 966 | 44 |
| 1 MB, `sync`, app I/O | 35.8 | 67.5 | | |
| 1 MB, `async` | 40.1 | | | |
| 1 MB, `async`, app I/O | 38.7 | | | |

### Kernel A vs B (1 MB blocks)

| Test | A | B |
|---|---|---|
| Seq write direct, `sync` | 21.6 MiB/s | 21.3 MiB/s |
| **Seq read direct** | 69.9 MiB/s | **79.0 MiB/s (+13%)** |
| Rand read 4k | 966 IOPS | 899 IOPS |
| Rand write 4k, `sync` | 44 IOPS | 44 IOPS |
| App write, `sync` | 35.8 MiB/s | 34.9 MiB/s |
| **App read** | 67.5 MiB/s | **88.5 MiB/s (+31%)** |
| Seq write direct, `async` | 40.1 MiB/s | 38.8 MiB/s |
| App write, `async` | 38.7 MiB/s | 38.7 MiB/s |

### Conclusions

- **The CPU is the limit for large files**: idle ≤ 3%, sys 50–70%, softirq 25–35% (one 1.6 GHz ARMv5 core). Network (940 Mbit/s) and disks (147 MiB/s) have headroom.
- **`max_block_size` = 1 MB** is the biggest single win (+73% sequential read on A). nfsd defaults to 32 KB on low-RAM machines. Made persistent with `config/etc/systemd/system/nfs-server.service.d/10-blocksize.conf`.
- **DONTCACHE**: +23% read, but halves sequential write (no write-back merging). Left off.
- **`async`**: +8% for normal app writes, at the cost of losing the last seconds of writes on power loss. Kept **`sync`**.
- **Small random writes** (43 IOPS) are bound by `sync` + two 5400 rpm disks flushing. Fine for photos/videos; not for databases (Immich's database stays on the Proxmox SSD).
- **Kernel B** reads 13–31% faster through NFS and the page cache, with equal writes. B is the default.
- Memory on the ix2 after all runs: ~85 MB used, ~145 MB available, no swap used.

## zram on B

`lz4` primary, `zstd(level=3)` recompression of pages idle > 10 min (`zram-recompress.timer`). `kies-kernel A` switches back to `lzo-rle` (A has no LZ4/ZSTD/multi-comp).

## Memory pressure: A vs B (`bench/pressure.sh`, `bench/memhog.py`)

A Python process allocates 150 MB (more than is free, ~2:1 compressible) and touches a 30 MB hot set every second, while the Proxmox host streams a 2 GB file over NFS for 60 s. One run per kernel, so small differences are noise.

| Under pressure | A (classic LRU, zram lzo-rle) | B (MGLRU, zram lz4) |
|---|---|---|
| NFS read | 77.5 MiB/s | 74.9 MiB/s |
| Hot set walk, p50 / p95 | 65.6 / 143.7 ms | **52.3 / 101.5 ms** |
| 50 cold pages, p50 / p95 | **4.2 / 37.4 ms** | 17.0 / 47.1 ms |
| Worst stall | **1.5 s** | 2.7 s |
| File refaults | **3,414** | 6,887 |
| Swap out / in (pages) | 9,593 / 1,982 | 5,142 / 3,699 |
| zram ratio | **1.83** | 1.40 (zstd recompression not yet active, it starts after 10 min) |
| PSI memory some / full (avg10) | n/a (no PSI in A) | 32% / 20% |

MGLRU protects the active working set (−20% p50, −29% p95), but brings cold pages back more slowly and refaults more page cache. Mixed; no clear winner under pressure. Without pressure, B reads 13–31% faster, so **B stays the default**.

Note: `swapoff -a; swapon -a` does not re-enable zram (it is not in fstab); the first run therefore had no swap and the probe was OOM-killed (by design, `oom_score_adj` 1000; NFS/ksmbd/sshd were unaffected).

## Runtime tuning on B (`bench/runtime-tuning.sh`)

Each setting alone, everything else at the default; NFS 1 MB blocks, `sync` export. Kernel C was compiling on the Proxmox host at the same time (nice 19), identical for all rows.

| Setting | Direct read | App read | App write |
|---|---|---|---|
| Baseline | 86.7 | 87.3 | 36.1 |
| `disable-splice-read` = 1 | **71.7** | **68.3** | 36.0 |
| NIC `tx-usecs 100` | 89.2 | 86.7 | 36.0 |
| NIC `rx-usecs 500 tx-usecs 100`, RX ring 512 | 90.3 | 87.7 | 35.2 |
| Scheduler `none` | 87.7 | 86.0 | 36.2 |
| 8 nfsd threads | 89.2 | 86.2 | 35.5 |

- **Splice must stay on**: turning it off costs 17–22%. (So the DONTCACHE read gain did not come from disabling splice.)
- NIC coalescing, scheduler and thread count are all within ~4% (noise). None adopted.
- Conclusion: with 1 MB blocks the box is CPU-bound; only less work per byte (kernel C) can still help.

## Kernel C (`7.1.9-ix2c-1` = B minus hardening/debug), 2026-10-12

### NFS (1 MB blocks)

| Test | A | B | **C** |
|---|---|---|---|
| Seq read direct | 69.9 | 79.0 | **106.9** |
| App read | 67.5 | 88.5 | **97.9** (ix2 19% idle) |
| Seq write direct, `sync` | 21.6 | 21.3 | 18.7 |
| App write, `sync` | 35.8 | 34.9 | **40.4** |
| Seq write direct, `async` | 40.1 | 38.8 | 43.4 |
| App write, `async` | 38.7 | 38.7 | 42.4 |
| Rand write 4k, `sync` | 44 IOPS | 44 IOPS | 43 IOPS |
| NFS read under memory pressure | 77.5 | 74.9 | **91.2** |

C with 16 nfsd threads (final configuration): direct read **108.2**, app read **99.3**, app write **41.5** MiB/s.

### Local disk

| Test | A | B | C |
|---|---|---|---|
| Seq write / read 1M direct | 121 / 149 | 121 / 147 | 122 / 145 |
| Rand read / write 4k | 616 / 416 | 627 / 423 | 628 / 422 |
| Write 4k + fsync | 18 | 19 | 11, 13, 16 (three runs; disk-cache-flush bound, noisy) |
| Buffered read 1M | 117 (sys 82%) | 132 (sys 88%) | **138** (sys 78%) |

### Memory pressure

| | A | B | C |
|---|---|---|---|
| Hot set p50 / p95 | 65.6 / 143.7 ms | 52.3 / 101.5 ms | 74.7 / 129.2 ms |
| Cold pages p50 | 4.2 ms | 17.0 ms | 13.3 ms |
| Worst stall | 1.5 s | 2.7 s | 1.9 s |
| NFS read meanwhile | 77.5 | 74.9 | **91.2** |

On C the probe competes with 22% more NFS traffic for the page cache, which explains the slower hot set.

### Correction: NFS random 4k reads

The earlier NFS random-read numbers (A 966, B 899, C 317 IOPS) are **not comparable**: fio repeats the same "random" offsets by default (`randrepeat=1`), so the result depended on what the previous test left in the ix2's page cache. A probe of `/proc/diskstats` showed one run at 1616 IOPS with only 16% of requests reaching the disks.

Fair test (`bench/nfs-randread-cold.sh`): `drop_caches` on the ix2 and `randrepeat=0`, 30 s, QD16 at the client, kernel C:

| nfsd threads | Cold random 4k read | Memory used |
|---|---|---|
| 4 | 310 IOPS (every request hits the disks) | 87 MB |
| 8 | 432 IOPS | 87 MB |
| **16** | **620 IOPS** (= local disk, 628) | 103 MB |

The limit was the number of nfsd threads (outstanding disk requests), not the kernel. **16 threads** adopted (`config/etc/nfs.conf.d/ix2.conf`); sequential throughput is unchanged.

### Verdict

**C is the default.** Large-file NFS reads +35% over B (+53% over A), app writes +16%, NFS under memory pressure +22%, with CPU headroom left over. Disk-bound results are unchanged. Trade-off: fewer kernel hardening features (acceptable on a trusted LAN only).

## Pending

- SMB: ksmbd vs Samba
