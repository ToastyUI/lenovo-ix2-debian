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
IX2 "echo '/srv/nas 192.168.20.118(rw,sync,no_subtree_check,no_root_squash)' > /etc/exports.d/benchmark.exports; exportfs -ra; for d in md127 sda sdb; do echo \$d ra=\$(cat /sys/block/\$d/queue/read_ahead_kb) sched=\$(cat /sys/block/\$d/queue/scheduler 2>/dev/null) nr=\$(cat /sys/block/\$d/queue/nr_requests 2>/dev/null); done; cat /proc/fs/nfsd/threads"
PVE 'ip addr add 192.168.20.118/24 dev vmbr2 2>/dev/null; ip route replace 192.168.20.100/32 dev vmbr2 src 192.168.20.118; mkdir -p /mnt/ix2nfs; mountpoint -q /mnt/ix2nfs || mount -t nfs4 -o vers=4.2,soft,timeo=150,retrans=3 192.168.20.100:/srv/nas /mnt/ix2nfs'
IX2 "sync; echo 3 > /proc/sys/vm/drop_caches"; S1=$(IX2 "grep -E ' (sda|sdb|md127) ' /proc/diskstats")
PVE "fio --name=rr --filename=/mnt/ix2nfs/bench/fio.dat --size=2G --ioengine=libaio --direct=1 --rw=randread --randrepeat=0 --bs=4k --iodepth=16 --time_based --runtime=30 --output-format=terse --terse-version=3" | awk -F';' '{print "nfs rand-read IOPS:", $8}'
S2=$(IX2 "grep -E ' (sda|sdb|md127) ' /proc/diskstats")
paste <(echo "$S1") <(echo "$S2") | awk '{n=NF/2; r=$(n+4)-$4; s=$(n+6)-$6; printf "%s: reads %d, gem. %.1f KB per read\n", $3, r, (r? s*512/1024/r : 0)}'
PVE 'umount /mnt/ix2nfs; ip route del 192.168.20.100/32 dev vmbr2; ip addr del 192.168.20.118/24 dev vmbr2'
IX2 'rm -f /etc/exports.d/benchmark.exports; exportfs -ra'
