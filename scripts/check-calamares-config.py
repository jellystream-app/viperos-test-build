#!/usr/bin/env python3
"""Prueft die Calamares-Konfiguration von ViperOS.

Laeuft im Preflight (.github/workflows/build-iso.yml) und laesst sich
genauso lokal aufrufen:

    python3 scripts/check-calamares-config.py

Erwartet das Wurzelverzeichnis des Repositorys als Arbeitsverzeichnis.
Endet mit 0, wenn alles stimmt, sonst mit 1 und einer ::error::-Zeile.

Warum es diese Pruefung gibt: die Installer-Konfiguration lag bis zur
Installations-Reparatur als Here-Doc in einem Shell-Hook und liess sich
deshalb nicht pruefen. Drei Fehler kamen so bis ins fertige ISO:

  - der Farbblock hiess "colors:" statt "style:" und war wirkungslos
  - "slideshow:" verwies auf eine show.qml, die nie kopiert wurde
  - "removeuser" fehlte in der Sequenz, wodurch das Live-Konto mit dem
    oeffentlich dokumentierten Passwort die Installation ueberlebte

Jede Pruefung hier wird von scripts/check-calamares-config-tests.sh gegen
einen absichtlich eingebauten Fehler getestet - ein Check, der nichts
findet, ist schlimmer als kein Check.
"""
import re
import sys
import pathlib

import yaml

root = pathlib.Path("build/lb-config/includes.chroot")
cal = root / "etc/calamares"
bad = []

# 1. Alles muss gueltiges YAML sein.
files = sorted(cal.rglob("*.conf")) + \
        sorted((root / "usr/share/calamares/branding").rglob("branding.desc"))
if not files:
    print("::error::Keine Calamares-Konfiguration gefunden.")
    sys.exit(1)

docs = {}
for f in files:
    try:
        docs[f] = yaml.safe_load(f.read_text(encoding="utf-8"))
        print(f"  OK  {f}")
    except yaml.YAMLError as e:
        bad.append(f"{f}: {e}")

if bad:
    for b in bad:
        print(f"::error::Ungueltiges YAML - {b}")
    sys.exit(1)

settings = docs.get(cal / "settings.conf")

# 2. removeuser MUSS in der exec-Phase stehen, sonst bleibt das
#    Live-Konto samt dokumentiertem Passwort auf der Platte.
exec_phase = []
for phase in settings.get("sequence", []):
    exec_phase += phase.get("exec", []) if isinstance(phase, dict) else []
if "removeuser" not in exec_phase:
    print("::error::'removeuser' fehlt in der exec-Sequenz von settings.conf.")
    print("  Das Live-Konto wuerde die Installation ueberleben.")
    sys.exit(1)

# 3. Es muss nach 'users' kommen - sonst ist UID 1000 belegt.
if exec_phase.index("removeuser") < exec_phase.index("users"):
    print("::error::'removeuser' steht vor 'users' - falsche Reihenfolge.")
    sys.exit(1)

# 4. Der Name dort muss zum Live-Benutzer aus auto/config passen.
ru = docs.get(cal / "modules/removeuser.conf", {})
user = ru.get("username")
cfg = pathlib.Path("build/lb-config/auto/config").read_text(encoding="utf-8")
m = re.search(r"username=(\S+)", cfg)
boot_user = m.group(1) if m else None
if not boot_user:
    print("::error::auto/config setzt kein username= in --bootappend-live.")
    print("  live-config meldet sonst 'user' an, nicht den ViperOS-Benutzer.")
    sys.exit(1)
if user != boot_user:
    print(f"::error::Live-Benutzer uneinheitlich: removeuser.conf '{user}',")
    print(f"  auto/config '{boot_user}'. userdel wuerde mit Code 6")
    print("  abbrechen ('specified user doesn't exist') und die")
    print("  Installation scheitern lassen.")
    sys.exit(1)
print(f"  Live-Benutzer einheitlich: {user}")

# 5. Benannte Modul-Instanzen muessen aufloesen.
#
# Eine Instanz "shellprocess@cleanup" in der Sequenz braucht einen Eintrag
# unter "instances:", und die dort genannte config-Datei muss existieren.
# Fehlt der Eintrag, kennt Calamares den Namen nicht; fehlt die Datei,
# laeuft das Modul mit leerer Konfiguration. Beides faellt sonst erst im
# gebooteten ISO auf - und beim Aufraeumschritt hiesse das: das
# installierte System behaelt ein Installer-Symbol, das ins Leere zeigt.
instances = {}
for inst in settings.get("instances", []):
    key = f"{inst.get('module')}@{inst.get('id')}"
    instances[key] = inst.get("config")

for step in exec_phase:
    if "@" not in step:
        continue
    if step not in instances:
        print(f"::error::Sequenz nennt '{step}', aber es gibt keinen "
              f"passenden Eintrag unter 'instances:'.")
        print("  Calamares wuerde den Schritt nicht finden.")
        sys.exit(1)
    conf = instances[step]
    if not conf:
        print(f"::error::Instanz '{step}' nennt keine config-Datei.")
        sys.exit(1)
    if not (cal / "modules" / conf).exists():
        print(f"::error::Instanz '{step}' verweist auf modules/{conf}, "
              f"das fehlt.")
        print("  Das Modul liefe mit leerer Konfiguration.")
        sys.exit(1)
    print(f"  Instanz OK: {step} -> modules/{conf}")

# 6. Branding: der Farbblock heisst 'style', nicht 'colors'.
brand = next((d for f, d in docs.items() if f.name == "branding.desc"), None)
if brand is not None:
    if "colors" in brand:
        print("::error::branding.desc benutzt 'colors:' - richtig ist 'style:'.")
        print("  Mit 'colors' bleibt die Sidebar in Calamares' Standardfarbe.")
        sys.exit(1)
    if settings.get("branding") != brand.get("componentName"):
        print(f"::error::settings.conf verlangt Branding "
              f"'{settings.get('branding')}', branding.desc heisst "
              f"'{brand.get('componentName')}'.")
        sys.exit(1)
    # Ein slideshow-Eintrag ohne die Datei daneben ergibt eine
    # leere Flaeche waehrend der Installation.
    show = brand.get("slideshow")
    if isinstance(show, str):
        bdir = next(f for f in docs if f.name == "branding.desc").parent
        if not (bdir / show).exists():
            print(f"::error::branding.desc verweist auf {show}, das fehlt.")
            sys.exit(1)
    print(f"  Branding OK: {brand.get('componentName')}")

print("Calamares-Konfiguration in Ordnung.")
