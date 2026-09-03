FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    gnupg \
    sudo \
    dbus-x11 \
    mesa-utils \
    libgl1-mesa-dri \
    pulseaudio-utils \
    pipewire \
    fonts-liberation \
    fonts-noto-color-emoji \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSLo /usr/share/keyrings/claude-desktop-archive-keyring.asc \
        https://downloads.claude.ai/claude-desktop/key.asc \
    && echo "deb [signed-by=/usr/share/keyrings/claude-desktop-archive-keyring.asc] https://downloads.claude.ai/claude-desktop/apt/stable stable main" \
        > /etc/apt/sources.list.d/claude-desktop.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends claude-desktop \
    && rm -rf /var/lib/apt/lists/*

LABEL org.opencontainers.image.source="https://github.com/bjoernellens1/claude-desktop-distrobox"
LABEL org.opencontainers.image.description="Claude Desktop, containerized for use via Distrobox on any Linux host"
LABEL org.opencontainers.image.licenses="MIT"
