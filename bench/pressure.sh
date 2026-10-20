#!/bin/bash
# NFS v4.2 benchmark: Proxmox host (tijdelijk 192.0.2.118 op vmbr2) -> ix2
set -u
KEY=~/.ssh/id_ed25519
KH=$HOME/.ssh/known_hosts_ix2
PVE() { ssh -i $KEY -o BatchMode=yes -o ConnectTimeout=10 root@192.0.2.2 "$@"; }
IX2() { ssh -i $KEY -o BatchMode=yes -o ConnectTimeout=10 -o UserKnownHostsFile=$KH \
        -o "ProxyCommand=ssh -i $KEY -o BatchMode=yes -W %h:%p root@192.0.2.2" root@192.0.2.100 "$@"; }

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
VM='grep -E "^(pgmajfault|pswpin|pswpout|workingset_refault_file|allocstall_normal|pgscan_direct|pgsteal_direct) " /proc/vmstat'
echo "== geheugendruktest, kernel $(IX2 uname -r)"
IX2 'set -e; mkdir -p /etc/exports.d /srv/nas/bench
echo "/srv/nas 192.0.2.118(rw,sync,no_subtree_check,no_root_squash)" > /etc/exports.d/benchmark.exports; exportfs -ra
[ -s /srv/nas/bench/fio.dat ] || fio --name=mk --filename=/srv/nas/bench/fio.dat --size=2G --rw=write --bs=1M --direct=1 --ioengine=libaio --iodepth=8 >/dev/null
sync; echo 3 > /proc/sys/vm/drop_caches; swapon --show=NAME --noheadings | grep -q zram0 || { swapoff /dev/zram0 2>/dev/null; echo 1 > /sys/block/zram0/reset; systemctl reset-failed systemd-zram-setup@zram0; systemctl start systemd-zram-setup@zram0 dev-zram0.swap; }; swapon --show=NAME --noheadings | grep -q zram0 || exit 1; free -m | sed -n 2,3p' || { echo 'VOORBEREIDING MISLUKT'; exit 1; }
PVE 'ip addr add 192.0.2.118/24 dev vmbr2 2>/dev/null; ip route replace 192.0.2.100/32 dev vmbr2 src 192.0.2.118
mountpoint -q /mnt/ix2nfs || { mkdir -p /mnt/ix2nfs; mount -t nfs4 -o vers=4.2,soft,timeo=150,retrans=3 192.0.2.100:/srv/nas /mnt/ix2nfs; }
mountpoint -q /mnt/ix2nfs' || { echo "MOUNT MISLUKT"; exit 1; }
cat "$(dirname "$0")/memhog.py" | IX2 'cat > /root/memhog.py'
IX2 "nohup python3 /root/memhog.py 150 30 110 > /root/memhog.out 2>&1 &"
until IX2 'grep -q filled /root/memhog.out || ! pgrep -f memhog.py >/dev/null'; do sleep 3; done; IX2 'grep -q filled /root/memhog.out' || { echo 'VRETER GESTOPT (OOM?)'; IX2 'dmesg | tail -3'; exit 1; }
sleep 15
V1=$(IX2 "$VM; cat /proc/pressure/memory 2>/dev/null | sed 's/^/psi-mem-/'")
a=$(cpu)
r=$(PVE "mountpoint -q /mnt/ix2nfs && fio --name=pressure-read --filename=/mnt/ix2nfs/bench/fio.dat --size=2G --ioengine=psync --direct=0 --invalidate=1 --bs=1M --rw=read --time_based --runtime=60 --output-format=terse --terse-version=3" | awk -F';' '{printf "%.1f MiB/s", $7/1024}')
b=$(cpu)
V2=$(IX2 "$VM; cat /proc/pressure/memory 2>/dev/null | sed 's/^/psi-mem-/'")
echo "nfs-read onder druk: $r | $(busy "$a" "$b")"
paste <(echo "$V1") <(echo "$V2") | awk '$1 !~ /^psi/ {printf "%s +%d\n", $1, $4-$2}'
echo "$V2" | grep psi
until IX2 'grep -q hot-walk /root/memhog.out || ! pgrep -f memhog.py >/dev/null'; do sleep 3; done
IX2 'cat /root/memhog.out | grep hot-walk; free -m | sed -n 2,3p; zramctl --output-all 2>/dev/null | cut -c1-120'
PVE 'umount /mnt/ix2nfs; ip route del 192.0.2.100/32 dev vmbr2; ip addr del 192.0.2.118/24 dev vmbr2'
IX2 'rm -f /etc/exports.d/benchmark.exports; exportfs -ra'
echo klaar
