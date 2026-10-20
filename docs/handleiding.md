# Lenovo ix2 → Debian, als NFS-opslag voor Proxmox

Handleiding voor jouw toestel: **Lenovo ix2 (ix2-ng)** (ix2-ng), Marvell Kirkwood 88F6282, 256 MB RAM, stock U-Boot 0.0.8 in SPI-flash, 2 SATA-schijven.

**Doel:** een minimale Debian op een USB-stick, de twee schijven als RAID 1, en NFS (voor Proxmox en Immich) plus Samba (voor de Mac en telefoons, rechtstreeks op de ix2).

---

## Gebruik van deze handleiding

Community-handleiding voor de Lenovo ix2-ng; geen officieel Lenovo-product.
Alle adressen in `192.0.2.0/24`, MAC-adressen en gebruikersnamen zijn voorbeelden.
Vervang ze door je eigen gegevens. Dit document combineert historische
installatieroutes; lees eerst de README en kies één route. Voer geen wis- of
partitioneercommando's uit op schijven met gegevens die je wilt bewaren.
Bewaar een eigen `fw_printenv`-back-up buiten deze repository.
Controleer actuele Debian- en kernelondersteuning bij de genoemde upstreambronnen.

---

## Fase 0: Voorbereiding

**Benodigd**
- [ ] USB-stick van **8–32 GB** (USB 2.0-compatibel, een bekend merk)
- [ ] Je Proxmox-host met een vrije USB-poort
- [ ] SSH-toegang tot de ix2 (via de diagnostics-pagina, dat werkt al)
- [ ] Optioneel maar aanbevolen: een **3,3 V USB-TTL-adapter** als noodtoegang

**Controleer eerst**
- [ ] Het secure erase is **100% klaar** en de NAS staat weer normaal aan
- [ ] Het label onder de NAS: noteer model en onderdeelnummer
- [ ] `~/ix2-private-backup/fw_printenv.txt` bestaat

**Waarom deze volgorde veilig is**
We passen **alleen bootvariabelen** aan, niet U-Boot zelf. De bootvolgorde wordt: **eerst de USB-stick, anders de originele firmware van de schijf**. Pas als Debian goed werkt, nemen we de schijven in gebruik.

---

## Fase 1: Bestanden downloaden (op de Proxmox-host)

Open een shell op je Proxmox-host (via de webinterface: node → **Shell**, of via SSH).

Ga naar de releasethread van bodhi op het doozan-forum:
**https://forum.doozan.com/read.php?2,12096**

Download daaruit, met de links in het eerste bericht:
1. De **Debian Kirkwood rootfs** (op het moment van schrijven `Debian-6.5.7-kirkwood-tld-1-rootfs-bodhi.tar.bz2`, Debian 12 bookworm; neem de nieuwste die daar staat).
2. Optioneel: het **nieuwste kernelpakket** `linux-6.x.x-kirkwood-tld-1-bodhi.tar.bz2`. De rootfs bevat al een kernel, dus voor de eerste installatie is dit niet nodig.

Controleer de checksum (md5/sha256) die bodhi bij elk bestand vermeldt:

```bash
mkdir -p /root/ix2 && cd /root/ix2
# zet de gedownloade bestanden hier neer, daarna:
md5sum *.tar.bz2
sha256sum *.tar.bz2
```

Vergelijk de uitkomst met de waarden in de thread. **Klopt het niet, ga dan niet verder.**

Benodigde tools:

```bash
apt update && apt install -y u-boot-tools bzip2 parted dosfstools e2fsprogs
```

---

## Fase 2: USB-stick voorbereiden (op de Proxmox-host)

> **Gevaar:** in deze fase wis je een schijf. Kies **alleen** de USB-stick. Gebruik het pad uit `/dev/disk/by-id/usb-…`, nooit een gok als `/dev/sdb`.

### 2.1 De stick vinden

Steek de stick in de Proxmox-host en kijk welke het is:

```bash
lsblk -o NAME,SIZE,MODEL,TRAN,MOUNTPOINT
ls -l /dev/disk/by-id/ | grep -i usb
```

Zoek de regel met `TRAN` = `usb` en de juiste grootte. Zet het pad in een variabele (pas de naam aan):

```bash
STICK=/dev/disk/by-id/usb-MERK_MODEL_SERIENUMMER-0:0
readlink -f "$STICK"     # toont bv. /dev/sdX; controleer met lsblk dat dit de stick is
```

### 2.2 Partitioneren: MBR, BOOT 256 MB ext2, rootfs ext4

```bash
wipefs -a "$STICK"
parted -s "$STICK" mklabel msdos
parted -s "$STICK" mkpart primary ext2 1MiB 257MiB
parted -s "$STICK" mkpart primary ext4 257MiB 100%
partprobe "$STICK"; sleep 2

mkfs.ext2 -L BOOT "${STICK}-part1"
mkfs.ext4 -L rootfs "${STICK}-part2"
```

### 2.3 De rootfs uitpakken

```bash
mkdir -p /mnt/ix2root
mount "${STICK}-part2" /mnt/ix2root
mkdir -p /mnt/ix2root/boot
mount "${STICK}-part1" /mnt/ix2root/boot

cd /mnt/ix2root
tar -xjf /root/ix2/Debian-*-kirkwood-tld-1-rootfs-bodhi.tar.bz2
ls /mnt/ix2root/boot      # hier staan zImage-…, initrd.img-…, map dts/
```

### 2.4 Kernel met de juiste device tree (`uImage`) en `uInitrd`

Dit is de belangrijkste stap. De device tree moet **`kirkwood-lenovo-ix2-ng.dtb`** zijn.

```bash
cd /mnt/ix2root/boot
ls dts/ | grep -i ix2          # moet kirkwood-lenovo-ix2-ng.dtb tonen

KVER=$(ls zImage-* | head -1 | sed 's/zImage-//')
echo "Kernelversie: $KVER"

cp "zImage-$KVER" zImage.fdt
cat dts/kirkwood-lenovo-ix2-ng.dtb >> zImage.fdt

mkimage -A arm -O linux -T kernel  -C none -a 0x00008000 -e 0x00008000 \
        -n "Linux-$KVER" -d zImage.fdt uImage
mkimage -A arm -O linux -T ramdisk -C gzip -a 0x00000000 -e 0x00000000 \
        -n "initramfs-$KVER" -d "initrd.img-$KVER" uInitrd

ls -la uImage uInitrd
```

### 2.5 fstab en netwerk

```bash
cat >> /mnt/ix2root/etc/fstab <<'EOF'
LABEL=rootfs  /      ext4  defaults,noatime  0 1
LABEL=BOOT    /boot  ext2  defaults,noatime  0 2
EOF

cat /mnt/ix2root/etc/network/interfaces    # standaard DHCP op eth0, dat is goed
```

Het IP regel je met een **DHCP-reservering in OPNsense** op MAC-adres **`02:00:00:00:00:01`**, voor bijvoorbeeld `192.0.2.100`.

### 2.6 Afronden

```bash
sync; sync
umount /mnt/ix2root/boot
umount /mnt/ix2root
sync
```

Haal de stick eruit.

---

## Fase 3: Bootvolgorde aanpassen (op de ix2, via SSH in LifeLine)

Log in via SSH op de ix2 (LifeLine draait nog):

```bash
ssh root@192.0.2.100
```

### 3.1 Controleer de back-up nog één keer

```bash
fw_printenv bootcmd
fw_printenv bootcmd2
```

Dit moet overeenkomen met je back-upbestand.

### 3.2 De nieuwe variabelen zetten, mét terugval naar de originele firmware

Typ de regels **één voor één**, niet alles tegelijk plakken:

```bash
fw_setenv bootcmd_stock 'ide reset; ide read 0x40000 0x800 0x1800; ide read 0x900000 0x2000 0x2000; setenv bootargs $(console) $(bootargs_root) $(bootargs_mtd) $(bootargs_end); bootm 0x40000 0x900000; run bootcmd2'

fw_setenv usb_set_bootargs 'setenv bootargs console=ttyS0,115200 root=LABEL=rootfs rootdelay=10 earlyprintk=serial'
fw_setenv load_uimage 'ext2load usb 0:1 0x800000 /uImage'
fw_setenv load_uinitrd 'ext2load usb 0:1 0x2100000 /uInitrd'
fw_setenv usb_boot 'mw 0x800000 0 1; run load_uimage; run load_uinitrd; bootm 0x800000 0x2100000'
fw_setenv usb_bootcmd 'run usb_set_bootargs; run usb_boot'

fw_setenv bootcmd 'usb reset; run usb_bootcmd; usb stop; run bootcmd_stock'
```

Controleer:

```bash
fw_printenv bootcmd bootcmd_stock usb_bootcmd usb_boot load_uimage load_uinitrd usb_set_bootargs
```

**Hoe het werkt:** U-Boot probeert eerst van USB te booten. Lukt dat niet (geen stick, of een leesfout), dan voert hij `bootcmd_stock` uit, het originele commando, en start LifeLine gewoon van de schijf.

---

## Fase 4: Eerste boot van Debian

1. Zet de ix2 uit (via de webinterface of `poweroff` in SSH).
2. Steek de stick in de **achterste USB-poort**.
3. Zet de ix2 aan en wacht 2–3 minuten.
4. Zoek het IP-adres (DHCP-lease in OPNsense, of vanaf je Mac):

```bash
arp -a | grep -i "02:00:00:00:00:01"
```

5. Inloggen: op de zelfgebouwde stick **alleen met de SSH-sleutel** (geen wachtwoord). (Bij de rootfs van bodhi was het `root` / `root`.)

```bash
ssh -i ~/.ssh/id_ed25519 root@192.0.2.100
```

6. Controleren of je in Debian zit:

```bash
uname -a            # moet een 6.x kirkwood-tld-kernel tonen, niet 2.6.31
cat /etc/debian_version
```

**Komt de ix2 in LifeLine in plaats van Debian?** Dan las U-Boot de stick niet. Zie "Problemen oplossen".

---

## Fase 5: Debian beveiligen en bijwerken

### 5.1 Direct doen

```bash
passwd                                  # nieuw, sterk root-wachtwoord
adduser nasuser                           # eigen gebruiker
apt update && apt install -y sudo
usermod -aG sudo nasuser
```

Zet je SSH-sleutel erop (vanaf de Mac):

```bash
ssh-copy-id nasuser@192.0.2.100
```

Daarna inloggen met een wachtwoord en als root uitschakelen:

```bash
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/; s/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl restart ssh
```

> Test eerst in een **tweede terminal** of inloggen met je sleutel werkt, voordat je de eerste sluit.

### 5.2 Bootvariabelen ook vanuit Debian kunnen lezen

```bash
apt install -y libubootenv-tool
cat /proc/mtd
```

Zet in `/etc/fw_env.config` de regel voor de env-partitie. Gebruik het juiste `/dev/mtdX` uit `/proc/mtd` (de partitie die "env" heet; grootte 0x1000):

```
/dev/mtd1  0x0000  0x1000  0x1000
```

Test met `fw_printenv`. Je moet dezelfde waarden zien als in je back-up. Zie de doozan-HOWTO "access printenv from Debian" bij twijfel.

### 5.3 Upgraden naar Debian 13 (trixie)

Controleer vóór een distributie-upgrade de actuele armel-ondersteuning en beveiligingsstatus bij Debian.

```bash
apt update && apt full-upgrade -y
apt-mark hold $(dpkg -l | awk '/linux-image/ {print $2}')   # houd de kernel van bodhi vast
sed -i 's/bookworm/trixie/g' /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null
apt update && apt full-upgrade -y
reboot
```

> Installeer **geen** Debian-kernel. De armel-kernels van Debian ondersteunen de ix2 niet; je gebruikt de kernels van bodhi. Nieuwe kernels installeer je volgens de instructies in de doozan-thread, en daarna maak je `uImage` opnieuw met de **ix2-ng-DTB** (stap 2.4).

### 5.4 Automatische beveiligingsupdates

```bash
apt install -y unattended-upgrades
dpkg-reconfigure -plow unattended-upgrades
```

---

## Fase 6: Schijven controleren en RAID 1 maken

> Pas doen als Debian stabiel boot. Hiermee verdwijnt LifeLine **definitief** van de schijven, en daarmee ook de terugval.

### 6.1 Gezondheid van de schijven

```bash
apt install -y smartmontools mdadm
lsblk -o NAME,SIZE,MODEL,SERIAL
smartctl -H /dev/sda; smartctl -H /dev/sdb
smartctl -A /dev/sda | grep -iE "Reallocated|Pending|Uncorrect|Power_On"
smartctl -A /dev/sdb | grep -iE "Reallocated|Pending|Uncorrect|Power_On"
```

Zie je `Reallocated_Sector_Ct`, `Current_Pending_Sector` of `Offline_Uncorrectable` **groter dan 0**? Vertrouw die schijf dan niet voor belangrijke data.

### 6.2 RAID 1 opzetten

Controleer eerst met `lsblk` dat `/dev/sda` en `/dev/sdb` de **twee SATA-schijven** zijn, en niet de stick.

```bash
wipefs -a /dev/sda /dev/sdb
parted -s /dev/sda mklabel gpt mkpart data 1MiB 100% set 1 raid on
parted -s /dev/sdb mklabel gpt mkpart data 1MiB 100% set 1 raid on

mdadm --create /dev/md0 --level=1 --raid-devices=2 /dev/sda1 /dev/sdb1
cat /proc/mdstat            # synchroniseren duurt uren, je kunt intussen verder

mkfs.ext4 -L nasdata /dev/md0
mdadm --detail --scan >> /etc/mdadm/mdadm.conf
update-initramfs -u
```

> Na `update-initramfs` moet je **`uInitrd` opnieuw maken** (stap 2.4, alleen de `mkimage … ramdisk`-regel, nu direct in `/boot` op de ix2), anders kent de boot het RAID mogelijk niet.

### 6.3 Mounten

```bash
mkdir -p /srv/nas
echo 'LABEL=nasdata  /srv/nas  ext4  defaults,noatime  0 2' >> /etc/fstab
mount -a && df -h /srv/nas
```

### 6.4 Meldingen bij een kapotte schijf

```bash
# in /etc/mdadm/mdadm.conf:  MAILADDR jouw@adres   (vereist een mailer, bv. msmtp)
```

---

## Fase 7: NFS-server

```bash
apt install -y nfs-kernel-server
mkdir -p /srv/nas/proxmox /srv/nas/share
```

`/etc/exports`: **alleen het IP van je Proxmox-host** (vul in):

```
/srv/nas  PROXMOX_IP(rw,sync,no_subtree_check,no_root_squash)
```

```bash
exportfs -ra
exportfs -v
```

> `no_root_squash` is nodig omdat Proxmox als root back-ups schrijft. Daarom is de beperking tot alleen het Proxmox-IP verplicht.

### Firewall op de ix2 (nftables)

```bash
apt install -y nftables
cat > /etc/nftables.conf <<'EOF'
#!/usr/sbin/nft -f
flush ruleset
table inet filter {
  chain input {
    type filter hook input priority 0; policy drop;
    ct state established,related accept
    iif lo accept
    ip saddr { PROXMOX_IP, MAC_IP } tcp dport 22 accept
    ip saddr PROXMOX_IP tcp dport { 111, 2049 } accept
    ip saddr PROXMOX_IP udp dport { 111, 2049 } accept
    icmp type echo-request accept
  }
}
EOF
systemctl enable --now nftables
```

> Vul `PROXMOX_IP` en `MAC_IP` in, en test SSH vanuit een tweede terminal **voordat** je de huidige sessie sluit.

---

## Fase 8: Proxmox koppelen

### 8.1 NFS-opslag toevoegen

Proxmox-webinterface → **Datacenter → Storage → Add → NFS**:
- **ID:** `ix2`
- **Server:** `192.0.2.100`
- **Export:** `/srv/nas` (verschijnt in de lijst)
- **Content:** `VZDump backup file`, `ISO image`, `Container template`
- **Niet** gebruiken voor VM-schijven (te traag en te kwetsbaar)

De share wordt op de host gekoppeld als `/mnt/pve/ix2`.

### 8.2 Samba-container voor de Mac

1. Maak een **Debian-LXC** aan (klein: 1 core, 512 MB RAM).
2. Koppel een map van de NFS-opslag erin (op de Proxmox-host):

```bash
pct set <CTID> -mp0 /mnt/pve/ix2/share,mp=/srv/share
```

3. In de container: `apt install samba`, maak een gebruiker en een share op `/srv/share`.

> **Let op met rechten:** een *unprivileged* LXC mapt root naar UID 100000. Op een NFS-map geeft dat vaak schrijfproblemen. Kies voor deze container **privileged**, of zet op de ix2 de eigenaar van `/srv/nas/share` op `100000:100000`.

### 8.3 Back-ups

Proxmox → **Datacenter → Backup → Add**: Storage `ix2`, Mode `Snapshot`, een rustig tijdstip, met retentie (bijvoorbeeld 7 dagelijks, 4 wekelijks). Zet in `/etc/vzdump.conf` eventueel `bwlimit` als het netwerk volloopt.

---

## Fase 9: OPNsense-regels

Op de interface of het VLAN van de NAS (192.0.2.0/24):

| # | Actie | Bron | Doel | Poort | Waarom |
|---|---|---|---|---|---|
| 1 | Toestaan | Proxmox-IP | 192.0.2.100 | TCP/UDP 111, 2049 | NFS |
| 2 | Toestaan | Mac-IP, Proxmox-IP | 192.0.2.100 | TCP 22 | Beheer |
| 3 | Toestaan | 192.0.2.100 | Debian-mirrors (alias) | TCP 80, 443 | Updates |
| 4 | Toestaan | 192.0.2.100 | OPNsense | UDP 53, 123 | DNS en tijd |
| 5 | **Blokkeren** | 192.0.2.100 | any | any | Verder geen internet |

Plus: geen port forwards naar de ix2, en **UPnP uit**.

---

## Problemen oplossen

| Symptoom | Oorzaak / oplossing |
|---|---|
| ix2 start **LifeLine** in plaats van Debian | U-Boot kon de stick niet lezen. Probeer een andere (kleinere) stick, de andere USB-poort, of formatteer BOOT opnieuw met `mkfs.ext2 -I 128 -L BOOT` en zet `uImage`/`uInitrd` terug |
| Hangt bij "Starting kernel…" (alleen zichtbaar met een seriële kabel) | **Verkeerde device tree.** Controleer dat `kirkwood-lenovo-ix2-ng.dtb` is aangehangen (stap 2.4). Helpt dat niet, kijk dan in de doozan-HOWTO naar `mainlineLinux`/`arcNumber` (de ix2-dl-handleiding gebruikt `mainlineLinux=yes`, `arcNumber=1682`) |
| Geen netwerk na boot | Controleer de DHCP-lease in OPNsense op MAC `02:00:00:00:00:01`; de interface heet `eth0` |
| RAID niet gevonden na reboot | `uInitrd` niet opnieuw gemaakt na `update-initramfs` (zie 6.2) |
| Alles mislukt | Trek de stick eruit en zet de ix2 aan. Zolang de schijven niet zijn omgezet (fase 6), start LifeLine gewoon. Of zet terug met `fw_setenv bootcmd '…'` uit je back-upbestand |

### Terug naar de originele situatie (zolang fase 6 nog niet is gedaan)

```bash
fw_setenv bootcmd 'ide reset; ide read 0x40000 0x800 0x1800; ide read 0x900000 0x2000 0x2000; setenv bootargs $(console) $(bootargs_root) $(bootargs_mtd) $(bootargs_end); bootm 0x40000 0x900000;run bootcmd2'
```

---

## Wat je realistisch mag verwachten

- **Snelheid:** ongeveer 30–70 MB/s via NFS (CPU, 1 GbE en oude schijven). Prima voor back-ups, ISO's en bestanden; niet voor VM-schijven.
- **Levensduur:** afhankelijk van de actuele ondersteuning van Debian en de gebruikte kernel. Plan daarna een vervanger, of hang de schijven direct in de Proxmox-host.

## Bronnen

- [Doozan: Linux Kernel Kirkwood package en Debian rootfs (bodhi)](https://forum.doozan.com/read.php?2,12096)
- [Doozan: HOWTO Lenovo ix2-dl/ix2-ng, stock U-Boot, printenv vanuit Debian](https://forum.doozan.com/read.php?2,70294)
- [Doozan: Debian op de ix2-ng](https://forum.doozan.com/read.php?2,120309,page=1)
- [ArchyCho/Lenovo-IX2-Debian (GitHub)](https://github.com/ArchyCho/Lenovo-IX2-Debian)
- [NeverBehave/IX2-dl-alarm (GitHub)](https://github.com/NeverBehave/IX2-dl-alarm)
- [Debian trixie release-informatie (armel-status)](https://debian.org/releases/trixie)
