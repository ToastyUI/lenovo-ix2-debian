#!/usr/bin/env python3
"""Analyse the tar produced by ts412-inventory.sh and print which boot route is possible.

  python3 tools/ts412-analyze.py ts412-inventory.tar

Only reads the tar. The U-Boot checks look for help/usage strings inside the
bootloader binary; that shows which commands were compiled in, not that they work
with this board's SATA controller. Treat the verdict as "worth trying" vs "not possible".
"""
import importlib.util
import os
import re
import sys
import tarfile

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("qenv", os.path.join(HERE, "qnap-uboot-env.py"))
qenv = importlib.util.module_from_spec(spec)
spec.loader.exec_module(qenv)

SECTOR = 512
AREA_OFFSET = 2048          # sectors into the area (1 MiB), see rootfs/ts41x-install-boot.sh
AREA_SECTORS = 0x18000      # 48 MiB reserved for the multi-image

# Command -> regexes that only occur when the command is compiled in (help/usage texts).
UBOOT_FEATURES = {
    "ide":      [r"ide read +addr blk# cnt", r"ide reset", r"IDE device"],
    "sata pci": [r"88SX", r"7042", r"Serial ATA"],
    "usb":      [r"usb reset", r"usb start", r"USB device"],
    "ext2load": [r"ext2load"],
    "fatload":  [r"fatload"],
    "saveenv":  [r"saveenv", r"Saving Environment"],
    "multi":    [r"Multi-File Image"],
    "uart1":    [r"\buart1\b"],
    "bootm":    [r"\bbootm\b"],
    "run":      [r"\brun var"],
}


def strings(blob, minlen=4):
    return [m.group().decode("latin-1") for m in re.finditer(rb"[\x20-\x7e]{%d,}" % minlen, blob)]


def section(title):
    print(f"\n== {title}")


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    files = {}
    with tarfile.open(sys.argv[1]) as tar:
        for m in tar.getmembers():
            if m.isfile():
                files[os.path.basename(m.name)] = tar.extractfile(m).read()
    text = lambda n: files.get(n, b"").decode("latin-1", "replace")
    verdict = {}

    section("System")
    cpu = text("cpuinfo.txt")
    for key in ("Processor", "model name", "Hardware", "BogoMIPS"):
        m = re.search(rf"^{key}\s*:\s*(.+)$", cpu, re.M)
        if m:
            print(f"{key}: {m.group(1).strip()}")
    m = re.search(r"MemTotal:\s+(\d+) kB", text("meminfo.txt"))
    if m:
        print(f"RAM: {int(m.group(1)) // 1024} MiB")
    print(text("qts-version.txt").strip() or text("version.txt").strip()[:200])
    idt = text("id.txt")
    if idt:
        print("SSH user is root (uid 0)" if "uid=0(" in idt else "WARNING: SSH user is not root: " + idt.splitlines()[1] if len(idt.splitlines()) > 1 else idt)
    eths = sorted(set(re.findall(r"^(eth\d+)", text("interfaces.txt"), re.M)))
    print(f"Ethernet interfaces: {', '.join(eths) or 'unknown'}")
    print(f"cmdline: {text('cmdline.txt').splitlines()[1] if len(text('cmdline.txt').splitlines()) > 1 else '?'}")

    section("Flash")
    mtd = {}
    for line in text("mtd.txt").splitlines():
        m = re.match(r'(mtd\d+): ([0-9a-f]+) ([0-9a-f]+) "(.+)"', line)
        if m:
            mtd[m.group(4)] = (m.group(1), int(m.group(2), 16))
            print(f"{m.group(1)}  {int(m.group(2), 16) // 1024:6d} KiB  {m.group(4)}")
    def mtd_blob(*names):
        for n in names:
            if n in mtd:
                return files.get(mtd[n][0] + ".bin")
        return None

    section("U-Boot")
    ub = mtd_blob("U-Boot", "uboot")
    feats = {}
    if ub:
        s = "\n".join(strings(ub))
        ver = re.search(r"U-Boot \d[^\n]{0,80}", s)
        print(f"version: {ver.group().strip() if ver else 'not found'}")
        for feat, pats in UBOOT_FEATURES.items():
            hits = [p for p in pats if re.search(p, s)]
            feats[feat] = bool(hits)
            print(f"{feat:9s} {'yes' if hits else 'no '}  {('(' + ', '.join(hits) + ')') if hits else ''}")
    else:
        print("no U-Boot dump found")

    section("U-Boot environment")
    env = {}
    eb = mtd_blob("U-Boot Config", "U-Boot_Config")
    if eb:
        size = qenv.detect(eb)
        if size:
            env, _ = qenv.parse(eb, size)
            print(f"env size 0x{size:x}, {len(env)} variables, CRC ok")
            for k in ("bootcmd", "bootargs", "bootdelay", "mainlineLinux"):
                print(f"{k} = {env.get(k, '(unset)')}")
            mods = [k for k in env if k.startswith(("bootcmd_", "ts_", "usb_", "load_"))]
            if mods:
                print(f"WARNING: already modified? extra boot variables: {', '.join(mods)}")
        else:
            print("CRC invalid: U-Boot is running on built-in defaults; fw_setenv/our tool cannot be trusted here")
    verdict["env ok"] = bool(env)
    if "uart1 " in env.get("bootcmd", ""):
        feats["uart1"] = True   # the stock bootcmd itself uses it (TS-119/219/419 family dumps do)

    section("Disks")
    disks = {}
    for line in text("layout.txt").splitlines():
        m = re.match(r"disk=(\S+) size_sectors=(\d+) model=(.*)", line)
        if m:
            cur = m.group(1)
            disks[cur] = {"size": int(m.group(2)), "model": m.group(3).strip(), "parts": {}}
            continue
        m = re.match(r"part=(\S+) start=(\d+) size=(\d+)", line)
        if m and disks:
            disks[cur]["parts"][int(re.search(r"(\d+)$", m.group(1)).group(1))] = (int(m.group(2)), int(m.group(3)))
    usb_like = {d for d in disks if b"USB" in files.get(f"smart-{d}.txt", b"")}
    sata = {d: v for d, v in disks.items() if d not in usb_like}
    for d, v in disks.items():
        parts = ", ".join(f"p{n}: start {s}, {sz * SECTOR // 2**20} MiB" for n, (s, sz) in sorted(v["parts"].items()))
        print(f"{d}: {v['size'] * SECTOR / 1e12:.2f} TB {v['model']}  [{parts}]")
        sm = text(f"smart-{d}.txt")
        for attr in ("overall-health", "Power_On_Hours", "Reallocated_Sector_Ct", "Current_Pending_Sector", "Offline_Uncorrectable"):
            m = re.search(rf"{attr}.*?(\S+)\s*$", sm, re.M)
            if m:
                print(f"    {attr}: {m.group(1)}")
    p2 = {d: v["parts"].get(2) for d, v in sata.items()}
    same_p2 = len({x for x in p2.values() if x}) == 1 and all(p2.values())
    if sata:
        start, size = next(iter(p2.values())) if same_p2 else (None, None)
        if same_p2 and size >= AREA_OFFSET + AREA_SECTORS:
            lba = start + AREA_OFFSET
            print(f"QTS swap partition (p2) identical on all disks: start {start}, {size * SECTOR // 2**20} MiB")
            print(f"-> boot area in p2: LBA {lba} (0x{lba:x}), {AREA_SECTORS} sectors (0x{AREA_SECTORS:x})")
            verdict["boot area"] = f"0x{lba:x}"
        else:
            print("p2 differs between disks or is too small: use --mode raw on freshly partitioned disks")

    section("RAID / LVM")
    print(text("mdstat.txt").strip())
    lvm = text("lvm.txt")
    print("LVM: " + ("yes (static volume, mount via vgchange -ay)" if re.search(r"\bvg\d+", lvm) else "no / unknown"))

    section("Verdict")
    if not ({"U-Boot Config", "U-Boot_Config"} & set(mtd) and ub):
        print("This does not look like a QNAP TS-x19 inventory (no U-Boot / U-Boot Config flash partitions).")
        print("No verdict.")
        return
    a = feats.get("ide") and feats.get("saveenv") and feats.get("multi") and verdict["env ok"]
    u = feats.get("usb") and feats.get("ext2load") and verdict["env ok"]
    print(f"Route A  (Debian from disk, QTS fallback):  {'worth trying' if a else 'NOT possible'}"
          f"{'' if a else '  (needs ide + saveenv + multi-image + valid env)'}")
    if a and not feats.get("sata pci"):
        print("         note: no 88SX7042 strings found; U-Boot may not see the PCIe SATA bays at all")
    print(f"Route A' (ix2-style USB boot):              {'worth trying' if u else 'NOT possible'}")
    print("Route B  (Debian in flash via qnap_mtd_resize): possible (TS-412 success reported upstream),")
    print("         but needs a kernel under 3 MiB; this repo's 7.1.9 zImage is 4.8 MiB (docs/kernel.md)")
    print(f"PIC LED feedback from U-Boot (uart1):     {'yes' if feats.get('uart1') else 'no'}")


if __name__ == "__main__":
    main()
