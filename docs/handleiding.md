# Lenovo ix2-ng: Debian vanaf USB met LifeLine als terugval

Dit communityproject start Debian vanaf een USB-stick. De originele LifeLine-
systeempartities en bootsectoren op de SATA-schijven blijven intact. Het is geen
officiële Lenovo-firmware. De beschreven bootinstellingen zijn bedoeld voor de
ix2-ng met stock U-Boot 0.0.8; controleer eerst je eigen model en bootomgeving.

## Hoe de boot werkt

1. U-Boot probeert `/uImage` en `/uInitrd` op de eerste USB-partitie te laden.
2. Debian mount de tweede USB-partitie (`LABEL=rootfs`) als `/` en de eerste
   (`LABEL=BOOT`) als `/boot`. Debian wordt niet op de interne schijven geïnstalleerd.
3. Zonder werkende USB-boot probeert U-Boot de oorspronkelijke LifeLine-bootregel.
4. Voor een bewuste terugval: zet de NAS uit, verwijder de stick en start opnieuw.

LifeLine is een **terugvalbesturingssysteem**, geen back-up van je bestanden.
Bewaar daarnaast een onafhankelijke gegevensback-up. Als de oorspronkelijke
systeempartities worden gewist, werkt de terugval niet meer.

## 1. Voorbereiden

- Controleer het model, de bestaande schijfindeling en de originele bootregels.
- Maak een gegevensback-up en bewaar uitvoer van `fw_printenv` buiten GitHub.
- Gebruik een aparte USB-stick (8–32 GB) en een Linux-bouwhost. Een Proxmox-VM
  of container is mogelijk; geef alleen de bedoelde USB-stick door.
- Gebruik je eigen SSH-sleutelpaar. Alleen de publieke sleutel mag op de USB-stick.
- De adressen in `192.0.2.0/24`, gebruikersnamen en MAC-adressen in deze repository
  zijn voorbeelden. Vervang ze door jouw eigen waarden.

## 2. SSH in de originele LifeLine-firmware

Open de LifeLine-webinterface op het eigen NAS-adres. Ga naar **Support Diagnostics**
(`/diagnostics.html`) en schakel SSH in.

Voor de hier gebruikte LifeLine-versie is de login:

```text
User:     root
Password: soho<JOUW_BEHEERDERSWACHTWOORD>
```

Typ `soho` direct vóór het beheerderswachtwoord dat je zelf in de LifeLine-
webinterface hebt ingesteld, zonder spatie of de tekens `<` en `>`.
Voorbeeld met een fictief beheerderswachtwoord `Voorbeeld123!`:
het SSH-wachtwoord is `sohoVoorbeeld123!`.
Dit is de LifeLine-login, niet het wachtwoord van Debian. Firmwareversies kunnen
verschillen; als dit niet werkt, controleer de documentatie van je versie.

```bash
ssh root@192.0.2.100  # vervang het voorbeeldadres
```

Maak na het inloggen een eigen back-up:

```bash
fw_printenv
fw_printenv bootcmd bootcmd2
```

Bewaar die uitvoer veilig op een andere computer. De geredigeerde bestanden in
`uboot/` zijn voorbeelden en geen vervanging voor je eigen back-up.

## 3. Debian-rootfs bouwen

Gebruik een wegwerpomgeving met rootrechten, armel-ondersteuning via
qemu/binfmt en de tools `debootstrap`, `u-boot-tools`, `initramfs-tools`,
`parted`, `e2fsprogs`, `rsync` en de benodigde uitpaktools.

Lees `rootfs/build.sh` vóór uitvoering. Het script verwacht in `/root/ix2/k/`
het uitgepakte bodhi-kernelpakket voor de daarin vastgelegde kernelversie en in
`/root/ix2/authorized_keys` jouw eigen publieke SSH-sleutel(s). Haal het pakket
bij de upstreambron en controleer de bijbehorende checksums.
Het script bouwt `/root/ix2/rootfs` opnieuw op; gebruik die map niet voor eigen data.

```bash
bash rootfs/build.sh
```

Het resultaat bevat `/boot/uImage`, `/boot/uInitrd` en de ix2-ng device tree.
Gebruik bij de eerste installatie de baseline-kernel A. Kernel C is een
prestatie-experiment met minder hardening; zie `kernel-options.md`.

De gebouwde rootfs bevat jouw `authorized_keys`: publiceer deze persoonlijke
image niet. Het project levert broncode en configuratievoorbeelden, geen
universele persoonlijke rootfs-image.

## 4. Alleen de USB-stick voorbereiden

**Deze stap wist de gekozen USB-stick. De SATA-schijven blijven onaangeroerd.**
Controleer het apparaat met `lsblk`; gebruik een expliciet USB-pad onder
`/dev/disk/by-id/`. Kies nooit blind `/dev/sda` of `/dev/sdb`.

```bash
lsblk -o NAME,SIZE,MODEL,TRAN,MOUNTPOINT
ls -l /dev/disk/by-id/usb-*
STICK=/dev/disk/by-id/usb-MERK_MODEL_SERIENUMMER-0:0
readlink -f "$STICK"
# Controleer het apparaat en ontkoppel bestaande mounts vóór de volgende regels.
wipefs -a "$STICK"
parted -s "$STICK" mklabel msdos
parted -s "$STICK" mkpart primary ext2 1MiB 257MiB
parted -s "$STICK" mkpart primary ext4 257MiB 100%
partprobe "$STICK"
# Wacht tot beide partitiepaden bestaan.
ls "${STICK}-part1" "${STICK}-part2"
mkfs.ext2 -L BOOT "${STICK}-part1"
mkfs.ext4 -L rootfs "${STICK}-part2"
mkdir -p /mnt/ix2root
mount "${STICK}-part2" /mnt/ix2root
mkdir -p /mnt/ix2root/boot
mount "${STICK}-part1" /mnt/ix2root/boot
rsync -aHAX --numeric-ids /root/ix2/rootfs/ /mnt/ix2root/
sync
umount /mnt/ix2root/boot
umount /mnt/ix2root
```

Het buildscript zet de rootfs- en BOOT-labels in `fstab` en gebruikt DHCP.
Controleer vóór het ontkoppelen of de twee bootbestanden op de BOOT-partitie staan.

## 5. USB-boot instellen zonder U-Boot te vervangen

Doe dit in LifeLine via SSH. Vergelijk eerst je eigen `bootcmd`, `bootcmd2` en
flashlayout met de voorbeelden. Het script past bootvariabelen in flash aan;
het vervangt niet de U-Boot-binary. Het bevat een ix2-ng-specifieke stockbootregel:
voer het niet uit bij een afwijkende bootomgeving.

Lees `uboot/fw_setenv-usb-boot.sh`, controleer de stockbootregel en voer daarna
het script op de NAS uit. Controleer de resulterende waarden met `fw_printenv`.
Bewaar de oorspronkelijke waarden buiten de NAS.

Zet de NAS uit, steek de USB-stick in de NAS en start opnieuw. Zoek het DHCP-adres.

## 6. Eerste Debian-boot controleren

Debian gebruikt de publieke SSH-sleutel uit stap 3, niet het LifeLine-wachtwoord.

```bash
ssh -i ~/.ssh/id_ed25519 root@192.0.2.100  # eigen sleutel en NAS-adres
uname -a
cat /etc/debian_version
findmnt /
findmnt /boot
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT
```

Controleer dat `/` en `/boot` bij de USB-stick horen. De host key van Debian
verschilt van LifeLine: verifieer de nieuwe fingerprint via een vertrouwd kanaal.
Verwijder niet blind host-key-controles.

## 7. Interne schijven behouden

Voer **geen** `wipefs`, `mkfs`, `parted mklabel` of `mdadm --create` uit op de
interne SATA-schijven. Kopieer geen RAID-UUIDs van een ander apparaat.

```bash
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT
cat /proc/mdstat
mdadm --detail --scan
```

Identificeer eerst de bestaande LifeLine-systeemarrays en data-array.
`config/etc/mdadm/mdadm.conf` is een voorbeeld zonder apparaat-UUIDs; genereer
je eigen configuratie lokaal. Inspecteer bestaande data eerst alleen-lezen.
De dienst `ix2-lifeline-ro.service` kan ongebruikte arrays met metadata 0.90
alleen-lezen zetten, maar detecteert niet automatisch elke LifeLine-layout.
Controleer daarom altijd zelf welke partities bij het originele systeem horen.

Gebruik bestaande data pas nadat filesystem, RAID-layout en rechten zijn
gecontroleerd. Schrijven vanuit Debian en LifeLine kan verschillen in rechten
of applicatiemetadata veroorzaken. Laat de originele systeempartities ongemoeid.

## 8. Netwerkdiensten en updates

Pas de voorbeelden in `config/` aan je eigen omgeving aan. Stel voor SMB een
eigen gebruiker en wachtwoord in. Beperk NFS tot specifieke vertrouwde clients;
`no_root_squash` geeft die client rootrechten op de export. Gebruik geen publieke
portforwarding naar SSH, SMB of NFS.

Installeer Debian-updates en controleer ook upstream kernelupdates; een aangepaste
kernel wordt niet automatisch bijgewerkt door Debian. Test kernelwissels via de
USB-stick en behoud een werkende kopie. Testscripts in `bench/` wijzigen exports,
routes en mounts en zijn bedoeld voor een geïsoleerde testomgeving.

Voor de volgende stap: [RAID-bewaking, leds, schijfrust en Gmail](monitoring.md).
Voor gemeten prestaties en testbeperkingen: [benchmarks](benchmarks.md).

## 9. Terug naar LifeLine

1. Sluit Debian netjes af met `poweroff` en wacht tot de NAS uit staat.
2. Verwijder de USB-stick.
3. Start de NAS: de bewaarde stockbootregel probeert LifeLine op de SATA-schijven.
4. Gebruik in de LifeLine-webinterface **geen initialize-, format- of resetactie**
   als je bestaande data wilt behouden.

Test deze terugval voordat je op de opstelling vertrouwt. Het behoud van LifeLine
is geen garantie tegen schijfstoringen en vervangt geen onafhankelijke back-up.

## Upstreambronnen

- [bodhi: Kirkwood-kernel en Debian-rootfs](https://forum.doozan.com/read.php?2,12096)
- [Doozan: ix2-dl/ix2-ng met stock U-Boot](https://forum.doozan.com/read.php?2,70294)
- [Debian release-informatie](https://www.debian.org/releases/)
