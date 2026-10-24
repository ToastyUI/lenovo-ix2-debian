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
ssh admin@NAS "sh /tmp/prep.sh"
```
Droge run: moet voor elke schijf `ok: /dev/sdX3 ... free` geven en eindigen met `dry run`. Dan:

```bat
ssh admin@NAS "sh /tmp/prep.sh --write" < rootfs.tar.gz
```
Duurt een paar minuten (200 MB over het netwerk, uitpakken op de NAS). Eindigt met `done.` en
`/proc/mdstat` met `md100` aan het synchroniseren. Dat synchroniseren duurt uren en mag gewoon
doorlopen, ook over een herstart heen.

## 3. Boot-image in partitie 2 (SCHRIJFT p2 van elke schijf; QTS-swap gaat even uit)

```bat
ssh admin@NAS "cat > /tmp/ib.sh" < ts41x-install-boot.sh
ssh admin@NAS "cat > /tmp/boot.uimg" < boot.uimg
ssh admin@NAS "swapoff -a; sh /tmp/ib.sh --image /tmp/boot.uimg --mode qts"
ssh admin@NAS "swapoff -a; sh /tmp/ib.sh --image /tmp/boot.uimg --mode qts --write"
```
Noteer de LBA aan het eind (verwacht `0x1035c8` op de TS-412 van de inventaris).

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
Met de sleutel uit QTS' `authorized_keys`, of tijdelijk wachtwoord `root` (alleen vanaf het LAN). Daarna direct:

```sh
rm /etc/ssh/sshd_config.d/05-temp-root-password.conf && passwd root && systemctl reload ssh
cat /proc/mdstat; df -h /; uname -r
```

Kwam QTS terug in plaats van Debian? Dan is de poging mislukt en draait QTS gewoon. Niets is
kwijt. Lever `ssh admin@NAS "cat /dev/mtdblock4" > mtd4.after2.bin` en `dmesg` aan.

## Terug naar QTS

`mtd4.orig.bin` terugschrijven (zoals in stap 1). **Nooit** in de QTS-webinterface schijven
"initialiseren": dat wist de Debian-RAID.
