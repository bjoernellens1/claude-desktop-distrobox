# Claude Desktop Distrobox — Design

Date: 2026-09-03
Repo: `claude-desktop-distrobox` (public, MIT)

## Problem

Anthropic ships Claude Desktop for Linux only as an apt package for
Ubuntu 22.04+/Debian 12+. Users on other distros (Fedora, Arch, etc.)
have no supported install path. We want a toolbox-style containerized
environment — analogous to Fedora toolbox — that runs Claude Desktop
as if it were a native app on any Linux host, using Distrobox (works
with podman or docker, any host distro) instead of toolbox itself,
since toolbox is Fedora/podman-specific and distrobox generalizes the
same idea across hosts.

## Goals

- One-command setup: build a container, install Claude Desktop inside
  it via Anthropic's official apt repo, and export it as a launchable
  app on the host (desktop menu entry + `claude-desktop` on host PATH).
- GUI passthrough that works out of the box on both X11 and Wayland
  hosts, without manual `xhost`/socket wrangling.
- Audio (Pulse/PipeWire) and GPU passthrough for a smooth, native-feeling
  Electron app experience.
- Host `$HOME` mounted by default (needed for Claude Desktop's local
  file / filesystem MCP features).
- Optional "unsafe mode": broader host mounts (e.g. `/`, `/mnt`,
  `/media`) and device passthrough beyond the defaults, off by default,
  clearly flagged as reducing isolation.

## Non-goals

- Supporting non-Debian/Ubuntu base images for Claude Desktop itself
  (the app's install method requires apt).
- Packaging or redistributing Claude Desktop's `.deb` — we always pull
  it live from Anthropic's official repo at build/install time.
- Full headless CI verification of GUI rendering (not feasible without
  a real display; noted as a manual verification step).

## Components

### `Containerfile`
- Base: latest Ubuntu LTS (`ubuntu:24.04` at time of writing, but not
  hardcoded to a specific point release beyond the tag).
- Installs Anthropic's apt signing key + repo, then `claude-desktop`
  via `apt install`.
- Installs GUI/runtime deps: mesa/dri utilities, pulseaudio-utils /
  pipewire client libs, fonts, `dbus-x11`, basic X11/Wayland client
  libs Electron needs.
- Runs as a normal user matching the host UID/GID (distrobox handles
  this automatically via its entrypoint).

### `distrobox.ini`
- A distrobox assemble manifest defining the container:
  - `image` built from the local `Containerfile` (or a pinned tag once
    published, TBD by user preference later).
  - Default mounts: `$HOME` (distrobox default), X11 socket, Wayland
    socket / `$XDG_RUNTIME_DIR`, D-Bus (distrobox defaults already
    cover most of this).
  - Audio: explicit PulseAudio/PipeWire socket mount.
  - GPU: `--nvidia` equivalent flag / additional device passthrough
    for `/dev/dri`.
  - `init_hooks` to run `distrobox-export --app claude-desktop` so the
    app shows up in the host's application menu automatically after
    first assemble.

### `install.sh`
- Checks for distrobox; if missing, prints/install per host package
  manager (best-effort detection: apt/dnf/pacman/zypper) or points to
  distrobox's official install script.
- Runs `distrobox assemble` from `distrobox.ini`.
- Detects Wayland vs X11 (`$WAYLAND_DISPLAY` vs `$DISPLAY`) purely for
  informational/troubleshooting output — actual passthrough is via
  distrobox's default shared sockets, so no per-session branching is
  strictly required, but the script surfaces which mode is active.
- Runs the export step (also triggered by init_hooks, but re-runnable
  idempotently for manual re-export).
- Accepts a `--unsafe` flag (or `CLAUDE_TOOLBOX_UNSAFE=1` env var) that
  switches to `distrobox-unsafe.ini` (or applies extra `--additional-flags`
  mounts) adding broader host mounts (`/mnt`, `/media`, `/run/media`,
  and optionally `/` read-only) and `/dev` passthrough. Prints a clear
  warning before proceeding.

### `README.md`
- What this is, why distrobox instead of toolbox, prerequisites
  (podman or docker + distrobox), quick start, GPU/audio/Wayland notes,
  unsafe mode explanation and warning, troubleshooting section.

### `.github/workflows/build.yml`
- GitHub Actions workflow that builds the `Containerfile` and pushes
  the image to GitHub Container Registry (`ghcr.io/<owner>/claude-desktop-distrobox`).
- Triggers: on push to `main` affecting `Containerfile`/workflow, and
  on tag pushes (`v*`) for versioned releases; also `workflow_dispatch`
  for manual runs.
- Uses `docker/build-push-action` (or podman equivalent) with
  `GITHUB_TOKEN` (`packages: write` permission) to auth to GHCR — no
  extra secrets needed.
- Tags pushed images `latest` (on `main`) and `vX.Y.Z` (on version
  tags), plus the short commit SHA.
- `distrobox.ini` / `install.sh` updated to prefer pulling the
  published `ghcr.io` image by default, falling back to local build
  only if explicitly requested (`--local-build` flag) — avoids every
  user needing to build Ubuntu+apt-install locally.

### `.gitignore`, `LICENSE` (MIT)

## Testing / Verification

- `shellcheck` on `install.sh`.
- Attempt `podman build` of the `Containerfile` in this session to
  confirm the apt-repo + install steps succeed non-interactively.
- GUI launch itself cannot be verified headlessly here — documented in
  README as a manual step for the user to confirm on their machine.

## Open questions / decisions deferred to implementation

- Exact Ubuntu tag to pin (`ubuntu:24.04` vs `ubuntu:latest`) — will
  pin to a specific LTS tag for reproducibility.
- Whether to also publish a pre-built image later (out of scope for
  this initial version; Containerfile-based local build only).
