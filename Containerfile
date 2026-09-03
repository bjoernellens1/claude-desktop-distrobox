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
    openssh-server \
    shellcheck \
    cmake \
    iproute2 \
    net-tools \
    patch \
    vim \
    less \
    unzip \
    wget \
    jq \
    ripgrep \
    nodejs \
    npm \
    pipx \
    tmux \
    htop \
    tree \
    zip \
    dnsutils \
    sqlite3 \
    fd-find \
    rsync \
    podman \
    podman-docker \
    podman-compose \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL --retry 5 --retry-delay 2 --retry-connrefused \
        -o /usr/share/keyrings/claude-desktop-archive-keyring.asc \
        https://downloads.claude.ai/claude-desktop/key.asc \
    && echo "deb [signed-by=/usr/share/keyrings/claude-desktop-archive-keyring.asc] https://downloads.claude.ai/claude-desktop/apt/stable stable main" \
        > /etc/apt/sources.list.d/claude-desktop.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends claude-desktop \
    && rm -rf /var/lib/apt/lists/*

# Debian/Ubuntu ships fd-find's binary as `fdfind` (name clash with another
# package) — symlink it to the `fd` name most people actually expect.
RUN ln -s "$(command -v fdfind)" /usr/local/bin/fd

# CONTAINER_HOST (pointing the podman client at the host's rootless Podman
# API socket, already reachable since distrobox bind-mounts $XDG_RUNTIME_DIR
# wholesale by default) is set via distrobox.ini's additional_flags as a
# container-level `podman create --env`, not here — a Containerfile ENV/
# profile.d script would only apply to login shells, but the actual app
# launch path (`distrobox-enter -n <container> -- <command>`) and Claude
# Code's own Bash tool calls both bypass login shells entirely.

# GitHub CLI, from its own official repo (not in Ubuntu's default repos).
# The raw downloaded key isn't accepted by apt's signed-by= as-is ("unsupported
# filetype") even though it's a valid GPG key — it must go through gpg --dearmor
# to normalize it into the binary keyring format apt actually expects.
RUN curl -fsSL --retry 5 --retry-delay 2 --retry-connrefused \
        https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | gpg --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && test -s /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# Kubernetes tooling: kubectl from the official pkgs.k8s.io repo (Ubuntu
# doesn't carry it), plus Helm via its official install script.
RUN mkdir -p /etc/apt/keyrings \
    && curl -fsSL --retry 5 --retry-delay 2 --retry-connrefused \
        https://pkgs.k8s.io/core:/stable:/v1.35/deb/Release.key \
        | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.35/deb/ /" \
        > /etc/apt/sources.list.d/kubernetes.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends kubectl \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL --retry 5 --retry-delay 2 --retry-connrefused \
        https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 \
        | bash

# Electron's shell.openExternal() (used for OAuth/login popups, e.g. "Sign
# in with Google") calls xdg-open. Distrobox does not forward xdg-open to
# the host by default, and this container has no browser of its own — so
# forward to the host's real xdg-open (and thus the host's default
# browser) via distrobox-host-exec, which distrobox provides at runtime.
RUN printf '#!/bin/sh\nexec distrobox-host-exec xdg-open "$@"\n' > /usr/local/bin/xdg-open \
    && chmod +x /usr/local/bin/xdg-open
ENV BROWSER=/usr/local/bin/xdg-open

# Give Claude Code (running inside this container) context on its own
# environment: distrobox setup, host podman access, browser forwarding,
# mounted paths, available tooling, and known cosmetic quirks. This is a
# managed system-wide location, separate from $HOME (which is bind-mounted
# from the host) — it applies only to sessions launched inside this
# container, never to host-side Claude Code sessions.
RUN mkdir -p /etc/claude-code
COPY CONTAINER-CLAUDE.md /etc/claude-code/CLAUDE.md

LABEL org.opencontainers.image.source="https://github.com/bjoernellens1/claude-desktop-distrobox"
LABEL org.opencontainers.image.description="Claude Desktop, containerized for use via Distrobox on any Linux host"
LABEL org.opencontainers.image.licenses="MIT"
