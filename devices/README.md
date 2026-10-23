# Kirkwood devices

This repository started as Debian 13 for the Lenovo ix2-ng (top-level `README.md`,
`rootfs/`, `kernel/`, `uboot/`, `config/`). This directory extends it to other Marvell
Kirkwood (ARMv5, armel) NAS and plug computers whose OS can be replaced.

What is shared between all of them: the Debian 13 armel minbase rootfs, the 7.1.9 kernel
configs (`kernel/`, bodhi's all-Kirkwood base, kernel C = less hardening, more speed) and the
256 MB RAM tuning in `config/` (zram, sysctl, journald, NFS 1 MB blocks).
What differs per device: the DTB, how U-Boot can be made to load Debian, and how LEDs, fan
and power button are driven (GPIO, or a microcontroller on `/dev/ttyS1`).

## Status legend

- **tested on hardware**: running on a real unit, benchmarks in `docs/`.
- **kit (simulated)**: scripts written and tested against simulated hardware (loop disks,
  a pty instead of the PIC, real U-Boot env dumps), not yet booted on the device.
- **kit should apply (untested)**: same board family as a kit; expected to work with the
  DTB named, nobody has tried it.
- **untested**: the mainline kernel has a DTB for it; nothing in this repo is device-specific yet.

## Adding a device

1. Find its DTB in the table (mainline `arch/arm/boot/dts/marvell/kirkwood-*.dts`).
2. Work out how its stock U-Boot can load a kernel you control (USB, SATA, flash) and how to
   get back to the stock firmware. Dump the U-Boot env first; never write `mtd0` (the bootloader).
3. Copy `devices/qnap-ts41x/` as a template: `build-rootfs.sh`, `config/`, a guide in `docs/`.
4. Update its row in `devices.tsv` and run `python3 devices/render-table.py`.

For many plug computers in the list (Pogoplug, Dockstar, GoFlex, NSA3xx, iConnect, ...) the
doozan forum has community U-Boot builds and rootfs threads by bodhi; check there first.

## Devices

Generated from `devices.tsv` (81 DTBs in mainline Linux 7.1.9, plus the ix2-ng).

<!-- table:start -->
| Model | DTB | Family | MCU (LED/fan/power) | Status | Notes |
| --- | --- | --- | --- | --- | --- |
| Lenovo/Iomega ix2-ng | `kirkwood-lenovo-ix2-ng.dtb (bodhi patch, not mainline)` | lenovo | - (GPIO LEDs) | tested on hardware: top-level README | USB boot via fw_setenv, LifeLine fallback |
| QNAP TS219 family | `kirkwood-ts219-6281.dtb` | qnap | qnap-pic ttyS1 19200 | kit should apply (untested) | TS-11x/21x/22x: same PIC; set DTB in /etc/ts41x/boot.conf |
| QNAP TS219 family | `kirkwood-ts219-6282.dtb` | qnap | qnap-pic ttyS1 19200 | kit should apply (untested) | TS-11x/21x/22x: same PIC; set DTB in /etc/ts41x/boot.conf |
| QNAP TS419 family | `kirkwood-ts419-6281.dtb` | qnap | qnap-pic ttyS1 19200 | kit: devices/qnap-ts41x (simulated, not yet on hardware) | TS-410/412/419P/419U |
| QNAP TS419 family | `kirkwood-ts419-6282.dtb` | qnap | qnap-pic ttyS1 19200 | kit should apply (untested) | TS-419P II/U+ (88F6282) |
| Synology 409slim | `kirkwood-ds409slim.dtb` | synology | synology-mcu ttyS1 9600 | untested |  |
| Synology DS109, DS110, DS110jv20 | `kirkwood-ds109.dtb` | synology | synology-mcu ttyS1 9600 | untested |  |
| Synology DS110j v10 and v30 | `kirkwood-ds110jv10.dtb` | synology | synology-mcu ttyS1 9600 | untested |  |
| Synology DS111 | `kirkwood-ds111.dtb` | synology | synology-mcu ttyS1 9600 | untested |  |
| Synology DS112 | `kirkwood-ds112.dtb` | synology | synology-mcu ttyS1 9600 | untested |  |
| Synology DS209 | `kirkwood-ds209.dtb` | synology | synology-mcu ttyS1 9600 | untested |  |
| Synology DS210 v10, v20, v30, DS211j | `kirkwood-ds210.dtb` | synology | synology-mcu ttyS1 9600 | untested |  |
| Synology DS212, DS212p v10, v20, DS213air v10, DS213 v10 | `kirkwood-ds212.dtb` | synology | synology-mcu ttyS1 9600 | untested |  |
| Synology DS212j v10, v20 | `kirkwood-ds212j.dtb` | synology | synology-mcu ttyS1 9600 | untested |  |
| Synology DS409, DS410j | `kirkwood-ds409.dtb` | synology | synology-mcu ttyS1 9600 | untested |  |
| Synology DS411, DS413jv10 | `kirkwood-ds411.dtb` | synology | synology-mcu ttyS1 9600 | untested |  |
| Synology DS411j | `kirkwood-ds411j.dtb` | synology | synology-mcu ttyS1 9600 | untested |  |
| Synology DS411slim | `kirkwood-ds411slim.dtb` | synology | synology-mcu ttyS1 9600 | untested |  |
| Synology RS212 | `kirkwood-rs212.dtb` | synology | synology-mcu ttyS1 9600 | untested |  |
| Synology RS409 | `kirkwood-rs409.dtb` | synology | synology-mcu ttyS1 9600 | untested |  |
| Synology RS411 RS812 | `kirkwood-rs411.dtb` | synology | synology-mcu ttyS1 9600 | untested |  |
| Buffalo Linkstation LS-CHLv2 | `kirkwood-lschlv2.dtb` | buffalo | - | untested |  |
| Buffalo Linkstation LS-QVL | `kirkwood-linkstation-lsqvl.dtb` | buffalo | - | untested |  |
| Buffalo Linkstation LS-VL | `kirkwood-linkstation-lsvl.dtb` | buffalo | - | untested |  |
| Buffalo Linkstation LS-WSXL | `kirkwood-linkstation-lswsxl.dtb` | buffalo | - | untested |  |
| Buffalo Linkstation LS-WVL | `kirkwood-linkstation-lswvl.dtb` | buffalo | - | untested |  |
| Buffalo Linkstation LS-WXL | `kirkwood-linkstation-lswxl.dtb` | buffalo | - | untested |  |
| Buffalo Linkstation LS-XHL | `kirkwood-lsxhl.dtb` | buffalo | - | untested |  |
| LaCie 2Big NAS | `kirkwood-nas2big.dtb` | lacie | - | untested |  |
| LaCie 2Big Network v2 | `kirkwood-net2big.dtb` | lacie | - | untested |  |
| LaCie 5Big Network v2 | `kirkwood-net5big.dtb` | lacie | - | untested |  |
| LaCie CloudBox | `kirkwood-cloudbox.dtb` | lacie | - | untested |  |
| LaCie d2 Network v2 | `kirkwood-d2net.dtb` | lacie | - | untested |  |
| LaCie Internet Space v2 | `kirkwood-is2.dtb` | lacie | - | untested |  |
| LaCie LaPlug | `kirkwood-laplug.dtb` | lacie | - | untested |  |
| LaCie Network Space Lite v2 | `kirkwood-ns2lite.dtb` | lacie | - | untested |  |
| LaCie Network Space Max v2 | `kirkwood-ns2max.dtb` | lacie | - | untested |  |
| LaCie Network Space Mini v2 | `kirkwood-ns2mini.dtb` | lacie | - | untested |  |
| LaCie Network Space v2 | `kirkwood-ns2.dtb` | lacie | - | untested |  |
| ZyXEL NSA310 | `kirkwood-nsa310.dtb` | zyxel | - | untested |  |
| ZyXEL NSA310 | `kirkwood-nsa310a.dtb` | zyxel | - | untested |  |
| ZyXEL NSA310S | `kirkwood-nsa310s.dtb` | zyxel | - | untested |  |
| Zyxel NSA320 | `kirkwood-nsa320.dtb` | zyxel | - | untested |  |
| ZyXEL NSA325 | `kirkwood-nsa325.dtb` | zyxel | - | untested |  |
| Cloud Engines Pogoplug E02 | `kirkwood-pogo_e02.dtb` | plug/nas | - | untested |  |
| Cloud Engines PogoPlug Series 4 | `kirkwood-pogoplug-series-4.dtb` | plug/nas | - | untested |  |
| Ctera C200 V1 | `kirkwood-c200-v1.dtb` | plug/nas | - | untested |  |
| D-Link DNS-320 NAS (Rev A1) | `kirkwood-dns320.dtb` | plug/nas | - | untested |  |
| D-Link DNS-325 NAS (Rev A1) | `kirkwood-dns325.dtb` | plug/nas | - | untested |  |
| Excito B3 | `kirkwood-b3.dtb` | plug/nas | - | untested |  |
| Globalscale Technologies Dreamplug | `kirkwood-dreamplug.dtb` | plug/nas | - | untested |  |
| Globalscale Technologies eSATA SheevaPlug | `kirkwood-sheevaplug-esata.dtb` | plug/nas | - | untested |  |
| Globalscale Technologies Guruplug Server Plus | `kirkwood-guruplug-server-plus.dtb` | plug/nas | - | untested |  |
| Globalscale Technologies SheevaPlug | `kirkwood-sheevaplug.dtb` | plug/nas | - | untested |  |
| HP t5325 Thin Client | `kirkwood-t5325.dtb` | plug/nas | - | untested |  |
| Iomega Iconnect | `kirkwood-iconnect.dtb` | plug/nas | - | untested |  |
| Iomega StorCenter ix2-200 | `kirkwood-iomega_ix2_200.dtb` | plug/nas | - | untested |  |
| NETGEAR ReadyNAS Duo v2 | `kirkwood-netgear_readynas_duo_v2.dtb` | plug/nas | - | untested |  |
| NETGEAR ReadyNAS NV+ v2 | `kirkwood-netgear_readynas_nv+_v2.dtb` | plug/nas | - | untested |  |
| OpenRD Base | `kirkwood-openrd-base.dtb` | plug/nas | - | untested |  |
| OpenRD Client | `kirkwood-openrd-client.dtb` | plug/nas | - | untested |  |
| OpenRD Ultimate | `kirkwood-openrd-ultimate.dtb` | plug/nas | - | untested |  |
| RaidSonic ICY BOX IB-NAS62x0 (Rev B) | `kirkwood-ib62x0.dtb` | plug/nas | - | untested |  |
| Seagate Blackarmor NAS220 | `kirkwood-blackarmor-nas220.dtb` | plug/nas | - | untested |  |
| Seagate FreeAgent Dockstar | `kirkwood-dockstar.dtb` | plug/nas | - | untested |  |
| Seagate GoFlex Net | `kirkwood-goflexnet.dtb` | plug/nas | - | untested |  |
| Check Point L-50 | `kirkwood-l-50.dtb` | router/appliance | - | untested |  |
| D-Link DIR-665 | `kirkwood-dir665.dtb` | router/appliance | - | untested |  |
| Endian 4i Edge 200 | `kirkwood-4i-edge-200.dtb` | router/appliance | - | untested |  |
| Linksys Viper (E4200v2 / EA4500) | `kirkwood-linksys-viper.dtb` | router/appliance | - | untested |  |
| Plat'Home OpenBlocksA6 | `kirkwood-openblocks_a6.dtb` | router/appliance | - | untested |  |
| Plat'Home OpenBlocksA7 | `kirkwood-openblocks_a7.dtb` | router/appliance | - | untested |  |
| Keymile Kirkwood Fixed Eth | `kirkwood-km_fixedeth.dtb` | dev-board | - | untested |  |
| Keymile Kirkwood Reference Design | `kirkwood-km_kirkwood.dtb` | dev-board | - | untested |  |
| Marvell 88F6281 GTW GE Board | `kirkwood-mv88f6281gtw-ge.dtb` | dev-board | - | untested |  |
| Marvell DB-88F6281-BP Development Board | `kirkwood-db-88f6281.dtb` | dev-board | - | untested |  |
| Marvell DB-88F6282-BP Development Board | `kirkwood-db-88f6282.dtb` | dev-board | - | untested |  |
| Marvell RD88F6192 reference design | `kirkwood-rd88f6192.dtb` | dev-board | - | untested |  |
| Marvell RD88f6281 Reference design, with A0 or higher SoC | `kirkwood-rd88f6281-a.dtb` | dev-board | - | untested |  |
| Marvell RD88f6281 Reference design, with Z0 SoC | `kirkwood-rd88f6281-z0.dtb` | dev-board | - | untested |  |
| MPL CEC4 | `kirkwood-mplcec4.dtb` | dev-board | - | untested |  |
| Universal Scientific Industrial Co. Topkick-1281P2 | `kirkwood-topkick.dtb` | dev-board | - | untested |  |
<!-- table:end -->
