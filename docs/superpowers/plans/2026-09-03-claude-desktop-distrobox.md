# Claude Desktop Distrobox Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a distrobox-based container that installs Claude Desktop (official Ubuntu apt package) and exposes it as a native-feeling GUI app on any Linux host, with GitHub Actions building and publishing the image to GHCR.

**Architecture:** A `Containerfile` (Ubuntu LTS base + Anthropic's apt repo) is built by GitHub Actions and pushed to `ghcr.io/<owner>/claude-desktop-distrobox`. A `distrobox.ini` assemble manifest declares the container (pulling the published image by default), with default mounts for `$HOME`, GUI (X11/Wayland), audio, and GPU, plus an opt-in "unsafe" profile for broader host/device access. `install.sh` is the single entry point: installs distrobox if missing, assembles the container, and exports Claude Desktop into the host's app menu.

**Tech Stack:** Ubuntu 24.04 container base, Distrobox, Podman/Docker, Bash, GitHub Actions (`docker/build-push-action`), GHCR.

**Spec:** `docs/superpowers/specs/2026-09-03-claude-desktop-distrobox-design.md`

## Global Constraints

- Container base: latest Ubuntu LTS, pinned to a specific tag (`ubuntu:24.04`), not `:latest`.
- Claude Desktop installed only via Anthropic's official apt repo (key: `https://downloads.claude.ai/claude-desktop/key.asc`, repo: `https://downloads.claude.ai/claude-desktop/apt/stable stable main`) — never a redistributed `.deb`.
- Default mounts: `$HOME`, X11 socket, Wayland/`$XDG_RUNTIME_DIR`, D-Bus, PulseAudio/PipeWire socket, `/dev/dri` for GPU.
- Unsafe mode is opt-in only (`--unsafe` flag or `CLAUDE_TOOLBOX_UNSAFE=1`), never default, and must print a warning before proceeding.
- Image published to `ghcr.io/<owner>/claude-desktop-distrobox`, tagged `latest` (on `main` push) and `vX.Y.Z` (on version tags) plus short SHA, using `GITHUB_TOKEN` with `packages: write` — no extra secrets.
- `install.sh` must be POSIX-friendly bash, pass `bash -n` syntax check (no shellcheck available in this environment — note in README that CI should add it later if desired).
- License: MIT. Repo: `claude-desktop-distrobox`, public, owner `bjoernellens1`.

---

### Task 1: Repo scaffolding (LICENSE, .gitignore, README skeleton)

**Files:**
- Create: `LICENSE`
- Create: `.gitignore`
- Create: `README.md` (skeleton only — filled in fully in Task 6)

**Interfaces:**
- Produces: nothing consumed by other tasks; pure scaffolding.

- [ ] **Step 1: Write LICENSE**

MIT license text, copyright holder `Bjoern Ellensohn`, year 2026.

```
MIT License

Copyright (c) 2026 Bjoern Ellensohn

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 2: Write .gitignore**

```
*.log
.DS_Store
*.swp
```

- [ ] **Step 3: Write README skeleton**

```markdown
# Claude Desktop Distrobox

Run [Claude Desktop](https://claude.ai/download) as a native-feeling GUI app on any Linux distro, via [Distrobox](https://distrobox.it/).

> Full documentation coming in Task 6 of the implementation plan.
```

- [ ] **Step 4: Commit**

```bash
git add LICENSE .gitignore README.md
git commit -m "chore: add license, gitignore, README skeleton"
```

---

### Task 2: Containerfile

**Files:**
- Create: `Containerfile`

**Interfaces:**
- Consumes: nothing.
- Produces: a buildable image installing `claude-desktop` on Ubuntu 24.04, consumed by Task 5 (GH Actions) and Task 3 (`distrobox.ini` local-build fallback).

- [ ] **Step 1: Write the Containerfile**

```dockerfile
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
```

- [ ] **Step 2: Attempt a local build to verify it succeeds**

Run: `podman build -t claude-desktop-distrobox:local -f Containerfile .`
Expected: build completes with exit code 0 and `claude-desktop` package installs without error. If the sandboxed environment blocks network access to `downloads.claude.ai` or `archive.ubuntu.com`, the build will fail at the `apt-get`/`curl` steps — in that case, record the exact failure in the task notes as an environment limitation (not a Containerfile bug) and proceed; the user will verify the build locally where network access is unrestricted.

- [ ] **Step 3: Commit**

```bash
git add Containerfile
git commit -m "feat: add Containerfile installing Claude Desktop on Ubuntu 24.04"
```

---

### Task 3: distrobox.ini assemble manifest (default + unsafe profiles)

**Files:**
- Create: `distrobox.ini`
- Create: `distrobox-unsafe.ini`

**Interfaces:**
- Consumes: image name `ghcr.io/bjoernellens1/claude-desktop-distrobox:latest` (produced by Task 5) as the default `image=`, with `Containerfile` (Task 2) as local-build fallback.
- Produces: assemble manifests read by `install.sh` (Task 4) via `distrobox assemble --file distrobox.ini` / `--file distrobox-unsafe.ini`.

- [ ] **Step 1: Write distrobox.ini (default/safe profile)**

```ini
[claude-desktop]
image=ghcr.io/bjoernellens1/claude-desktop-distrobox:latest
pull=true
nvidia=true
init_hooks=distrobox-export --app claude-desktop
additional_flags=--device /dev/dri --volume /run/user/${UID}/pulse:/run/user/${UID}/pulse --volume /run/user/${UID}/pipewire-0:/run/user/${UID}/pipewire-0
```

Notes captured as comments in the file itself:
- `$HOME`, the X11 socket, `$XDG_RUNTIME_DIR` (covers Wayland), and D-Bus are shared with the container by distrobox's default behavior — no explicit flags needed for those.
- `nvidia=true` is distrobox's flag to pass through NVIDIA GPU support when present; on non-NVIDIA hosts it's a no-op. `/dev/dri` covers Mesa/AMD/Intel GPU passthrough.
- Pulse/PipeWire socket paths assume the standard `$XDG_RUNTIME_DIR=/run/user/$UID` layout.

- [ ] **Step 2: Write distrobox-unsafe.ini (unsafe profile)**

```ini
[claude-desktop-unsafe]
image=ghcr.io/bjoernellens1/claude-desktop-distrobox:latest
pull=true
nvidia=true
init_hooks=distrobox-export --app claude-desktop
additional_flags=--device /dev/dri --volume /run/user/${UID}/pulse:/run/user/${UID}/pulse --volume /run/user/${UID}/pipewire-0:/run/user/${UID}/pipewire-0 --volume /mnt:/mnt --volume /media:/media --volume /run/media:/run/media --volume /:/host-root --device /dev
```

Note captured as a comment: this profile additionally mounts `/mnt`, `/media`, `/run/media`, the entire host filesystem read-write at `/host-root`, and passes through all host devices via `/dev`. This significantly reduces container isolation — only use when you specifically need the container to reach files or devices outside `$HOME`.

- [ ] **Step 3: Validate INI syntax**

Run: `python3 -c "import configparser; c = configparser.ConfigParser(); c.read('distrobox.ini'); c.read('distrobox-unsafe.ini'); print(list(c.sections()))"`
Expected: prints `['claude-desktop-unsafe']` or similar without raising — note `ConfigParser` only validates syntax, not distrobox-specific semantics, since it reads both files into one parser sequentially; run it twice separately if section-name collision is a concern (it isn't here, sections are uniquely named `claude-desktop` and `claude-desktop-unsafe`).

- [ ] **Step 4: Commit**

```bash
git add distrobox.ini distrobox-unsafe.ini
git commit -m "feat: add distrobox assemble manifests (default and unsafe profiles)"
```

---

### Task 4: install.sh

**Files:**
- Create: `install.sh`

**Interfaces:**
- Consumes: `distrobox.ini` / `distrobox-unsafe.ini` (Task 3).
- Produces: the `install.sh --unsafe` / `CLAUDE_TOOLBOX_UNSAFE=1` interface documented in README (Task 6).

- [ ] **Step 1: Write install.sh**

```bash
#!/usr/bin/env bash
set -euo pipefail

UNSAFE=0
LOCAL_BUILD=0

for arg in "$@"; do
    case "$arg" in
        --unsafe) UNSAFE=1 ;;
        --local-build) LOCAL_BUILD=1 ;;
        -h|--help)
            echo "Usage: $0 [--unsafe] [--local-build]"
            echo "  --unsafe       Mount additional host paths (/mnt, /media, /run/media, /) and all /dev devices. Reduces isolation."
            echo "  --local-build  Build the container image locally from ./Containerfile instead of pulling from GHCR."
            exit 0
            ;;
        *)
            echo "Unknown argument: $arg" >&2
            exit 1
            ;;
    esac
done

if [[ "${CLAUDE_TOOLBOX_UNSAFE:-0}" == "1" ]]; then
    UNSAFE=1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v distrobox >/dev/null 2>&1; then
    echo "distrobox not found. Attempting to install it..."
    if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update && sudo apt-get install -y distrobox
    elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y distrobox
    elif command -v pacman >/dev/null 2>&1; then
        sudo pacman -S --noconfirm distrobox
    elif command -v zypper >/dev/null 2>&1; then
        sudo zypper install -y distrobox
    else
        echo "Could not detect a supported package manager." >&2
        echo "Install distrobox manually: https://github.com/89luca89/distrobox/blob/main/docs/install.md" >&2
        exit 1
    fi
fi

if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
    echo "Detected Wayland session (WAYLAND_DISPLAY=$WAYLAND_DISPLAY)."
elif [[ -n "${DISPLAY:-}" ]]; then
    echo "Detected X11 session (DISPLAY=$DISPLAY)."
else
    echo "Warning: no WAYLAND_DISPLAY or DISPLAY detected. GUI passthrough may not work." >&2
fi

MANIFEST="$SCRIPT_DIR/distrobox.ini"
if [[ "$UNSAFE" == "1" ]]; then
    echo "UNSAFE MODE: mounting additional host paths (/mnt, /media, /run/media, /) and all devices." >&2
    echo "This significantly reduces container isolation. Press Ctrl+C within 5 seconds to abort." >&2
    sleep 5
    MANIFEST="$SCRIPT_DIR/distrobox-unsafe.ini"
fi

if [[ "$LOCAL_BUILD" == "1" ]]; then
    echo "Building image locally from Containerfile..."
    podman build -t ghcr.io/bjoernellens1/claude-desktop-distrobox:latest -f "$SCRIPT_DIR/Containerfile" "$SCRIPT_DIR"
fi

distrobox assemble create --file "$MANIFEST"

echo "Done. Claude Desktop should now appear in your application menu."
echo "You can also launch it with: distrobox-enter claude-desktop -- claude-desktop"
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x install.sh`

- [ ] **Step 3: Verify syntax**

Run: `bash -n install.sh`
Expected: no output, exit code 0.

- [ ] **Step 4: Commit**

```bash
git add install.sh
git commit -m "feat: add install.sh entry point with unsafe-mode and local-build options"
```

---

### Task 5: GitHub Actions build/push workflow

**Files:**
- Create: `.github/workflows/build.yml`

**Interfaces:**
- Consumes: `Containerfile` (Task 2).
- Produces: `ghcr.io/bjoernellens1/claude-desktop-distrobox` image referenced by `distrobox.ini`/`distrobox-unsafe.ini` (Task 3) and README (Task 6).

- [ ] **Step 1: Write the workflow**

```yaml
name: Build and push container image

on:
  push:
    branches: [main]
    paths:
      - Containerfile
      - .github/workflows/build.yml
    tags:
      - "v*"
  workflow_dispatch: {}

permissions:
  contents: read
  packages: write

jobs:
  build-push:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Log in to GHCR
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ghcr.io/${{ github.repository_owner }}/claude-desktop-distrobox
          tags: |
            type=raw,value=latest,enable={{is_default_branch}}
            type=semver,pattern={{version}}
            type=sha,format=short

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Build and push
        uses: docker/build-push-action@v6
        with:
          context: .
          file: Containerfile
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
```

- [ ] **Step 2: Validate YAML syntax**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/build.yml'))"`
Expected: no output, exit code 0.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/build.yml
git commit -m "ci: build and push container image to GHCR on push and tags"
```

---

### Task 6: Full README

**Files:**
- Modify: `README.md` (replace skeleton from Task 1)

**Interfaces:**
- Consumes: behavior/flags defined in `install.sh` (Task 4), image name from Task 5, profiles from Task 3.

- [ ] **Step 1: Write the full README**

```markdown
# Claude Desktop Distrobox

Run [Claude Desktop](https://claude.ai/download) as a native-feeling GUI app on **any Linux distro** — Fedora, Arch, openSUSE, etc. — not just Ubuntu/Debian, using [Distrobox](https://distrobox.it/).

Anthropic ships Claude Desktop for Linux only via an apt repository for Ubuntu 22.04+/Debian 12+. This project runs it inside an Ubuntu container managed by Distrobox, and exports it into your host's application menu so it looks and feels like a native app — while still using your host's GPU, audio, and home directory.

## Prerequisites

- [Podman](https://podman.io/) or [Docker](https://www.docker.com/)
- [Distrobox](https://distrobox.it/) (installed automatically by `install.sh` if missing, where possible)

## Quick start

\`\`\`bash
git clone https://github.com/bjoernellens1/claude-desktop-distrobox.git
cd claude-desktop-distrobox
./install.sh
\`\`\`

This pulls the prebuilt image from GHCR, assembles the `claude-desktop` container, and exports Claude Desktop into your application menu. Launch it from there, or run:

\`\`\`bash
distrobox-enter claude-desktop -- claude-desktop
\`\`\`

## What's shared with the container by default

- Your `$HOME` directory (distrobox default) — needed for Claude Desktop's local file features.
- The X11 socket and `$XDG_RUNTIME_DIR` (covers Wayland) — distrobox defaults.
- D-Bus — distrobox default.
- PulseAudio/PipeWire sockets — for notification sounds and any audio features.
- `/dev/dri` (and NVIDIA GPU support when present) — for hardware-accelerated rendering.

## Unsafe mode

Need the container to reach files or devices outside your home directory — other mounted drives, `/media`, or raw devices? Run:

\`\`\`bash
./install.sh --unsafe
# or
CLAUDE_TOOLBOX_UNSAFE=1 ./install.sh
\`\`\`

This additionally mounts `/mnt`, `/media`, `/run/media`, and your entire host filesystem (read-write, at `/host-root` inside the container), plus passes through all host devices. **This significantly reduces container isolation** — the script prints a warning and pauses 5 seconds before proceeding. Only use it if you specifically need that access.

## Building locally instead of pulling from GHCR

\`\`\`bash
./install.sh --local-build
\`\`\`

Builds the image from the included `Containerfile` instead of pulling `ghcr.io/bjoernellens1/claude-desktop-distrobox:latest`.

## Wayland vs X11

`install.sh` detects and prints which display server your session is using. No manual configuration is needed either way — distrobox shares the relevant sockets/env automatically. If you hit rendering issues under Wayland, Claude Desktop (an Electron app) will typically still work via XWayland.

## Troubleshooting

- **No sound**: confirm `$XDG_RUNTIME_DIR/pulse` or `$XDG_RUNTIME_DIR/pipewire-0` exists on the host before running `install.sh`.
- **No GPU acceleration**: confirm `/dev/dri` exists on the host (`ls /dev/dri`). For NVIDIA, ensure the host NVIDIA driver/container toolkit is set up per distrobox's NVIDIA docs.
- **App menu entry missing**: re-run the export manually: `distrobox-enter claude-desktop -- distrobox-export --app claude-desktop`.

## License

MIT — see [LICENSE](LICENSE).
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: write full README"
```

---

### Task 7: Create GitHub repo and push

**Files:** none (repo operations only)

**Interfaces:**
- Consumes: full repo state from Tasks 1-6.

- [ ] **Step 1: Confirm all prior commits are in place**

Run: `git log --oneline`
Expected: one commit per prior task (plus the earlier spec commit), most recent first.

- [ ] **Step 2: Create the GitHub repository**

Run: `gh repo create bjoernellens1/claude-desktop-distrobox --public --source=. --description "Run Claude Desktop as a native GUI app on any Linux host via Distrobox" --remote origin`

- [ ] **Step 3: Push**

Run: `git push -u origin main`
Expected: push succeeds; `git remote -v` shows `origin` pointing at `github.com:bjoernellens1/claude-desktop-distrobox.git`.

- [ ] **Step 4: Verify Actions workflow triggers**

Run: `gh run list --limit 5`
Expected: a `build.yml` run listed (triggered by the push to `main`, since it modifies `Containerfile`/the workflow file). If it doesn't appear immediately, note that the user can check `gh run list` again shortly — GHCR push may take a minute to complete and doesn't block this task.
