#!/bin/bash
# ============================================================
# ViperosOS - ISO Build Script (läuft in Docker/WSL)
# ============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log() { echo -e "${BLUE}[ViperosOS]${NC} $1"; }
success() { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }

echo -e "${BOLD}${CYAN}"
echo "  ╔═══════════════════════════════════════╗"
echo "  ║     ViperosOS 1.0 - ISO Builder       ║"
echo "  ║     Based on Debian 13 Trixie         ║"
echo "  ╚═══════════════════════════════════════╝"
echo -e "${NC}"

BUILD_DIR="/build"
OUTPUT_DIR="/output"

cd "$BUILD_DIR"

mkdir -p config
for component in hooks package-lists includes.chroot; do
    if [ -d "$component" ]; then
        rm -rf "config/$component"
        cp -a "$component" "config/$component"
    fi
done

# Vorherige Builds bereinigen
log "Bereinige vorherige Builds..."
lb clean 2>/dev/null || true

# Verzeichnisstruktur für live-build
log "Initialisiere live-build Konfiguration..."

# auto/config ausführen
if [ -f auto/config ]; then
    chmod +x auto/config
    bash auto/config
    success "live-build Konfiguration erstellt"
else
    error "auto/config nicht gefunden!"
fi

# Hooks ausführbar machen
log "Bereite Hooks vor..."
find config/hooks/ -name "*.hook.chroot" -exec chmod +x {} \; 2>/dev/null || true
find hooks/ -name "*.hook.chroot" -exec chmod +x {} \; 2>/dev/null || true

# Pakete
log "Kopiere Paketlisten..."

# ISO bauen
log "Starte ISO-Build (dauert 20-60 Minuten je nach Internet)..."
echo ""

START_TIME=$(date +%s)
lb build 2>&1 | tee /tmp/viperos-build.log

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
MINUTES=$((DURATION / 60))
SECONDS_LEFT=$((DURATION % 60))

echo ""
success "Build abgeschlossen in ${MINUTES}m ${SECONDS_LEFT}s!"

# ISO finden und kopieren
ISO_FILE=$(find "$BUILD_DIR" -name "*.iso" -newer /tmp/viperos-build.log 2>/dev/null | head -1)
if [ -z "$ISO_FILE" ]; then
    ISO_FILE=$(find "$BUILD_DIR" -name "*.iso" 2>/dev/null | head -1)
fi

if [ -n "$ISO_FILE" ]; then
    ISO_DEST="${OUTPUT_DIR}/viperos-1.0-amd64.iso"
    cp "$ISO_FILE" "$ISO_DEST"
    ISO_SIZE=$(du -h "$ISO_DEST" | cut -f1)
    echo ""
    echo -e "${GREEN}${BOLD}════════════════════════════════════════════${NC}"
    echo -e "${GREEN}${BOLD}  ISO erfolgreich erstellt!${NC}"
    echo -e "${GREEN}${BOLD}════════════════════════════════════════════${NC}"
    echo -e "  Datei:  ${CYAN}${ISO_DEST}${NC}"
    echo -e "  Größe:  ${CYAN}${ISO_SIZE}${NC}"
    sha256sum "$ISO_DEST" > "${ISO_DEST}.sha256"
    echo -e "  SHA256: $(cut -d' ' -f1 "${ISO_DEST}.sha256")"
    echo -e "${GREEN}${BOLD}════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  Testen mit QEMU:"
    echo -e "  ${YELLOW}qemu-system-x86_64 -m 2048 -boot d -cdrom viperos-1.0-amd64.iso -vga virtio${NC}"
    echo ""
else
    error "Keine ISO-Datei gefunden! Prüfe /tmp/viperos-build.log"
fi
