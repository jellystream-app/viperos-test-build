# ViperOS: Installation reparieren

## Befund

Das ISO hat einen Installer (Calamares steht in der Paketliste, Hook 0040
brandet ihn, es gibt ein Desktop-Symbol). Trotzdem lässt sich ViperOS nicht
installieren. Die Ursache ist nicht ein fehlender Assistent, sondern eine
Kette von Fehlern, die jeder für sich die Installation abbricht.

Alle Angaben unten sind gegen die echten Trixie-Pakete geprüft, nicht
geschätzt: Paketindex aller vier Archivbereiche (56 MB, 1773 Pakete im
Closure), dazu die entpackten `.deb` von `calamares`, `calamares-settings-debian`,
`live-config`, `live-build` und `dosfstools`.

### 1. Der Installer bricht sofort ab — `unsquashfs` fehlt

`auto/config` setzt `--apt-recommends false`. Damit installiert der Build
**nur harte Depends**. `squashfs-tools` ist aber lediglich ein *Recommends*
von `calamares`:

    calamares  Recommends: btrfs-progs, squashfs-tools

Nachgerechnet über den gesamten Abhängigkeitsbaum (Paketliste + alle Pakete
mit Priority required/important): **niemand** zieht `squashfs-tools` hart.
Es liegt nicht im Image.

Calamares' `unpackfs` prüft das, bevor es irgendetwas tut
(`modules/unpackfs/main.py`, Zeile 482):

    if shutil.which("unsquashfs") is None:
        return (_("Bad unpackfs configuration"),
                _("Failed to find unsquashfs, make sure you have the
                   squashfs-tools package installed."))

Der Nutzer klickt sich durch Sprache, Tastatur, Partitionierung und Konto,
und **dann** bricht es mit genau dieser Meldung ab. Nichts wird geschrieben.
Das ist der Hauptgrund, warum "man es nicht richtig installieren kann".

### 2. Kein UEFI-Install möglich — `mkfs.vfat` fehlt

Dieselbe Ursache, andere Folge. Nicht im Image, weil nur Recommends/Suggests:

| Paket | Wird gebraucht für |
|---|---|
| `dosfstools` | `mkfs.vfat` — die EFI-Partition (ESP) **jeder** UEFI-Installation |
| `efibootmgr` | den UEFI-Booteintrag schreiben |
| `btrfs-progs` | Btrfs als Dateisystem anbieten |
| `ntfs-3g`, `exfatprogs`, `xfsprogs` | vorhandene Windows-/Fremdpartitionen erkennen und behalten |
| `mtools` | GRUBs EFI-Hilfsdateien |

`dosfstools` liefert `/usr/sbin/mkfs.vfat` (im `.deb` nachgesehen). Ohne das
Programm kann Calamares auf einer leeren Platte keine ESP anlegen — und damit
ist eine saubere UEFI-Installation ausgeschlossen. Das trifft praktisch jeden
Rechner ab ca. 2014.

`grub-efi-amd64` und `grub-pc` fehlen ebenfalls im Chroot. Das ist hier
**kein** Fehler: Debians Helfer `calamares-bootloader-config` installiert sie
zur Laufzeit ins Zielsystem, und live-build legt die nötigen `.deb` dafür
vorsorglich in den ISO-Pool (`installer_debian-installer`, Zeile 449-450,
Kommentar dort wörtlich: "required by Calamares"). Das funktioniert also —
solange `--debian-installer live` gesetzt bleibt, was es ist.

### 3. Der Live-Benutzer heißt anders, als überall steht

Hook 0010 legt `viperos` an. Aber die Anmeldung macht `live-config`, und
dessen Vorgabe ist `user` (`/usr/lib/live/init-config.sh`):

    LIVE_USERNAME="user"

`auto/config` setzt kein `--bootappend-live`, und es gibt keine
`/etc/live/config.conf`. Also gilt die Vorgabe. Folge:

- `0080-gdm3` schreibt `AutomaticLogin=user` — angemeldet wird als **user**
- `0030-user-setup` legt diesen Benutzer mit Passwort **live** an
- `/etc/motd`, der Hub ("Benutzer: viperos Passwort: viperos") und das README
  nennen dagegen `viperos/viperos` — **alle drei sind falsch**
- der Hook-Benutzer `viperos` existiert zwar, meldet sich aber nie an; seine
  Gruppen, sein Desktop-Symbol und seine sudo-Ausnahme laufen ins Leere

Entscheidung: Live-Benutzer heißt **viperos** (per Boot-Parameter), damit
Anmeldung und Dokumentation zusammenpassen.

### 4. Das Live-Konto überlebt die Installation

Debians `settings.conf` hat **kein** `removeuser` in der exec-Sequenz. Das
Modul existiert (`libcalamares_job_removeuser.so`, Meldung "Removing live
user from the target system"), wird aber nie aufgerufen. Ohne es bleibt auf
dem installierten System ein zweites Konto mit bekanntem Passwort stehen.

Der Dienst aus Hook 0018 (`drop-live-privileges`) löscht die sudo-Ausnahme
nur, *wenn es den Benutzer nicht mehr gibt* — er entfernt ihn aber nicht
selbst. Solange `removeuser` fehlt, greift die Sicherung also nie.

### 5. Kein Setup-Assistent nach der Installation

`gnome-initial-setup` ist in Trixie vorhanden, steht aber nicht in der
Paketliste und wird von nichts hart gezogen. Nach der Installation startet
deshalb direkt der nackte Desktop: keine Abfrage von Zeitzone, Tastatur,
Datenschutz oder Online-Konten. Das Paket bringt den Autostart selbst mit
(`gnome-initial-setup-first-login.desktop`, Bedingung
`unless-exists gnome-initial-setup-done`) — es läuft also genau einmal und
muss nicht verdrahtet werden.

### 6. Branding greift nicht

Hook 0040 kopiert nach `/usr/share/calamares/branding/viperos/` und setzt in
`settings.conf` `branding: viperos`. Debians Branding liegt aber unter
**`/etc/calamares/branding/debian/`** — nachgesehen in der Dateiliste des
Pakets. Zwei Folgen:

- `cp -a "$brand_root/debian/."` kopiert nichts (Quelle existiert nicht),
  der Hook läuft dank `[ -d ]`-Prüfung stumm weiter
- die eigene `branding.desc` nutzt den Schlüssel `colors:` — richtig heißt er
  **`style:`** (Calamares' eigene `branding/default/branding.desc`
  nachgesehen). Die Sidebar-Farben sind damit wirkungslos
- `show.qml` fehlt im ViperOS-Verzeichnis, während `slideshowAPI` nicht
  gesetzt ist

Der Installer erscheint deshalb nicht im ViperOS-Blau, sondern teils in
Debian-Optik, teils in Calamares-Standard.

### 7. Debians Paketquelle überschreibt die von ViperOS

Debians Helfer `calamares-sources-final` schreibt am Ende der Installation
`/etc/apt/sources.list` **neu** — mit reinen Debian-Quellen. Zusätzlich
entfernt `packages.conf` unter anderem `calamares-settings-debian`. Die
ViperOS-Quelle liegt in `/etc/apt/sources.list.d/viperos.sources` (eigene
Datei, bleibt also erhalten) — hier ist nichts kaputt, aber es ist der Grund,
warum diese Trennung wichtig ist und nicht angetastet werden darf.

---

## Was geändert wird

Leitlinie: so viel wie möglich über die **Paketliste** und eine **eigene
Calamares-Konfiguration** lösen, statt weitere Logik in Hooks zu schreiben.
Debians Modulkonfiguration wird nicht editiert, sondern durch eigene Dateien
in `includes.chroot/etc/calamares/` ersetzt — dort liegt bereits ein leeres
`modules/`-Verzeichnis, das nie befüllt wurde (untracked, in keinem Commit).

### A. Paketliste — die fehlenden Werkzeuge

`build/lb-config/package-lists/viperos-desktop.list.chroot`, neuer Abschnitt
mit Begründung je Paket:

    squashfs-tools     unsquashfs - ohne das bricht der Installer ab
    dosfstools         mkfs.vfat  - die EFI-Partition jeder UEFI-Installation
    efibootmgr         UEFI-Booteintrag
    mtools             GRUBs EFI-Hilfsdateien
    btrfs-progs        Btrfs als Auswahl
    ntfs-3g            Windows-Partitionen erkennen statt überschreiben
    exfatprogs         exFAT (USB-Medien)
    xfsprogs           XFS als Auswahl
    gnome-initial-setup  Ersteinrichtung beim ersten Anmelden

Dazu ein Kommentarblock, der festhält **warum** diese Zeilen nötig sind:
`--apt-recommends false` heißt, dass Recommends nicht automatisch kommen —
wer die Zeilen später "aufräumt", zerstört die Installierbarkeit.

### B. Eigene Calamares-Konfiguration

Neu unter `build/lb-config/includes.chroot/etc/calamares/`:

**`settings.conf`** — Debians Sequenz, ergänzt um:
- `removeuser` in der exec-Phase (löscht das Live-Konto im Zielsystem)
- `branding: viperos`
- Rest unverändert, inklusive Debians Helfer `sources-media`,
  `sources-final`, `bootloader-config` — die funktionieren und installieren
  GRUB aus dem ISO-Pool

**`modules/removeuser.conf`** — `username: viperos`
(Schlüsselname aus der Bibliothek verifiziert)

**`modules/welcome.conf`** — Debians Fassung, aber:
- `requiredStorage` von 15 auf 25 GB (das ViperOS-Squashfs ist deutlich
  größer als Debians; 15 GB würde bei knappen Platten mitten im Kopieren
  volllaufen)
- `requiredRam` bleibt 1.0

**`modules/packages.conf`** — Debians Entfernliste, ergänzt um
`calamares` und `calamares-settings-debian`, damit der Installer nicht auf
dem installierten System zurückbleibt.

**`modules/displaymanager.conf`** — auf `gdm` reduziert statt Debians Liste
mit sieben Kandidaten. ViperOS hat genau einen Anmeldemanager.

Branding wandert von Hook 0040 nach
`includes.chroot/usr/share/calamares/branding/viperos/`:
- `branding.desc` mit `style:` statt `colors:` und ohne `slideshow`-Eintrag,
  der ins Leere zeigt
- die beiden PNG erzeugt weiterhin der Hook (python3-pil ist im Image)

### C. Live-Benutzer vereinheitlichen

`auto/config` bekommt:

    --bootappend-live "boot=live components quiet splash username=viperos
                       hostname=viperos user-fullname=ViperOS"

Damit meldet `live-config` denselben Benutzer an, den Hook 0010 anlegt, und
motd/Hub/README stimmen wieder. Das Passwort bleibt `viperos` (Hook 0010
setzt es; `user-setup` überspringt die Anlage, weil der Benutzer schon
existiert — im Quelltext von `0030-user-setup` nachgesehen:
`if grep -q "^${LIVE_USERNAME}:" /etc/passwd then exit 0`).

### D. Preflight erweitert

In `.github/workflows/build-iso.yml`, im Schritt "Validate package list":
nach dem bestehenden `--dry-run` prüfen, dass die installationskritischen
Programme wirklich im aufgelösten Satz stehen — `squashfs-tools`,
`dosfstools`, `efibootmgr`, `gnome-initial-setup`. Das ist genau die
Prüfung, die den jetzigen Fehler in zwei Minuten gefunden hätte statt nach
40 Minuten Build und einem Installationsversuch.

Zusätzlich ein Schritt, der die neue Calamares-Konfiguration als YAML
parst (`python3 -c "import yaml"`), damit ein Tippfehler in `settings.conf`
nicht erst im gebooteten ISO auffällt.

### E. Dokumentation geradeziehen

`README.md`: Live-Zugang und Installationsablauf beschreiben, wie er dann
tatsächlich ist.

Nicht angefasst: Hook 0018 (`drop-live-privileges`) bleibt als zweite
Sicherung, falls `removeuser` einmal nicht greift.

---

## Reihenfolge

1. Paketliste ergänzen (A) — behebt allein schon den Abbruch
2. Calamares-Konfiguration anlegen (B)
3. `auto/config` + Branding-Hook anpassen (C)
4. Preflight-Prüfungen (D)
5. README (E)

## Was das nicht abdeckt

Ob die Installation auf echter Hardware durchläuft, zeigt erst ein Testlauf
in einer VM mit UEFI **und** Legacy-BIOS. Der Plan behebt die Fehler, die
sich statisch nachweisen lassen; er ersetzt diesen Test nicht.
