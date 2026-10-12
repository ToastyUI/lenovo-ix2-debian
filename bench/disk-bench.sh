cd /srv/nas
F="--directory=/srv/nas --filename=fio.test --size=2G --ioengine=libaio --group_reporting --time_based"
run(){ n="$1"; shift; vmstat 2 > /tmp/vm.$n & V=$!; out=$(fio --name=$n $F "$@" 2>&1); kill $V; cpu=$(awk 'NR>3{u+=$13;s+=$14;w+=$16;n++} END{if(n) printf "cpu user %d%% sys %d%% iowait %d%%", u/n, s/n, w/n}' /tmp/vm.$n); echo "$n: $(echo "$out" | grep -oE "(read|write): IOPS=[^,]+, BW=[^ ]+" | tr '\n' ' ') | $cpu"; }
echo "=== kernel $(uname -r), $(date +%T)"
run seq-write   --rw=write     --bs=1M --direct=1 --iodepth=8  --runtime=30
run seq-read    --rw=read      --bs=1M --direct=1 --iodepth=8  --runtime=30
run rand-read4k --rw=randread  --bs=4k --direct=1 --iodepth=16 --runtime=25
run rand-write4k --rw=randwrite --bs=4k --direct=1 --iodepth=16 --runtime=25
run fsync-4k    --rw=write     --bs=4k --fsync=1  --iodepth=1  --runtime=20 --size=256M
run buffered-read --rw=read    --bs=1M --direct=0 --iodepth=1  --runtime=20
rm -f /srv/nas/fio.test
echo "=== ruwe schijf sda (alleen lezen, datadeel)"
fio --name=raw --filename=/dev/sda --offset=30G --size=8G --rw=read --bs=1M --direct=1 --ioengine=libaio --iodepth=8 --readonly --runtime=20 --time_based 2>&1 | grep -oE "read: IOPS=[^,]+, BW=[^ ]+"
echo "=== geheugen na de tests"; free -m | sed -n 2,3p; cat /sys/block/zram0/mm_stat 2>/dev/null | awk '{printf "zram: %d MB data, %d MB gecomprimeerd\n", $1/1048576, $2/1048576}'
[ -r /proc/pressure/memory ] && for r in cpu memory io; do echo "psi $r: $(head -1 /proc/pressure/$r)"; done
