# RAID, ledlampjes, schijfrust en Gmail-meldingen

Deze instructies vullen de USB-installatiehandleiding aan. Ze wijzigen niet de
partities van LifeLine. Voorbeelden bevatten geen persoonlijke sleutels of adressen.

## Wat eerder is vastgesteld

De geïmporteerde ontwikkelchat van 14 oktober 2026 bevat:

- RAID 1-data-array met twee actieve leden (`[UU]`), plus een aparte systeemarray.
- Een actieve `mdmonitor`, gekoppeld aan `ix2-md-led` voor rode schijffoutleds.
- Actieve `hd-idle` met 20 minuten rusttijd en een ledservice.
- Gmail-acceptatie van mdadm-testmeldingen: `smtpstatus=250`, `exitcode=EX_OK`.

Dit is historisch bewijs op één apparaat, geen nieuwe controle van jouw NAS.
De exacte namen van arrays en schijven moet je op je eigen apparaat vaststellen.
RAID is geen onafhankelijke back-up.

## RAID en de ledservice

Controleer de bestaande arrays; maak ze niet opnieuw aan:

```bash
cat /proc/mdstat
mdadm --detail --scan
ls /sys/class/leds/
```

Installeer de twee scripts uit `config/usr-local-sbin/` als
`/usr/local/sbin/ix2-leds` en `/usr/local/sbin/ix2-md-led`, uitvoerbaar met mode 0755.
Installeer `ix2-leds.service` uit `config/etc/systemd/system/` in dezelfde map
onder `/etc/`. Controleer eerst of de lednamen overeenkomen met jouw hardware.

```bash
systemctl daemon-reload
systemctl enable --now ix2-leds.service
```

De blauwe led volgt schijfactiviteit, wit geeft systeemstatus en rood kan een
kernelpanic aangeven. Het RAID-script gebruikt `sda` voor bay 1 en `sdb` voor
bay 2. Het controleert ontbrekende of defect gemarkeerde leden in `/proc/mdstat`.
Controleer die bay-toewijzing zelf: apparaatnamen zijn geen vaste identiteit.
Dit eenvoudige script is geen volledige SMART- of per-array-gezondheidscontrole.

Voeg in de bestaande `/etc/mdadm/mdadm.conf` één passende `PROGRAM`-regel toe:

```text
PROGRAM /usr/local/sbin/ix2-md-led
MAILADDR YOUR_ALERT_ADDRESS@example.com
```

Vervang het voorbeeldmailadres. Behoud eigen ARRAY-regels en UUIDs lokaal.
Controleer bestaande PROGRAM-integraties voordat je een regel vervangt.

```bash
systemctl enable --now mdmonitor.service
systemctl restart mdmonitor.service
systemctl status mdmonitor.service
```

Sommige distributieversies starten monitoring via andere units; inspecteer
`systemctl cat mdmonitor.service` als enable niet wordt ondersteund.

## Schijven na 20 minuten laten rusten

Installeer `hd-idle`, controleer met `lsblk` welke twee apparaten de SATA-schijven
zijn en neem de voorbeeldinstelling uit `config/etc/default/hd-idle` over in
`/etc/default/hd-idle`. Bewaar eventuele eigen opties.

```bash
apt install hd-idle hdparm
systemctl enable --now hd-idle
systemctl restart hd-idle
```

De voorbeeldinstelling gebruikt 1200 seconden per schijf. Controleer na een rustige
periode met `hdparm -C /dev/sda /dev/sdb` en de servicelogs. Applicaties, monitoring,
RAID-scrubs en netwerkclients kunnen de schijven wakker houden. Vermijd erg korte
rusttijden en controleer of het aantal start/stopcycli aanvaardbaar blijft.

## Gmail als verzender voor RAID-waarschuwingen

```bash
apt install msmtp msmtp-mta ca-certificates
install -d -m 0700 -o root -g root /etc/ix2-secrets
install -m 0600 -o root -g root config/etc/msmtprc.example /etc/msmtprc
```

Voer de laatste opdracht vanuit de repository uit. Bestaat `/etc/msmtprc` al,
bewaar die eerst en pas de bestaande configuratie aan in plaats van te overschrijven.
Vervang `YOUR_ACCOUNT@gmail.com` op beide plekken door het verzendende account.

Gebruik een Gmail-appwachtwoord als jouw account en organisatiebeleid dit toestaan;
daarvoor is tweestapsverificatie nodig. Bewaar het uitsluitend op de NAS als
`/etc/ix2-secrets/gmail-app-password`, eigenaar root en mode 0600. Gebruik een
lokale editor of een verborgen invoerprompt; zet het niet in een shellcommando,
Git-commit, screenshot of chat. Zet één wachtwoordregel zonder opmaakspaties in
het bestand. Gebruik niet je gewone Google-wachtwoord.

De template gebruikt `smtp.gmail.com:587` met STARTTLS en certificaatcontrole.
Door `msmtp-mta` krijgt mdadm een sendmail-interface. Laat uitgaand DNS, correcte
tijd en TCP 587 toe. AppArmor kan de geheime bestandslocatie blokkeren; controleer
bij toegangsproblemen de lokale policy en geef alleen het benodigde leesrecht.

### Bewust een testmelding sturen

Deze opdracht verstuurt echte testmails voor de gevonden arrays; hij verwijdert
geen schijf en markeert geen schijf als defect. Voer hem zelf uit wanneer je klaar
bent om te testen:

```bash
mdadm --monitor --scan --test --oneshot
journalctl --since '-5 minutes' | grep -E 'msmtp|mdadm'
```

Controleer ook de inbox en spammap van de ontvanger. SMTP-status 250 betekent
acceptatie door de mailserver, niet gegarandeerde aflevering in de inbox.
Test ook na een herstart. Met deze repository-update is geen mail verstuurd.

## Watchdogs: verschillende functies

`mdmonitor` bewaakt RAID-events; het is geen hardwarewatchdog die een vastgelopen
NAS herstart. Een actieve hardwarewatchdog of SMART-mailconfiguratie is in het
onderzochte chatdeel niet aangetoond en wordt hier niet als aanwezig voorgesteld.

De chat bevat ook Proxmox-uplink-watchdogs voor USB/5G en netwerkroutes. Een oude
uplink-watchdog is later uitgeschakeld. Die hoort niet op de ix2 en wordt niet
meegeleverd met dit NAS-project.

## Bronnen

- [Google: SMTP-instellingen](https://support.google.com/mail/answer/7104828)
- [Google: inloggen met appwachtwoorden](https://support.google.com/accounts/answer/185833)
