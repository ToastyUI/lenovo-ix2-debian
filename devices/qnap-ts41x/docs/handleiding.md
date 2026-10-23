# QNAP TS-41x: Debian 13 vanaf disk, met QTS als terugval

Voor TS-410/412/419P/419U (Kirkwood 88F6281, DTB `kirkwood-ts419-6281.dtb`). TS-11x/21x/22x
gebruiken dezelfde PIC en U-Boot-familie met `kirkwood-ts219-*.dtb`: zelfde stappen, ander DTB,
**niet getest**.

Status: de scripts zijn getest tegen gesimuleerde hardware (loop-disks met een QTS-indeling,
een pty in plaats van de PIC, echte TS-419P-U-Boot-envdumps, kruiscontrole met libubootenv).
Nog niet op een echte TS-412 geboot. Lees eerst alles, voer dan stap voor stap uit.

## Hoe het werkt

- QTS blijft in de flash staan en is de terugval. Debian komt op de schijven.
- U-Boot laadt één *multi*-image (zImage + DTB + initramfs) met `ide read` uit een vast stuk
  van partitie 2 van elke schijf (de QTS-swap, md256). QTS-data op partitie 3 blijft onaangeroerd.
- **One-shot-bewaking:** `bootcmd_debian` zet eerst `bootcmd` terug naar QTS en doet `saveenv`,
  pas daarna probeert hij Debian. Mislukt het lezen of de CRC, dan boot QTS in dezelfde start.
  Hangt Debian, dan boot na stroom eraf/erop QTS. Alleen een volledig opgestarte Debian zet de
  volgende Debian-poging weer aan (`ts41x-boot-ok.service`). Een boot-lus kan dus niet.
- Debians rootfs staat op een USB-stick met label `rootfs` (zoals bij de ix2).

Wat U-Boot moet kunnen: `ide`, `saveenv`, multi-images. `ts412-analyze.py` controleert dat vooraf.
Of de U-Boot de bays achter de PCIe-controller (Marvell 88SX7042) ziet, blijkt pas bij de eerste
poging; gaat het mis, dan start QTS gewoon.

**Verzekering:** een USB-TTL-adapter van 3,3 V (seriële console, 115200) kost een paar euro.
Met de one-shot-bewaking is hij niet nodig om terug te komen, wel om te zien wát er misgaat.

## 0. Wat je nodig hebt

- PC met Linux (of Proxmox-VM/container) voor het bouwen: `debootstrap qemu-user-static
  binfmt-support u-boot-tools device-tree-compiler gcc-arm-linux-gnueabi python3`.
- USB-stick (≥ 4 GB) voor de rootfs.
- SSH op QTS: Configuratiescherm → Netwerkdiensten → Telnet/SSH. Login `admin` (is root).
  QTS heeft geen scp/sftp; bestanden gaan via `ssh ... 'cat > bestand' < bestand`.

## 1. Inventaris (alleen lezen)

```sh
ssh admin@NAS 'sh -s' < devices/qnap-ts41x/tools/ts412-inventory.sh > ts412-inventory.tar
python3 devices/qnap-ts41x/tools/ts412-analyze.py ts412-inventory.tar
```

Bewaar `ts412-inventory.tar`: daar zitten ook kopieën van alle flashpartities in (mtd0–mtd5).
Dat is je terugweg. Het script schrijft niets.

Stop hier als het oordeel voor Route A "NOT possible" is. Dan blijft route B over
(Debian in de flash via [qnap_mtd_resize](https://github.com/amouiche/qnap_mtd_resize_for_bullseye),
geen QTS-terugval).

Controleer ook de SMART-waarden per schijf in de uitvoer. Oude schijven eerst vervangen.

## 2. Kernel en rootfs bouwen (op de PC)

```sh
sudo devices/qnap-ts41x/kernel/build-kernel.sh C            # C = snelst; B = met hardening
sudo devices/qnap-ts41x/build-rootfs.sh /root/ts41x/kernel/out/linux-image-*.deb ~/.ssh/id_ed25519.pub
```

Uitvoer in `/root/ts41x/out`: `rootfs.tar.zst` en `boot.uimg`.

USB-stick klaarmaken (controleer `sdX`!):

```sh
sudo mkfs.ext4 -L rootfs /dev/sdX1
sudo mount /dev/sdX1 /mnt && sudo tar -C /mnt -xf /root/ts41x/out/rootfs.tar.zst && sudo umount /mnt
```

## 3. Probe: blijft `saveenv` bewaard? (fase 1)

```sh
ssh admin@NAS 'cat /dev/mtdblock4' > mtd4.orig.bin           # nogmaals, vlak voor de wijziging
python3 devices/qnap-ts41x/tools/ts41x-bootplan.py stage1 --env mtd4.orig.bin -o stage1.txt
python3 devices/qnap-ts41x/tools/qnap-uboot-env.py set mtd4.orig.bin -s stage1.txt -o mtd4.stage1.bin
python3 devices/qnap-ts41x/tools/qnap-uboot-env.py show mtd4.stage1.bin   # nalezen!
ssh admin@NAS 'cat > /dev/mtdblock4' < mtd4.stage1.bin
ssh admin@NAS reboot
```

Fase 1 boot QTS precies zoals altijd, maar laat U-Boot eerst `ts_probe_saveenv=ok` opslaan.
Na de herstart:

```sh
ssh admin@NAS 'cat /dev/mtdblock4' > mtd4.after1.bin
python3 devices/qnap-ts41x/tools/qnap-uboot-env.py get mtd4.after1.bin ts_probe_saveenv   # moet "ok" zijn
```

Staat er nog `pending`? Dan bewaart deze U-Boot geen env (dat is op een TS-421 gemeld) en werkt
de bewaking niet. Zet het origineel terug (`cat > /dev/mtdblock4 < mtd4.orig.bin`) en stop.

## 4. Boot-image op de schijven zetten (vanuit QTS)

```sh
cat devices/qnap-ts41x/tools/ts41x-install-boot.sh | ssh admin@NAS 'cat > /tmp/ib.sh'
cat /root/ts41x/out/boot.uimg | ssh admin@NAS 'cat > /tmp/boot.uimg'
ssh admin@NAS 'swapoff -a; sh /tmp/ib.sh --image /tmp/boot.uimg --mode qts'          # droog
ssh admin@NAS 'swapoff -a; sh /tmp/ib.sh --image /tmp/boot.uimg --mode qts --write'  # echt
```

Noteer de LBA die het script aan het eind print (bijv. `0x1035a8`). Elke schijf krijgt
hetzelfde image op dezelfde plek, dus elke bay kan booten. Het script controleert alles terug.

## 5. Debian inschakelen (fase 2)

Gebruik `--pic-led` alleen als de analyse `uart1: yes` gaf: de statusled knippert dan
groen/rood zolang U-Boot Debian probeert.

```sh
python3 devices/qnap-ts41x/tools/ts41x-bootplan.py stage2 --env mtd4.after1.bin --lba 0x1035a8 -o stage2.txt
python3 devices/qnap-ts41x/tools/qnap-uboot-env.py set mtd4.after1.bin -s stage2.txt -o mtd4.stage2.bin
ssh admin@NAS 'cat > /dev/mtdblock4' < mtd4.stage2.bin
```

USB-stick erin, `ssh admin@NAS reboot`. Na 1–2 minuten: `ssh root@<ip>` met je sleutel.
De statusled wordt groen en de buzzer piept kort zodra Debian volledig draait.

Kwam QTS terug? Dan lukte de poging niet. Debian probeert het niet opnieuw tot je stap 5 herhaalt.

## 6. Op Debian instellen

```sh
cp /etc/ts41x/boot.conf.example /etc/ts41x/boot.conf     # MODE=qts, voor kernel-updates
mdadm --examine --scan                                    # alleen lezen: welke arrays er zijn
```

- **Data van QTS:** QTS-data zit op partitie 3 (md + vaak LVM `vg288/lv1`, ext4). Voeg alleen
  dat array toe aan `/etc/mdadm/mdadm.conf` (`AUTO -all` laat md9/md13/md256/md322 met rust),
  `apt install lvm2` staat er al, mount op `/srv/data`. Eerst read-only proberen.
- **4 schijven:** nieuwe arrays als RAID 10 of 2× RAID 1, geen RAID 5/6 (pariteit op een
  1,2 GHz ARMv5 maakt schrijven traag). De boot-area gaat automatisch naar alle schijven.
- **Mail bij problemen:** `/etc/msmtprc` (voorbeeld: `config/etc/msmtprc.example` in de repo)
  en `/etc/ts41x/alert.conf` met het adres van de eigenaar. RAID-fouten, SMART-waarschuwingen,
  fanfouten en temperatuur ≥ 65 °C gaan naar dat adres (max. 1× per 6 uur per onderwerp).
  Test: `ts41x-alert "Test" "Mail werkt"`.
- **Torrents:** `settings.json.example` → `/etc/transmission-daemon/settings.json` (gebruiker
  en wachtwoord invullen), dan `systemctl enable --now transmission-daemon`.
- **Tv:** minidlna-regels uit `/etc/minidlna.d/ts41x.conf.example`, `systemctl enable --now minidlna`.
- **Foto's van de telefoon:** WireGuard (`/etc/systemd/network/50-wg0.*.example`) + SFTP-account
  `photos` (`/etc/ssh/sshd_config.d/20-photos-sftp.conf.example`). Op Android: WG Tunnel
  (auto-tunnel uit op thuiswifi) en FolderSync (SFTP naar het LAN-adres van de NAS).
- **Firewall:** zet `LAN` in `/etc/nftables.conf` op het thuisnetwerk.

## 7. Terug naar QTS

- Eenmalig: stroom eraf/erop terwijl Debian niet opstart, of `fw_setenv bootcmd 'run bootcmd_fallback'` op Debian.
- Definitief: `ts41x-bootplan.py restore --env <dump> -o restore.txt`, toepassen zoals in stap 5,
  of het originele `mtd4.orig.bin` terugschrijven.
- **Nooit** in de QTS-webinterface schijven "initialiseren" als QTS na een terugval meldt dat
  er iets mis is: dat wist de data.

## Wat er nog niet getest is

- Of de TS-412-U-Boot de PCIe-bays met `ide` leest, en welke bay apparaat 0 is.
- Of `saveenv` bewaard blijft (stap 3 test dat veilig).
- Of de PIC-firmware zelf temperaturen stuurt; zo niet, dan regelt `ts41x-picd` de fan niet.
- `uart1`-ledcommando's in U-Boot (alleen met `--pic-led`).
