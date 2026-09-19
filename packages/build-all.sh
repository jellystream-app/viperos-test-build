#!/bin/bash
# ViperOS - alle Pakete bauen
#
# Baut jedes Unterverzeichnis mit einem debian/-Ordner zu einem .deb und legt
# die Ergebnisse in packages/out/ ab.
#
# Aufruf im Trixie-Container (so macht es auch die CI):
#   docker run --rm -v "$PWD:/src" debian:trixie \
#     bash -c 'apt-get update -qq && apt-get install -y --no-install-recommends \
#              build-essential debhelper devscripts && /src/packages/build-all.sh'
#
# Warum Trixie und nicht der Host: debhelper-compat (= 13) und die
# Abhaengigkeitsnamen muessen zur Zieldistribution passen. Ein Bau auf einem
# Ubuntu-Runner kann Pakete erzeugen, die in Trixie nicht aufloesen.

set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
OUT="$HERE/out"

rm -rf "$OUT"
mkdir -p "$OUT"

built=0
failed=0

for dir in "$HERE"/*/; do
    name=$(basename "$dir")
    [ "$name" = "out" ] && continue
    [ -d "$dir/debian" ] || continue

    echo "=============================================================="
    echo "  Baue $name"
    echo "=============================================================="

    # In einer Kopie bauen: dpkg-buildpackage legt Dateien neben dem
    # Quellverzeichnis ab und veraendert debian/. Das Repository bleibt so
    # unberuehrt, auch wenn ein Bau abbricht.
    work=$(mktemp -d)
    cp -a "$dir." "$work/"

    # Rechte normalisieren. Beide Richtungen sind wichtig:
    #
    # 1. debian/rules MUSS ausfuehrbar sein, sonst bricht der Bau mit
    #    "Permission denied" ab. Ein Checkout unter Windows kann das
    #    Executable-Bit verlieren.
    #
    # 2. Die uebrigen debian/-Dateien duerfen es NICHT sein. debhelper
    #    behandelt eine ausfuehrbare Config als Programm und FUEHRT sie aus,
    #    statt sie zu lesen ("executable config"). Bei debian/install
    #    versucht die Shell dann, jede Zeile als Befehl zu starten, und der
    #    Bau endet mit "returned exit code 127". Liegt das Quellverzeichnis
    #    auf einem Windows-Laufwerk (/mnt/c), meldet der Treiber fuer JEDE
    #    Datei 0755 - deshalb hier explizit zuruecksetzen.
    find "$work/debian" -type f ! -name 'rules' \
         ! -name 'post*' ! -name 'pre*' -exec chmod 0644 {} +
    chmod 0755 "$work/debian/rules"
    # Maintainer-Skripte muessen ausfuehrbar sein; dh nimmt sie sonst nicht auf.
    for s in postinst prerm postrm preinst; do
        [ -f "$work/debian/$s" ] && chmod 0755 "$work/debian/$s"
    done
    # Programme im Paket: hier ist das Bit erwuenscht.
    [ -f "$work/usr/bin/viperos-hub" ] && chmod 0755 "$work/usr/bin/viperos-hub"
    [ -f "$work/usr/lib/viperos/update-system" ] && \
        chmod 0755 "$work/usr/lib/viperos/update-system"

    # CR entfernen: ein Windows-Zeilenende in debian/control macht den
    # Paketnamen unlesbar, in debian/rules bricht make ab.
    find "$work/debian" -type f -exec sed -i 's/\r$//' {} +

    if ( cd "$work" && dpkg-buildpackage -b -us -uc ); then
        # Die .deb landen eine Ebene ueber dem Quellverzeichnis.
        find "$(dirname "$work")" -maxdepth 1 -name '*.deb' -exec mv {} "$OUT/" \;
        echo "  OK  $name"
        built=$((built + 1))
    else
        echo "::error::Bau von $name fehlgeschlagen"
        failed=$((failed + 1))
    fi

    rm -rf "$work"
done

echo
echo "=============================================================="
echo "  Gebaut: $built   Fehlgeschlagen: $failed"
echo "=============================================================="

if [ "$built" -gt 0 ]; then
    for deb in "$OUT"/*.deb; do
        [ -f "$deb" ] || continue
        echo
        echo "--- $(basename "$deb") ($(du -h "$deb" | cut -f1)) ---"
        dpkg-deb -I "$deb" | sed -n 's/^ /    /p' | head -12
        echo "    Dateien:"
        dpkg-deb -c "$deb" | awk '{print "      " $6}' | grep -v '/$' | head -20
    done
fi

[ "$failed" -eq 0 ] || exit 1
