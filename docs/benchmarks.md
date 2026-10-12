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

## Pending

- SMB: ksmbd vs Samba
- Memory-pressure test A vs B (MGLRU, PSI)
