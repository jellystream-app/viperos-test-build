# ViperOS V2 — von Build-Hooks zu Paketen mit eigenem APT-Repo

## Ziel

ViperOS wird updatebar. Heute lebt die gesamte Identität (Hub, Theme, dconf,
Branding) in 2312 Zeilen live-build-Hooks, die **nur beim ISO-Bau** laufen. Wer
V1 installiert hat, sitzt für immer auf V1 — der einzige Weg zu Neuem ist eine
Neuinstallation.

Nach V2 gilt: `apt upgrade` liefert neuen Hub, neues Theme, neue Defaults. Das
ISO ist nur noch ein Snapshot der Pakete, kein Sonderweg.

Entscheidungen (bestätigt):

| | |
|---|---|
| Repo-URL | `https://jellystream-app.github.io/viperos-apt` (GitHub Pages) |
| Umfang | alle 5 Pakete |
| Versionierung | rollend, jedes Paket eigene Version; `os-release` sagt `2.0` |

## Die fünf Pakete

Neues Verzeichnis `packages/` im Repo, ein Unterordner pro Paket mit
`debian/`-Verzeichnis (control, changelog, rules, install, compat).

| Paket | Inhalt | Quelle heute |
|---|---|---|
| `viperos-hub` | Python/GTK3-App + `.desktop` + `update-system` | Heredoc in Hook 0015 (Z. 117–824) |
| `viperos-desktop-theme` | `viperos-overrides.css`, `gnome-shell-base.css`, SVGs, 5 Wallpaper (1,9 MB), `index.theme`, GTK3/4-`gtk.css`, `viperos.xml` | includes.chroot + Hook 0020 |
| `viperos-panel-extension` | die Shell-Extension (`viperos-panel@viperos.os`) | includes.chroot |
| `viperos-settings` | dconf-Defaults, GDM-Greeter, gschema-Override, Logo-SVG/PNGs, `/etc/issue`, GRUB-Defaults, Firefox-Policies | Hooks 0025, 0030, 0060, 0065, 0070 |
| `viperos-desktop` (meta) | `Depends:` auf die vier oben + alle Desktop-Pakete aus der `.list.chroot` | Paketliste |

### Architektur-Entscheidungen

**Alle Pakete `Architecture: all`.** Es ist kein compilierter Code dabei, nur
Python, CSS, JS, Bilder. Das macht den Bau schnell (kein Cross-Compiling) und
ein `.deb` läuft auf jeder Architektur.

**Theme-Zusammensetzung wandert in `debian/rules`.** Hook 0020 hängt heute zur
Build-Zeit `viperos-overrides.css` an GNOMEs 174-KB-Basis-CSS. Das passiert
künftig beim **Paketbau**, das `.deb` enthält die fertige `gnome-shell.css`.
Grund: die Logik ist dieselbe, aber sie läuft dann einmal pro Paketversion statt
einmal pro ISO — und der CI-Check auf ≥150 KB Basis bleibt sinnvoll anwendbar.

**`os-release` bleibt Hook, wird NICHT paketiert.** `/usr/lib/os-release` gehört
`base-files`. Ein Paket, das dieselbe Datei mitbringt, erzeugt einen
dpkg-Dateikonflikt und bricht die Installation ab. `viperos-settings` schreibt
die Datei stattdessen in `postinst` — sauber, ohne Besitzanspruch.

**Hub-Fallbacks auf XFCE fliegen raus.** Der Hub ruft an 6 Stellen noch
`xfce4-terminal`, `xfce4-taskmanager`, `xfce4-settings-manager`, `xfce-polkit`
als Rückfallebene auf. Unter GNOME 48 ist keines davon installiert. Beim
Paketieren wird das auf die GNOME-Werkzeuge reduziert, die in `Depends:` stehen
— dann ist der Fallback keine Rateverkettung mehr, sondern eine Garantie.

## Das APT-Repo

Ein APT-Repo ist ein Baum statischer Dateien. GitHub Pages reicht vollständig,
kostet nichts und hat kein Traffic-Limit für öffentliche Repos.

```
viperos-apt/            (gh-pages-Branch oder eigenes Repo)
  dists/trixie/
    InRelease           GPG-clearsigned, enthält die Hashes von Packages
    main/binary-all/
      Packages, Packages.gz
  pool/main/v/viperos-hub/viperos-hub_2.0.0_all.deb
  viperos-archive-keyring.gpg
```

Erzeugt mit `apt-ftparchive` (Paket `apt-utils`) + `gpg --clearsign`.

**Signierung.** Ein GPG-Schlüsselpaar wird einmal erzeugt; der private Teil
liegt als GitHub-Secret `APT_SIGNING_KEY`, der öffentliche wandert als
`/usr/share/keyrings/viperos-archive-keyring.gpg` ins Paket
`viperos-settings`. Ohne Signatur würde `apt` bei jedem Update warnen oder
(seit Trixie) die Quelle ganz verweigern.

**Der `sources.list`-Eintrag** kommt in `viperos-settings`:

```
deb [signed-by=/usr/share/keyrings/viperos-archive-keyring.gpg]
  https://jellystream-app.github.io/viperos-apt trixie main
```

Zwei Punkte, die erledigt werden müssen:
- GitHub Pages ist auf dem Repo **noch nicht aktiviert** (`has_pages: false`) —
  einmalig in den Repo-Settings einschalten.
- `gh` CLI ist lokal nicht installiert; alle Repo-Operationen laufen daher über
  GitHub Actions, nicht von deinem Rechner. Das ist ohnehin die bessere
  Variante, weil der Signierschlüssel dann nie lokal liegt.

## Umsetzung in 6 Schritten

Jeder Schritt ist für sich testbar und ergibt einen eigenen Commit.

### 1. Paketgerüst + `viperos-hub`
- `packages/` anlegen, gemeinsames `packages/build-all.sh` (baut per
  `dpkg-buildpackage -b -us -uc` im Trixie-Container)
- Hub-Heredoc aus Hook 0015 in `packages/viperos-hub/usr/bin/viperos-hub`
  extrahieren — **als echte Datei**, damit sie lintbar und ohne ISO-Bau
  startbar ist
- XFCE-Fallbacks entfernen, `Depends: python3-gi, gir1.2-gtk-3.0,
  gnome-terminal, pciutils`
- `update-system` und das `.desktop` mit ins Paket
- **Test:** `dpkg-buildpackage` läuft durch, `dpkg -c` zeigt die erwarteten
  Pfade, `python3 -c "import ast; ast.parse(open(...).read())"` im Preflight

### 2. `viperos-desktop-theme` + `viperos-panel-extension`
- Theme-Dateien aus `includes.chroot` nach `packages/` verschieben
- `debian/rules` setzt `gnome-shell.css` aus Basis + Overrides zusammen
  (Logik aus Hook 0020 übernehmen, inkl. der Begründung im Kommentar)
- Extension mit `metadata.json`; `shell-version` bleibt `["48"]`
- **Test:** `gnome-shell.css` im gebauten `.deb` ist >180 KB; CSS-Klammern
  ausgeglichen (Check aus dem Preflight wandert mit)

### 3. `viperos-settings` + `viperos-desktop` (meta)
- dconf-Blöcke als echte Dateien statt Heredocs; `postinst` ruft
  `dconf update` und `glib-compile-schemas`
- `postinst` schreibt `os-release`, `/etc/issue`, GRUB-Distributor
- Logo-SVG als Datei; die PNG-Ableitungen erzeugt `debian/rules` per Pillow
  (Code aus Hook 0060, aber zur Paketbauzeit)
- `sources.list.d/viperos.list` + Keyring
- `viperos-desktop` als Metapaket mit allen Depends
- **Test:** `dconf compile` gegen die Dateien (bestehender Preflight-Check,
  nur ohne Heredoc-Extraktion — wird dadurch *einfacher*)

### 4. CI: Pakete bauen und Repo veröffentlichen
Neuer Workflow `.github/workflows/packages.yml`:
- Trigger: Push auf `packages/**`
- baut alle `.deb` im `debian:trixie`-Container
- `apt-ftparchive` erzeugt `Packages`/`Release`, `gpg --clearsign` → `InRelease`
- Deploy auf `gh-pages` via `actions/deploy-pages`
- **Test:** nach dem Lauf `curl .../dists/trixie/InRelease` liefert HTTP 200
  und eine gültige Signatur

### 5. ISO auf Pakete umstellen
- `viperos-desktop.list.chroot` wird kurz: `viperos-desktop` + die Basis-/
  Firmware-/Live-Boot-Pakete (die bleiben, weil live-build sie braucht)
- neuer Hook `0005-viperos-repo`: trägt Repo + Keyring ein, **bevor** Pakete
  installiert werden
- Hooks 0020, 0025, 0060, 0065, 0070 entfallen; 0015 behält nur noch VS Code,
  Jellystream, Discord (die externen Quellen)
- bleiben: 0010 (Live-User), 0018 (Security), 0030 (GDM-Autologin), 0040
  (Calamares), 0050 (NetworkManager), 0055 (Audio), 0080, 0090 — das sind
  Live-Medium- und Installer-Themen, die nicht ins installierte System gehören
- **Erwartung:** Hooks von 2312 auf ~400 Zeilen

### 6. Versionierung + Doku
- `os-release` auf `2.0` / `VERSION="2.0 (Viper)"`, ISO-Namen auf `2.0`
- Git-Tag `v2.0` (bisher gibt es **keinen einzigen Tag**)
- URLs vereinheitlichen: die toten `viperos.os` und `viperos.radionet.app`
  (beide antworten nicht) durch `radionet.app` bzw. die Pages-URL ersetzen
- README korrigieren: steht auf **XFCE**, gebaut wird GNOME Shell 48

## Risiken und wie sie abgefangen werden

| Risiko | Abfederung |
|---|---|
| Repo-Eintrag kaputt → apt bricht bei jedem Update ab | Schritt 4 vor Schritt 5; `InRelease` wird per curl im Preflight geprüft, genau wie heute die Debian-Mirrors |
| dpkg-Dateikonflikt mit `base-files` | `os-release` bewusst per `postinst`, nicht als Paketdatei |
| Paket überschreibt Nutzeranpassung | dconf-Defaults bleiben `system-db` ohne `lock` — Nutzeränderungen behalten Vorrang (wie heute) |
| GPG-Schlüssel verloren | Schlüssel wird beim Erzeugen als Backup exportiert, bevor er Secret wird; ohne ihn ist das Repo nicht mehr aktualisierbar |
| ISO-Build bricht, weil Pakete fehlen | Schritt 5 erst nach grünem Schritt 4; Preflight prüft die neue Paketliste gegen Trixie *und* das eigene Repo |

## Was das für dich ändert

Danach ist „ordentliche Updates machen" Routine: Datei in `packages/` ändern,
Changelog-Eintrag, Push. Die CI baut das `.deb`, signiert das Repo, und jedes
installierte ViperOS bekommt es beim nächsten `apt upgrade`. Kein ISO-Bau, keine
Neuinstallation, keine 40 Minuten Wartezeit.
