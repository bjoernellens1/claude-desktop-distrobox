# You are running inside claude-desktop-distrobox

This is Claude Desktop, running inside a Distrobox container (Ubuntu 26.04) defined by
[claude-desktop-distrobox](https://github.com/bjoernellens1/claude-desktop-distrobox), not
directly on the host OS. This file is baked into the container image at
`/etc/claude-code/CLAUDE.md` and loads automatically for every session here — it does not
affect Claude Code sessions run directly on the host.

## Filesystem

- `$HOME` is bind-mounted from the host — it's the exact same directory as the host user's
  home, with the same UID (distrobox uses `--userns keep-id`), so file ownership is identical
  on both sides. Files you create here are real host files.
- `/tmp`, `/dev`, and `/sys` are also bind-mounted from the host by default — device access
  (including the GPU, see below) already works without any extra configuration.
- Nothing outside `$HOME`, `/tmp`, `/dev`, `/sys` is reachable **unless** this container was
  started with `--unsafe` (or `CLAUDE_TOOLBOX_UNSAFE=1`). Check with `mountpoint -q /host-root
  && echo unsafe-mode`. In unsafe mode: `/mnt`, `/media`, `/run/media` are mounted at their
  real host paths, and the **entire host filesystem** is additionally available read-write
  under `/host-root` (e.g. the host's `/opt/foo` is `/host-root/opt/foo` here).

## Talking to the host's container runtime (Podman)

`podman`, `podman-compose`, and a `docker` compatibility wrapper (via `podman-docker`) are
installed, and `CONTAINER_HOST` is pre-set (as a container-level env var, via `podman create
--env` in `distrobox.ini` — not a login-shell script, so it applies to every process including
non-interactive Bash tool calls) to the
host's real rootless Podman API socket at `$XDG_RUNTIME_DIR/podman/podman.sock` — which is
itself already reachable because `$XDG_RUNTIME_DIR` is bind-mounted from the host by default.

**Use `podman ps`, `podman run`, `docker ...` etc. as normal remote-client commands** — they
talk to the host's already-running podman, so the actual containers run on the host, not
inside this container. This is the supported path and requires no special privileges.

**Do not try to run a local podman/docker daemon inside this container's own Bash tool.**
Claude Code's Bash tool executes inside its own nested sandbox cgroup
(`app.slice/app-com.anthropic.Claude*.scope`), which does not delegate the cgroup/user-namespace
access rootless *or* rootful local podman needs — you will hit `cannot set user namespace` or
cgroup path errors. This is not fixable from inside a session; it isn't a bug in this image,
it's Claude Code's own Bash-tool sandboxing. The `CONTAINER_HOST` remote-client approach above
sidesteps this entirely and is the only local-execution path that actually works here.

## Browser / OAuth login popups

Electron's `shell.openExternal()` (used for "Sign in with Google" and similar) calls `xdg-open`.
This container has no browser of its own — `xdg-open` is a wrapper (see
`/usr/local/bin/xdg-open`) that forwards to the **host's** real browser via
`distrobox-host-exec`. Login popups should just work; if one doesn't, test directly:
`xdg-open https://example.com` should open a tab in the host's default browser.

## GPU

AMD hardware acceleration works via the bind-mounted `/dev/dri` — verified in practice on a
Strix Halo (gfx1151) iGPU, hardware-accelerated `radeonsi`/Mesa, not falling back to software
rendering. The container's Mesa userspace version can trail the host's by a point release or
two; this is normal and doesn't affect functionality for `radeonsi` (unlike NVIDIA's
proprietary driver, which does need closer host/container version alignment).

## Dev tooling available in this image

`git`, `gh` (GitHub CLI), `kubectl`, `helm`, `podman`/`docker`/`podman-compose`, `node`/`npm`,
`python3`/`pip3`/`pipx`, `build-essential`, `cmake`, `tmux`, `shellcheck`, `ripgrep` (`rg`),
`fd` (symlinked from `fdfind`), `jq`, `sqlite3`, `rsync`, `htop`, `tree`, `openssh-client`, and
`openssh-server` (installed but **not** auto-started — this container has no init system
running sshd by default; start it manually with `sudo /usr/sbin/sshd` if you actually need
inbound SSH to the container itself).

## Known cosmetic quirks (not bugs, don't try to fix these)

- The host's **system** D-Bus socket (`/run/dbus/system_bus_socket`) is not mounted, so you'll
  see `Failed to connect to the bus` errors in Electron's logs at startup — harmless, the
  **session** bus (`$XDG_RUNTIME_DIR/bus`) is what's actually needed and does work.
- First launch can stall for up to ~25 seconds on a `systemd-run`/`StartTransientUnit` timeout
  (Chromium trying to sandbox itself via systemd, which isn't fully available here) before the
  window appears. This is cosmetic and resolves itself; it is not a crash.
