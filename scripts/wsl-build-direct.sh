#!/bin/bash
# ============================================================
# ViperosOS - Direkter WSL-Build (läuft innerhalb von WSL)
# Ausführen: wsl -d Debian -u root -- bash /mnt/c/Users/Jason/viperos/scripts/wsl-build-direct.sh
# ============================================================

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log()     { echo -e "${BLUE}[>>]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!!]${NC} $1"; }
err()     { echo -e "${RED}[XX]${NC} $1"; exit 1; }

echo -e "${BOLD}${CYAN}"
echo "  ╔══════════════════════════════════════════════╗"
echo "  ║   ViperosOS 1.0 — Live-Build ISO Builder    ║"
echo "  ║   Ziel-Image: Debian 13 Trixie              ║"
echo "  ╚══════════════════════════════════════════════╝"
echo -e "${NC}"

# DNS nur setzen, wenn WSL keine funktionierende Auflösung liefert.
# (Vorher wurde /etc/resolv.conf bedingungslos ueberschrieben, was eine
#  funktionierende Firmen-/VPN-DNS-Konfiguration zerstoeren kann.)
if ! getent hosts deb.debian.org >/dev/null 2>&1; then
    warn "DNS-Auflösung fehlgeschlagen - setze öffentliche Resolver"
    printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > /etc/resolv.conf
fi

# Pfade
WIN_PROJECT="/mnt/c/Users/Jason/viperos"
BUILD_DIR="/build/viperos-build"
OUTPUT_WIN="${WIN_PROJECT}/output"

# Build-Verzeichnis aufsetzen
log "Erstelle Build-Verzeichnis..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Konfiguration kopieren
log "Kopiere live-build Konfiguration..."
mkdir -p auto config/package-lists config/hooks/live config/includes.chroot \
         config/includes.chroot_before_packages config/archives

cp -r "${WIN_PROJECT}/build/lb-config/auto/." "${BUILD_DIR}/auto/"
cp -r "${WIN_PROJECT}/build/lb-config/package-lists/." "${BUILD_DIR}/config/package-lists/"
cp -r "${WIN_PROJECT}/build/lb-config/hooks/." "${BUILD_DIR}/config/hooks/"
cp -r "${WIN_PROJECT}/build/lb-config/includes.chroot/." "${BUILD_DIR}/config/includes.chroot/"

# ViperOS-Paketquelle samt Schluessel. Das MUSS ueber config/archives laufen:
# live-build bindet die Quellen dort in chroot_archives ein und aktualisiert
# danach die Indizes - also noch VOR der Paketinstallation. Ein Hook kann das
# nicht leisten, weil chroot_hooks erst NACH der Installation laeuft; ohne
# archives/ scheitert der Build mit "Unable to locate package viperos-desktop".
if [ -d "${WIN_PROJECT}/build/lb-config/archives" ]; then
    cp -r "${WIN_PROJECT}/build/lb-config/archives/." \
          "${BUILD_DIR}/config/archives/"
fi

# apt-Absicherung (99viperos-retry) - muss VOR der Paketinstallation im
# Chroot liegen, sonst greifen die Retry-Einstellungen nicht.
if [ -d "${WIN_PROJECT}/build/lb-config/includes.chroot_before_packages" ]; then
    cp -r "${WIN_PROJECT}/build/lb-config/includes.chroot_before_packages/." \
          "${BUILD_DIR}/config/includes.chroot_before_packages/"
fi

# Hooks ausführbar machen
find "${BUILD_DIR}/config/hooks/" -name "*.hook.chroot" -exec chmod +x {} \;
chmod +x "${BUILD_DIR}/auto/config" "${BUILD_DIR}/auto/build" "${BUILD_DIR}/auto/clean"

success "Konfiguration bereit"

# live-build initialisieren
log "Initialisiere live-build..."
bash auto/config
success "Konfiguration angewendet"

# Live-Build starten
log "Starte lb build (20-60 Minuten je nach Netzwerkgeschwindigkeit)..."
log "Protokoll: ${BUILD_DIR}/build.log"
echo ""

START=$(date +%s)
lb build 2>&1 | tee "${BUILD_DIR}/build.log"

END=$(date +%s)
MINS=$(( (END-START)/60 ))
SECS=$(( (END-START)%60 ))

echo ""
success "Build fertig nach ${MINS}m ${SECS}s"

# ISO finden
ISO=$(find "$BUILD_DIR" -maxdepth 1 -name "*.iso" | head -1)
[ -z "$ISO" ] && err "Keine ISO gefunden! Log: ${BUILD_DIR}/build.log"

# Nach Windows kopieren
mkdir -p "$OUTPUT_WIN"
cp "$ISO" "${OUTPUT_WIN}/viperos-1.0-amd64.iso"
SIZE=$(du -h "${OUTPUT_WIN}/viperos-1.0-amd64.iso" | cut -f1)
SHA256=$(sha256sum "${OUTPUT_WIN}/viperos-1.0-amd64.iso" | cut -d' ' -f1)
printf '%s  %s\n' "$SHA256" "viperos-1.0-amd64.iso" > "${OUTPUT_WIN}/viperos-1.0-amd64.iso.sha256"

echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║          ISO ERFOLGREICH ERSTELLT!               ║${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Datei:  ${CYAN}C:\\Users\\Jason\\viperos\\output\\viperos-1.0-amd64.iso${NC}"
echo -e "  Größe:  ${CYAN}${SIZE}${NC}"
echo -e "  SHA256: ${CYAN}${SHA256}${NC}"
echo ""
echo -e "  ${YELLOW}Auf USB schreiben:${NC}  Rufus oder balenaEtcher"
echo -e "  ${YELLOW}In VM testen:${NC}       VirtualBox / QEMU"
echo ""
echo -e "  QEMU (schnell):  ${YELLOW}qemu-system-x86_64 -m 2048 -boot d -cdrom viperos-1.0-amd64.iso -vga virtio${NC}"
echo ""
