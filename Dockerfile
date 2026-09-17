# ============================================================
# ViperosOS Build Container
# Debian 13 Trixie - live-build Umgebung
# ============================================================
FROM debian:trixie

LABEL maintainer="ViperosOS Project"
LABEL description="ViperosOS 1.0 ISO Build Environment"

ENV DEBIAN_FRONTEND=noninteractive
ENV LC_ALL=C.UTF-8
ENV LANG=C.UTF-8

# Build-Werkzeuge installieren
RUN apt-get update && apt-get install -y \
    live-build \
    debootstrap \
    squashfs-tools \
    zstd \
    xorriso \
    isolinux \
    syslinux-common \
    grub-efi-amd64-bin \
    grub-pc-bin \
    grub2-common \
    mtools \
    dosfstools \
    rsync \
    wget \
    curl \
    git \
    python3 \
    zenity \
    ca-certificates \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Arbeitsverzeichnis
WORKDIR /build

# Konfigurationsdateien kopieren
COPY build/lb-config/ /build/

# Build-Script
COPY scripts/build-iso.sh /build/build-iso.sh
RUN chmod +x /build/build-iso.sh

# Ausgabeverzeichnis
RUN mkdir -p /output

# Entrypoint
ENTRYPOINT ["/build/build-iso.sh"]
