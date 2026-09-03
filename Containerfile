FROM ubuntu:26.04

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
    git \
    build-essential \
    python3 \
    python3-pip \
    openssh-client \
    vim \
    less \
    unzip \
    wget \
    jq \
    ripgrep \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSLo /usr/share/keyrings/claude-desktop-archive-keyring.asc \
        https://downloads.claude.ai/claude-desktop/key.asc \
    && echo "deb [signed-by=/usr/share/keyrings/claude-desktop-archive-keyring.asc] https://downloads.claude.ai/claude-desktop/apt/stable stable main" \
        > /etc/apt/sources.list.d/claude-desktop.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends claude-desktop \
    && rm -rf /var/lib/apt/lists/*

# Electron's shell.openExternal() (used for OAuth/login popups, e.g. "Sign
# in with Google") calls xdg-open. Distrobox does not forward xdg-open to
# the host by default, and this container has no browser of its own — so
# forward to the host's real xdg-open (and thus the host's default
# browser) via distrobox-host-exec, which distrobox provides at runtime.
RUN printf '#!/bin/sh\nexec distrobox-host-exec xdg-open "$@"\n' > /usr/local/bin/xdg-open \
    && chmod +x /usr/local/bin/xdg-open
ENV BROWSER=/usr/local/bin/xdg-open

LABEL org.opencontainers.image.source="https://github.com/bjoernellens1/claude-desktop-distrobox"
LABEL org.opencontainers.image.description="Claude Desktop, containerized for use via Distrobox on any Linux host"
LABEL org.opencontainers.image.licenses="MIT"
