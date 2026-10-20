#!/bin/sh
# Run on the ix2 while it still runs stock LifeLine (SSH via Support Diagnostics).
# Boots from USB first (ext2 partition 1: /uImage + /uInitrd), falls back to the stock disk boot.
# `mw 0x800000 0 1` clears the load address so a failed USB load makes bootm fail safely and fall through.
set -e
fw_printenv bootcmd   # must match env-original-redacted.txt before changing anything
fw_setenv bootcmd_stock 'ide reset; ide read 0x40000 0x800 0x1800; ide read 0x900000 0x2000 0x2000; setenv bootargs $(console) $(bootargs_root) $(bootargs_mtd) $(bootargs_end); bootm 0x40000 0x900000; run bootcmd2'
fw_setenv usb_set_bootargs 'setenv bootargs console=ttyS0,115200 root=LABEL=rootfs rootdelay=10 earlyprintk=serial'
fw_setenv load_uimage 'ext2load usb 0:1 0x800000 /uImage'
fw_setenv load_uinitrd 'ext2load usb 0:1 0x2100000 /uInitrd'
fw_setenv usb_boot 'mw 0x800000 0 1; run load_uimage; run load_uinitrd; bootm 0x800000 0x2100000'
fw_setenv usb_bootcmd 'run usb_set_bootargs; run usb_boot'
fw_setenv bootcmd 'usb reset; run usb_bootcmd; usb stop; run bootcmd_stock'
for v in bootcmd bootcmd_stock usb_bootcmd usb_boot load_uimage load_uinitrd usb_set_bootargs; do fw_printenv $v; done
