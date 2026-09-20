#!/bin/bash
# Negativtests fuer scripts/check-calamares-config.py
#
# Ein Check, der nichts findet, ist schlimmer als kein Check: er erzeugt
# Vertrauen, ohne es zu verdienen. Jede Pruefung wird deshalb gegen einen
# absichtlich eingebauten Fehler getestet, und am Ende steht die Gegenprobe,
# dass die unveraenderte Konfiguration durchgeht.
#
# Dass das noetig ist, hat sich beim Schreiben sofort gezeigt: eine fruehe
# Fassung des Testskripts zerstoerte beim Einlesen die Einrueckung des
# Pruefskripts. Jeder Testfall schlug an - aber mit IndentationError, nicht
# mit dem gesuchten Fehler. Ohne die Gegenprobe haette das wie ein perfekt
# funktionierender Test ausgesehen.
#
# Arbeitet auf einer KOPIE unter dem temporaeren Verzeichnis; das
# Repository bleibt unberuehrt.
#
# Aufruf aus dem Wurzelverzeichnis:  bash scripts/check-calamares-config-tests.sh
set -u

REPO=$(cd "$(dirname "$0")/.." && pwd)
WORK="${TMPDIR:-/tmp}/viperos-calamares-tests"

rm -rf "$WORK"
mkdir -p "$WORK"
cp -a "$REPO/build"   "$WORK/"
cp -a "$REPO/scripts" "$WORK/"
cd "$WORK" || exit 1

C=build/lb-config/includes.chroot/etc/calamares
B=build/lb-config/includes.chroot/usr/share/calamares/branding/viperos/branding.desc
A=build/lb-config/auto/config
CHECK=scripts/check-calamares-config.py

# expect_fail <Beschreibung> <erwartetes Textfragment>
#
# Geprueft wird BEIDES: der Exit-Code und der Text. Nur der Exit-Code
# genuegt nicht - ein Absturz aus einem ganz anderen Grund wuerde sonst als
# "Fehler erkannt" durchgehen.
expect_fail() {
    local what=$1 needle=$2 out rc
    out=$(python3 "$CHECK" 2>&1); rc=$?
    if [ "$rc" -eq 0 ]; then
        echo "  VERPASST   $what   (Pruefung ging durch)"
        FAILED=$((FAILED + 1))
    elif printf '%s' "$out" | grep -q "$needle"; then
        echo "  ERKANNT    $what"
    else
        echo "  VERPASST   $what   (falscher Grund, erwartet: $needle)"
        printf '%s\n' "$out" | sed 's/^/      /'
        FAILED=$((FAILED + 1))
    fi
}

restore() { cp -a "$REPO/$1" "$1"; }

FAILED=0

echo
echo "=== Jeder Test baut einen echten Fehler ein ==="

# A: removeuser fehlt in der Sequenz. DAS war der Zustand vor der Reparatur:
# Debians settings.conf ruft das Modul nie auf, und das Live-Konto mit dem
# oeffentlich dokumentierten Passwort ueberlebte die Installation.
grep -v '^  - removeuser$' "$C/settings.conf" > "$C/settings.tmp" \
    && mv "$C/settings.tmp" "$C/settings.conf"
expect_fail "removeuser fehlt in der Sequenz" "removeuser"
restore "$C/settings.conf"

# B: removeuser laeuft vor users. Dann waere UID 1000 beim Anlegen des neuen
# Kontos noch belegt.
python3 - <<'PY'
import pathlib
p = pathlib.Path("build/lb-config/includes.chroot/etc/calamares/settings.conf")
t = p.read_text(encoding="utf-8").replace("  - removeuser\n", "")
t = t.replace("  - localecfg\n", "  - localecfg\n  - removeuser\n", 1)
p.write_text(t, encoding="utf-8")
PY
expect_fail "removeuser vor users" "vor 'users'"
restore "$C/settings.conf"

# C: Der Benutzername weicht von dem in auto/config ab. userdel bricht dann
# mit Code 6 ab ("specified user doesn't exist") - auch mit -f, weil die
# Existenzpruefung im Quelltext vor der Force-Behandlung steht.
sed -i 's/^username: viperos/username: live/' "$C/modules/removeuser.conf"
expect_fail "Live-Benutzer uneinheitlich" "uneinheitlich"
restore "$C/modules/removeuser.conf"

# D: Der Farbblock heisst "colors" statt "style". Auch das war real - die
# Sidebar blieb in Calamares' Standardfarbe statt im ViperOS-Blau.
sed -i 's/^style:/colors:/' "$B"
expect_fail "colors statt style im Branding" "style"
restore "$B"

# E: slideshow verweist auf eine Datei, die nicht mitgeliefert wird. Ebenfalls
# real: die alte Fassung nannte show.qml, kopierte sie aber nie.
printf 'slideshow: "show.qml"\n' >> "$B"
expect_fail "slideshow ohne Datei" "show.qml"
restore "$B"

# F: Branding-Name in settings.conf und branding.desc weichen ab.
sed -i 's/^branding: viperos/branding: gibtsnicht/' "$C/settings.conf"
expect_fail "Branding-Name weicht ab" "Branding"
restore "$C/settings.conf"

# G: auto/config setzt kein username=. Dann meldet live-config seinen
# Standardbenutzer "user" an, und motd/Hub/README nennen etwas anderes.
sed -i 's/ username=viperos//' "$A"
expect_fail "kein username= in auto/config" "username="
restore "$A"

# H: kaputtes YAML - der Fall, den ein Here-Doc im Hook gar nicht erst
# bemerkt haette.
printf '\n  bad: [unclosed\n' >> "$C/modules/welcome.conf"
expect_fail "ungueltiges YAML" "YAML"
restore "$C/modules/welcome.conf"

echo
echo "=== Gegenprobe: unveraenderte Konfiguration darf NICHT anschlagen ==="
if python3 "$CHECK" >/dev/null 2>&1; then
    echo "  BESTANDEN  saubere Konfiguration geht durch"
else
    echo "  FEHLER     saubere Konfiguration wird abgelehnt"
    python3 "$CHECK" 2>&1 | sed 's/^/    /'
    FAILED=$((FAILED + 1))
fi

echo
if [ "$FAILED" -eq 0 ]; then
    echo "Alle Negativtests erfolgreich: jede Pruefung greift."
else
    echo "$FAILED Pruefung(en) greifen nicht."
fi
exit "$FAILED"
