#!/bin/bash
# NFS v4.2 benchmark: Proxmox host (tijdelijk 192.168.20.118 op vmbr2) -> ix2
set -u
KEY=~/.ssh/proxmox_claude
KH=$HOME/.ssh/known_hosts_ix2
PVE() { ssh -i $KEY -o BatchMode=yes -o ConnectTimeout=10 root@192.168.3.2 "$@"; }
IX2() { ssh -i $KEY -o BatchMode=yes -o ConnectTimeout=10 -o UserKnownHostsFile=$KH \
        -o "ProxyCommand=ssh -i $KEY -o BatchMode=yes -W %h:%p root@192.168.3.2" root@192.168.20.100 "$@"; }

cpu() { IX2 'head -1 /proc/stat'; }
busy() { # $1 $2 = "cpu user nice sys idle iowait irq softirq ..."
  awk -v a="$1" -v b="$2" 'BEGIN{split(a,x);split(b,y);
    for(i=2;i<=9;i++){d[i]=y[i]-x[i];t+=d[i]}
    printf "ix2 cpu: user %d%% sys %d%% softirq %d%% iowait %d%% idle %d%%",
      100*(d[2]+d[3])/t,100*d[4]/t,100*d[8]/t,100*d[6]/t,100*d[5]/t}'; }
fio_() { PVE "mountpoint -q /mnt/ix2nfs && fio --name=t --filename=/mnt/ix2nfs/bench/fio.dat --size=2G $* --output-format=terse --terse-version=3" | awk -F';' '{printf "%.1f", ($7+$48)/1024}'; }
measure() { # label
  local a b r1 r2 r3
  a=$(cpu)
  r1=$(fio_ --ioengine=libaio --direct=1 --bs=1M --rw=read --iodepth=8 --time_based --runtime=30)
  b=$(cpu)
  r2=$(fio_ --ioengine=psync --direct=0 --invalidate=1 --bs=1M --rw=read)
  r3=$(fio_ --ioengine=psync --direct=0 --bs=1M --rw=write --end_fsync=1)
  printf "%-28s direct-read %5s | app-read %5s | app-write %5s MiB/s | read-%s\n" "$1" "$r1" "$r2" "$r3" "$(busy "$a" "$b")"
}
reset='echo 0 > /sys/kernel/debug/nfsd/disable-splice-read; ethtool -C eth0 rx-usecs 250 tx-usecs 0; ethtool -G eth0 rx 128; for d in sda sdb; do echo mq-deadline > /sys/block/$d/queue/scheduler; done; echo 4 > /proc/fs/nfsd/threads'
IX2 "mountpoint -q /sys/kernel/debug || mount -t debugfs none /sys/kernel/debug; mkdir -p /etc/exports.d /srv/nas/bench
echo '/srv/nas 192.168.20.118(rw,sync,no_subtree_check,no_root_squash)' > /etc/exports.d/benchmark.exports; exportfs -ra; $reset"
PVE 'ip addr add 192.168.20.118/24 dev vmbr2 2>/dev/null; ip route replace 192.168.20.100/32 dev vmbr2 src 192.168.20.118
mountpoint -q /mnt/ix2nfs || { mkdir -p /mnt/ix2nfs; mount -t nfs4 -o vers=4.2,soft,timeo=150,retrans=3 192.168.20.100:/srv/nas /mnt/ix2nfs; }
mountpoint -q /mnt/ix2nfs' || { echo "MOUNT MISLUKT"; exit 1; }
echo "== kernel $(IX2 uname -r)"
t() { IX2 "$reset; $2" >/dev/null 2>&1; measure "$1"; }
t "baseline"                ":"
t "splice uit"              "echo 1 > /sys/kernel/debug/nfsd/disable-splice-read"
t "nic tx-usecs 100"        "ethtool -C eth0 tx-usecs 100"
t "nic rx500 tx100 ring512" "ethtool -C eth0 rx-usecs 500 tx-usecs 100; ethtool -G eth0 rx 512"
t "scheduler none"          "for d in sda sdb; do echo none > /sys/block/\$d/queue/scheduler; done"
t "nfsd 8 threads"          "echo 8 > /proc/fs/nfsd/threads"
IX2 "$reset; rm -f /etc/exports.d/benchmark.exports; exportfs -ra"
PVE 'umount /mnt/ix2nfs; ip route del 192.168.20.100/32 dev vmbr2; ip addr del 192.168.20.118/24 dev vmbr2'
echo klaar
