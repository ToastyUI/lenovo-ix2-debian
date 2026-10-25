#!/bin/sh
# Read-only check that QTS's shell (busybox 1.01) supports everything ts41x-prep-qts.sh and
# ts41x-install-boot.sh use. Writes nothing to disks or flash.
#   ssh admin@NAS 'sh -s' < ts41x-qts-probe.sh
t() { if eval "$2" >/dev/null 2>&1; then echo "ok    $1"; else echo "FAIL  $1"; fi; }
t 'arithmetic $((..))'     '[ $((1060296 + 2048)) = 1062344 ]'
t 'command -v'             'command -v ls'
t 'which'                  'which ls'
t 'set -eu in subshell'    '(set -eu; x=1; echo $x)'
t 'trap EXIT'              '(trap "true" EXIT; true)'
t 'test -t 0'              '[ -t 0 ] || true'
t 'test -L'                '[ -L /proc/self ] || [ ! -L /proc/self ]'
t '${v##*/} ${v%:*}'       'v=/a/b:c; [ "${v##*/}" = "b:c" ] && [ "${v%:*}" = /a/b ]'
t 'case glob'              'case loop0 in *[0-9]) true ;; *) false ;; esac'
t 'egrep -q'               'echo "/dev/sda2 x" | egrep -q "^/dev/(sda2|md256) "'
t 'grep -q fixed'          'echo " sda3[0]" | grep -q " sda3\["'
t 'readlink (no -f)'       'readlink /sys/block/sda/device'
t 'hexdump -e'             '[ "$(echo AB | dd bs=1 count=2 2>/dev/null | hexdump -v -e "1/1 \"%02x\"")" = 4142 ]'
t 'awk printf hex'         '[ "$(echo 1062344 | awk "{ printf \"0x%x\", \$1 }")" = 0x1035c8 ]'
t 'awk field'              '[ "$(echo "0.0.0.0 1.2.3.4" | awk "\$1 == \"0.0.0.0\" { print \$2; exit }")" = 1.2.3.4 ]'
t 'dd skip/count'          'dd if=/dev/zero bs=512 skip=10 count=1 2>/dev/null | wc -c | grep -q 512'
t 'cmp -s stdin'           'echo x | cmp -s - /dev/null || true'
t 'date +%T'               'date +%T | grep -q :'
t 'sed s|..|..|'           '[ "$(echo DISKS=x | sed "s|^DISKS=.*|DISKS=\"sda sdb\"|")" = "DISKS=\"sda sdb\"" ]'
t 'tr . space'             '[ "$(echo 255.0 | tr . " ")" = "255 0" ]'
t 'cut -d'                 '[ "$(echo "1 2" | cut -d" " -f2)" = 2 ]'
t 'getcfg'                 'getcfg eth0 "Use DHCP" -d TRUE'
t 'ifconfig inet addr'     'ifconfig eth0 | grep -q "inet addr:"'
t 'route -n'               'route -n'
t 'ext4 in kernel'         'grep -q ext4 /proc/filesystems'
t 'raid1 in kernel'        'grep -q raid1 /proc/mdstat'
t 'gzip -dc'               'echo x | gzip | gzip -dc | grep -q x'
t 'tar -xf -'              'tar --help 2>&1 | grep -q x'
t 'sync, swapoff, mount'   'which sync && which swapoff && which mount'
echo "mdadm: $(mdadm --version 2>&1)"
echo "mke2fs: $(mke2fs -V 2>&1 | head -1)"
echo "shell: $(readlink /bin/sh)"
echo "swaps:"; cat /proc/swaps
