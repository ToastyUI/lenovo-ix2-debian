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

run() { # naam, fio-opties
  local n=$1; shift
  local a b r
  a=$(cpu)
  r=$(PVE "mountpoint -q /mnt/ix2nfs && fio --name=$n --filename=/mnt/ix2nfs/bench/fio.dat --size=2G --ioengine=libaio --direct=1 \
          --time_based --runtime=30 --ramp_time=3 --group_reporting $* --output-format=terse --terse-version=3" \
      | awk -F';' '{printf "read %.1f MiB/s %d IOPS | write %.1f MiB/s %d IOPS", $7/1024,$8,$48/1024,$49}')
  b=$(cpu)
  echo "$n: $r | $(busy "$a" "$b")"
}

runb() { # gebufferde client-IO zoals een echte app (geen O_DIRECT), met fsync aan het eind
  local n=$1; shift
  local a b r
  a=$(cpu)
  r=$(PVE "mountpoint -q /mnt/ix2nfs && fio --name=$n --filename=/mnt/ix2nfs/bench/fio.dat --size=2G --ioengine=psync --direct=0 --invalidate=1 \
          --end_fsync=1 --group_reporting $* --output-format=terse --terse-version=3" \
      | awk -F';' '{printf "read %.1f MiB/s | write %.1f MiB/s", $7/1024,$48/1024}')
  b=$(cpu)
  echo "$n: $r | $(busy "$a" "$b")"
}

suite() {
  run seq-write   --rw=write     --bs=1M --iodepth=8
  run seq-read    --rw=read      --bs=1M --iodepth=8
  run rand-read4k --rw=randread  --bs=4k --iodepth=16
  run rand-write4k --rw=randwrite --bs=4k --iodepth=16
}

mnt() {
PVE 'ip addr add 192.168.20.118/24 dev vmbr2 2>/dev/null; ip route replace 192.168.20.100/32 dev vmbr2 src 192.168.20.118
mountpoint -q /mnt/ix2nfs && umount /mnt/ix2nfs; mkdir -p /mnt/ix2nfs
mount -t nfs4 -o vers=4.2,soft,timeo=150,retrans=3 192.168.20.100:/srv/nas /mnt/ix2nfs
mountpoint -q /mnt/ix2nfs || exit 1
grep ix2nfs /proc/mounts | cut -d" " -f4 | tr , "\n" | grep -E "^(vers|rsize|wsize)" | tr "\n" " "; echo
mkdir -p /mnt/ix2nfs/bench' || { echo "MOUNT MISLUKT, stop"; exit 1; }
}

echo "== ronde 3: max_block_size 1M (sync export)"
IX2 'systemctl stop nfs-server; echo 1048576 > /proc/fs/nfsd/max_block_size; systemctl start nfs-server
echo "max_block_size=$(cat /proc/fs/nfsd/max_block_size)"
mkdir -p /etc/exports.d /srv/nas/bench
echo "/srv/nas 192.168.20.118(rw,sync,no_subtree_check,no_root_squash)" > /etc/exports.d/benchmark.exports; exportfs -ra'
mnt
suite
runb app-write-sync --rw=write --bs=1M
runb app-read       --rw=read  --bs=1M

echo "== ronde 4: max_block_size 1M + async export"
IX2 'echo "/srv/nas 192.168.20.118(rw,async,no_subtree_check,no_root_squash)" > /etc/exports.d/benchmark.exports; exportfs -ra; exportfs -v | head -2'
mnt
run  seq-write  --rw=write --bs=1M --iodepth=8
runb app-write-async --rw=write --bs=1M

echo "== geheugen ix2"
IX2 'free -m | sed -n 2,3p; dmesg | grep -iE "oom|nfsd" | tail -3'

echo "== opruimen"
PVE 'rm -f /mnt/ix2nfs/bench/fio.dat; umount /mnt/ix2nfs; ip route del 192.168.20.100/32 dev vmbr2; ip addr del 192.168.20.118/24 dev vmbr2; ip -br addr show vmbr2'
IX2 'rm -f /etc/exports.d/benchmark.exports; exportfs -ra; rmdir /srv/nas/bench 2>/dev/null; echo "max_block_size blijft $(cat /proc/fs/nfsd/max_block_size) tot reboot"'
echo klaar
