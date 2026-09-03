#!/usr/bin/env bash
set -euo pipefail

UNSAFE=0
LOCAL_BUILD=0

trap 'rm -f "${TMP_MANIFEST:-}"' EXIT

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
CONTAINER_NAME="claude-desktop"
if [[ "$UNSAFE" == "1" ]]; then
    echo "UNSAFE MODE: mounting additional host paths (/mnt, /media, /run/media, /) and all devices." >&2
    echo "This significantly reduces container isolation. Press Ctrl+C within 5 seconds to abort." >&2
    sleep 5
    MANIFEST="$SCRIPT_DIR/distrobox-unsafe.ini"
    CONTAINER_NAME="claude-desktop-unsafe"
fi

if [[ "$LOCAL_BUILD" == "1" ]]; then
    echo "Building image locally from Containerfile..."
    podman build -t claude-desktop-distrobox:local -f "$SCRIPT_DIR/Containerfile" "$SCRIPT_DIR"
    LOCAL_TAG="claude-desktop-distrobox:local"

    TMP_MANIFEST="$(mktemp --suffix=.ini)"
    sed -e "s|^image=.*|image=$LOCAL_TAG|" -e "s|^pull=.*|pull=false|" "$MANIFEST" > "$TMP_MANIFEST"
    MANIFEST="$TMP_MANIFEST"
fi

distrobox assemble create --file "$MANIFEST"

echo "Done. Claude Desktop should now appear in your application menu."
echo "You can also launch it with: distrobox-enter $CONTAINER_NAME -- claude-desktop"
