# QNAP TS-11x / TS-21x / TS-22x (untested)

Same board family as the TS-41x: same U-Boot environment location (mtd4, 0x1000), same flash
layout, same PIC on `/dev/ttyS1` at 19200 baud (qcontrol's `ts219` module uses the same codes).
The [TS-41x kit](../qnap-ts41x/README.md) should apply with these differences:

| | TS-41x | TS-11x/21x/22x |
|---|---|---|
| DTB | `kirkwood-ts419-6281.dtb` / `-6282` | `kirkwood-ts219-6281.dtb` (88F6281) / `kirkwood-ts219-6282.dtb` (88F6282: TS-119P+, TS-219P II, TS-220, ...) |
| SATA | 4 bays on PCIe 88SX7042 | 1-2 bays on the SoC's own SATA ports |
| Model string (`/proc/device-tree/model`) | QNAP TS419 family | QNAP TS219 family |

Set `DTB=` in `/etc/ts41x/boot.conf` and pass the TS-219 DTB to `ts41x-mkimage.sh`.
`ts41x-update-boot` accepts both model strings. Nobody has run the kit on these models yet;
the U-Boot env dumps for TS-119P+ and TS-219P II in qnap_mtd_resize's `resources/` show the
same stock `bootcmd` pattern the bootplan expects.
