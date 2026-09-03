# Claude Desktop Distrobox

Run [Claude Desktop](https://claude.ai/download) as a native-feeling GUI app on **any Linux distro** — Fedora, Arch, openSUSE, etc. — not just Ubuntu/Debian, using [Distrobox](https://distrobox.it/).

Anthropic ships Claude Desktop for Linux only via an apt repository for Ubuntu 22.04+/Debian 12+. This project runs it inside an Ubuntu container managed by Distrobox, and exports it into your host's application menu so it looks and feels like a native app — while still using your host's GPU, audio, and home directory.

## Prerequisites

- [Podman](https://podman.io/) or [Docker](https://www.docker.com/)
- [Distrobox](https://distrobox.it/) (installed automatically by `install.sh` if missing, where possible)

## Quick start

```bash
git clone https://github.com/bjoernellens1/claude-desktop-distrobox.git
cd claude-desktop-distrobox
./install.sh
```

This pulls the prebuilt image from GHCR, assembles the `claude-desktop` container, and exports Claude Desktop into your application menu. Launch it from there, or run:

```bash
distrobox-enter claude-desktop -- claude-desktop
```

## What's shared with the container by default

- Your `$HOME` directory (distrobox default) — needed for Claude Desktop's local file features.
- The X11 socket and `$XDG_RUNTIME_DIR` (covers Wayland, PulseAudio/PipeWire, and D-Bus session bus) — distrobox defaults.
- `/dev` (covers `/dev/dri`, and NVIDIA GPU support when present via `nvidia=true`) — for hardware-accelerated rendering.

## Browser login (Google sign-in, OAuth popups)

Electron apps like Claude Desktop open sign-in popups via `xdg-open`, which distrobox does **not** forward to the host by default — and this container deliberately has no browser of its own. Instead, the image ships a small `xdg-open` wrapper that forwards to your host's real `xdg-open` (and therefore your host's default browser) via `distrobox-host-exec`. You shouldn't need to do anything — Google/OAuth login popups should just open in your normal browser.

## Development tools

The image includes `git`, `build-essential`, `python3`/`pip3`, `openssh-client`, `vim`, `wget`, `unzip`, `jq`, and `ripgrep`, so you can use Claude Desktop's local dev features (e.g. Claude Code sessions, which require `git`) and do general development work inside the container without installing anything extra.

## Unsafe mode

Need the container to reach files or devices outside your home directory — other mounted drives, `/media`, or raw devices? Run:

```bash
./install.sh --unsafe
# or
CLAUDE_TOOLBOX_UNSAFE=1 ./install.sh
```

This additionally mounts `/mnt`, `/media`, `/run/media`, and your entire host filesystem (read-write, at `/host-root` inside the container), plus passes through all host devices. **This significantly reduces container isolation** — the script prints a warning and pauses 5 seconds before proceeding. Only use it if you specifically need that access.

## Building locally instead of pulling from GHCR

```bash
./install.sh --local-build
```

Builds the image from the included `Containerfile` instead of pulling `ghcr.io/bjoernellens1/claude-desktop-distrobox:latest`.

## Wayland vs X11

`install.sh` detects and prints which display server your session is using. No manual configuration is needed either way — distrobox shares the relevant sockets/env automatically. If you hit rendering issues under Wayland, Claude Desktop (an Electron app) will typically still work via XWayland.

## Troubleshooting

- **No sound**: confirm `$XDG_RUNTIME_DIR/pulse` or `$XDG_RUNTIME_DIR/pipewire-0` exists on the host before running `install.sh`.
- **No GPU acceleration**: confirm `/dev/dri` exists on the host (`ls /dev/dri`). For NVIDIA, ensure the host NVIDIA driver/container toolkit is set up per distrobox's NVIDIA docs.
- **App menu entry missing**: re-run the export manually: `distrobox-enter claude-desktop -- distrobox-export --app claude-desktop` (use `claude-desktop-unsafe` instead of `claude-desktop` if you installed with `--unsafe`).
- **Login/OAuth popup doesn't open a browser**: confirm the fix landed by running `distrobox-enter claude-desktop -- xdg-open https://example.com` — it should open a tab in your host's default browser. If not, re-pull/rebuild the image (`./install.sh` or `./install.sh --local-build`) to pick up the latest `Containerfile`.
- **Desktop feels sluggish while Claude Desktop is open**: this is normal GPU contention, not a distrobox misconfiguration — distrobox passes `/dev/dri` straight through with no extra proxy layer, so Claude Desktop's hardware-accelerated Electron renderer and your desktop compositor are simply sharing one GPU, the same as running any GPU-accelerated browser. Startup can also briefly stall (~25s) on a harmless `systemd-run` sandboxing timeout inside the container before the window appears.

## License

MIT — see [LICENSE](LICENSE).
