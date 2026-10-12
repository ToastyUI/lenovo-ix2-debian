# Benchmarks

Lenovo ix2 (88F6282, 256 MB), 2× WD Red WD20EFRX 2 TB in md RAID 1 (internal bitmap), ext4 `fast_commit`, Debian 13.
Client: LXC container on Proxmox in the same L2 network (`vmbr2`), 1 GbE.
fio: 2 GB test file (larger than RAM), libaio.

## Kernel A (`7.1.9-kirkwood-tld-1`), 2026-10-12

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

## Pending

- NFS v4.2: buffered vs DONTCACHE
- SMB: ksmbd vs Samba
- Kernel B: same suite + PSI under load
