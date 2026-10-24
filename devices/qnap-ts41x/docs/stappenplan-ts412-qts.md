# Stappenplan TS-412: Debian 13 op RAID 1 (partitie 3), vanaf een Windows-pc

Voor een TS-412 met stock QTS 4.3.x en twee schijven met de QTS-indeling (p1 md9, p2 swap md4,
p3 leeg, p4 md13). Uitgevoerd vanaf een Windows-pc in hetzelfde netwerk, zonder dock, zonder Python.
Debian komt op een RAID 1 over partitie 3 van beide schijven (systeem + data, gespiegeld).
Het boot-image staat in partitie 2 van elke schijf. QTS blijft in de flash als terugval.

**Regels:** gebruik `cmd`, niet PowerShell: PowerShell 5.1 beschadigt binaire data bij `<` en `>`.
Een stap met **SCHRIJFT** pas uitvoeren na een expliciet akkoord van de eigenaar. `NAS` hieronder
= het IP van de NAS.

## 0. Bestanden

Uit de release van deze repo (de URL staat in de releasenotes):

| bestand | wat |
|---|---|
| `ts41x-prep-qts.sh` | maakt RAID 1 + ext4 op p3, pakt de rootfs uit (QTS) |
| `ts41x-install-boot.sh` | zet het boot-image in p2 van elke schijf (QTS) |
| `boot.uimg`, `rootfs.tar.gz`, `SHA256SUMS` | de build |
| `mtd4.orig.bin`, `mtd4.stage1.bin` | U-Boot-env: origineel en fase 1, per apparaat gemaakt |

```bat
certutil -hashfile boot.uimg SHA256
certutil -hashfile rootfs.tar.gz SHA256
```
Vergelijk met `SHA256SUMS`.

## 0b. Shell-check op QTS (alleen lezen)

QTS heeft busybox 1.01 (2005): geen `od`, geen `printf`, geen `readlink -f`. De scripts houden daar
rekening mee; deze check bevestigt het op de echte NAS:

```bat
ssh admin@NAS "sh -s" < ts41x-qts-probe.sh
```
Alles moet `ok` zijn. Een `FAIL`: eerst melden, niet doorgaan met stap 2/3.
Geef bij stap 2 en 3 altijd `--disks "sda sdb"` mee en laat USB-sticks eruit.

## 1. U-Boot-proef: bewaart U-Boot zijn instellingen? (SCHRIJFT de U-Boot-env)

QTS start daarna precies zoals altijd. Alleen bewaart U-Boot eenmalig `ts_probe_saveenv=ok`.

```bat
ssh admin@NAS "md5sum /dev/mtdblock4"
```
Moet gelijk zijn aan de md5 van `mtd4.orig.bin` (`certutil -hashfile mtd4.orig.bin MD5`).
Anders stoppen: dan is de env veranderd sinds de inventaris.

```bat
ssh admin@NAS "cat > /dev/mtdblock4" < mtd4.stage1.bin
ssh admin@NAS "md5sum /dev/mtdblock4"
ssh admin@NAS reboot
```
De tweede md5 moet die van `mtd4.stage1.bin` zijn. Na 2–4 minuten is QTS terug:

```bat
ssh admin@NAS "tr '\000' '\n' < /dev/mtdblock4 | grep -E '^(ts_probe_saveenv|bootcmd)='"
ssh admin@NAS "cat /dev/mtdblock4" > mtd4.after1.bin
```
- `ts_probe_saveenv=ok` en `bootcmd=run bootcmd_stock`: goed. Lever `mtd4.after1.bin` aan, daaruit
  wordt `mtd4.stage2.bin` gemaakt (stap 4).
- Nog `pending`: deze U-Boot bewaart niets. Zet het origineel terug en stop:
  `ssh admin@NAS "cat > /dev/mtdblock4" < mtd4.orig.bin`

## 2. Schijven klaarzetten (SCHRIJFT: wist partitie 3 van beide schijven)

```bat
ssh admin@NAS "cat > /tmp/prep.sh" < ts41x-prep-qts.sh
ssh admin@NAS "sh /tmp/prep.sh --disks \"sda sdb\""
```
Droge run: moet voor elke schijf `ok: /dev/sdX3 ... free` geven en eindigen met `dry run`. Dan:

```bat
ssh admin@NAS "sh /tmp/prep.sh --disks \"sda sdb\" --write" < rootfs.tar.gz
```
Duurt een paar minuten (200 MB over het netwerk, uitpakken op de NAS). Eindigt met `done.` en
`/proc/mdstat` met `md100` aan het synchroniseren. Dat synchroniseren duurt uren en mag gewoon
doorlopen, ook over een herstart heen.

## 3. Boot-image in partitie 2 (SCHRIJFT p2 van elke schijf; QTS-swap gaat uit)

`/tmp` op QTS is een RAM-disk van 32 MB: zet het image op `/mnt/HDA_ROOT` (QTS-systeemvolume,
honderden MB vrij). Het script maakt daar ook zijn opgevulde kopie.

```bat
ssh admin@NAS "rm -f /tmp/boot.uimg; mkdir -p /mnt/HDA_ROOT/ts41x"
ssh admin@NAS "cat > /tmp/ib.sh" < ts41x-install-boot.sh
ssh admin@NAS "cat > /mnt/HDA_ROOT/ts41x/boot.uimg" < boot.uimg
ssh admin@NAS "md5sum /mnt/HDA_ROOT/ts41x/boot.uimg"
ssh admin@NAS "swapoff -a && cat /proc/swaps && sh /tmp/ib.sh --image /mnt/HDA_ROOT/ts41x/boot.uimg --mode qts --disks \"sda sdb\""
ssh admin@NAS "sh /tmp/ib.sh --image /mnt/HDA_ROOT/ts41x/boot.uimg --mode qts --disks \"sda sdb\" --write"
```
De md5 moet gelijk zijn aan die van `boot.uimg` op de pc. `/proc/swaps` moet daarna leeg zijn
(alleen de kopregel); het script weigert zolang er swap actief is. Noteer de LBA aan het eind
(verwacht `0x1035c8`) en controleer `verified /dev/sda` en `verified /dev/sdb`.

**Direct daarna stap 4 en de herstart**, zonder QTS ertussen opnieuw op te starten: het image staat
in QTS' swappartitie, en een QTS die weer swap aanzet kan het overschrijven. Bij een terugval naar
QTS stap 3 dus opnieuw doen.

## 4. Debian inschakelen (SCHRIJFT de U-Boot-env)

`mtd4.stage2.bin` wordt gemaakt uit `mtd4.after1.bin` met
`ts41x-bootplan.py stage2 --env mtd4.after1.bin --lba 0x1035c8` (+ `qnap-uboot-env.py set`),
op een pc met Python.

```bat
ssh admin@NAS "md5sum /dev/mtdblock4"
```
Moet de md5 van `mtd4.after1.bin` zijn. Dan:

```bat
ssh admin@NAS "cat > /dev/mtdblock4" < mtd4.stage2.bin
ssh admin@NAS "md5sum /dev/mtdblock4"
ssh admin@NAS reboot
```

## 5. Eerste login op Debian

Na 2–3 minuten. Debian houdt het MAC-adres van QTS (en een vast QTS-adres), dus meestal hetzelfde IP.
De SSH-host-key is nieuw: verwijder de oude regel met `ssh-keygen -R NAS`.

```bat
ssh root@NAS
```
Met de sleutel uit QTS' `authorized_keys`, of tijdelijk wachtwoord `root` (alleen vanaf het LAN).

**SSH (poort 22) mag nooit dicht.** Er is geen seriële console: zonder SSH kom je er niet meer in.
Nooit `systemctl stop/restart ssh`, nooit de firewall herladen zonder `nft -c` vooraf. Het tijdelijke
wachtwoord gaat pas weg als de sleutel aantoonbaar werkt:

1. Laat de eerste sessie open staan.
2. Test in een **tweede** venster dat de sleutel werkt, zonder wachtwoord:
   ```bat
   ssh -o PasswordAuthentication=no -o BatchMode=yes root@NAS "echo SLEUTEL-OK"
   ```
   Geen `SLEUTEL-OK`? Stop hier, laat het wachtwoord staan en zet eerst de sleutel goed.
3. Pas dan, in de eerste sessie:
   ```sh
   mv /etc/ssh/sshd_config.d/05-temp-root-password.conf /root/05-temp-root-password.conf.off
   sshd -t && systemctl reload ssh      # reload: poort 22 blijft open, sessies blijven
   passwd root                          # nieuw, sterk wachtwoord (alleen nog lokaal bruikbaar)
   ```
4. Test opnieuw stap 2 in een nieuw venster. Werkt het niet: in de nog open eerste sessie
   `mv /root/05-temp-root-password.conf.off /etc/ssh/sshd_config.d/05-temp-root-password.conf && systemctl reload ssh`.

Controle:
```sh
systemctl is-active ssh; ss -ltn | grep ':22 '; systemctl show ssh -p OOMScoreAdjust -p Restart
cat /proc/mdstat; df -h /; uname -r
```
Verwacht: `active`, poort 22 luistert, `OOMScoreAdjust=-1000`, `Restart=always`.

Kwam QTS terug in plaats van Debian? Dan is de poging mislukt en draait QTS gewoon. Niets is
kwijt. Lever `ssh admin@NAS "cat /dev/mtdblock4" > mtd4.after2.bin` en `dmesg` aan.

## Terug naar QTS

`mtd4.orig.bin` terugschrijven (zoals in stap 1). **Nooit** in de QTS-webinterface schijven
"initialiseren": dat wist de Debian-RAID.
