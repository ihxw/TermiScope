#!/bin/bash
# Install TermiScope in WSL from a Windows-built linux/amd64 package.
# Preserves existing database (data/), config (configs/config.yaml), and logs/.
#
# Usage (from repo root in WSL):
#   sudo bash scripts/install_wsl.sh
#   sudo bash scripts/install_wsl.sh /mnt/c/Users/you/code/TermiScope/release/termiscope-linux-amd64-1.5.16.tar.gz
#   sudo bash scripts/install_wsl.sh --install-dir /opt/termiscope -y
#
# After building on Windows:
#   powershell -File scripts/build_and_install_wsl.ps1
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ARCHIVE=""
INSTALL_ARGS=()

usage() {
  sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
  echo ""
  echo "Options (passed to install_local.sh):"
  echo "  --install-dir PATH   Default: /opt/termiscope"
  echo "  --port PORT          HTTP port for first-time install only"
  echo "  -y, --non-interactive"
}

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --install-dir|--port|-y|--non-interactive)
      INSTALL_ARGS+=("$1")
      if [ "$1" = "--install-dir" ] || [ "$1" = "--port" ]; then
        INSTALL_ARGS+=("$2")
        shift
      fi
      shift
      ;;
    *)
      if [ -z "$ARCHIVE" ]; then
        ARCHIVE="$1"
      else
        INSTALL_ARGS+=("$1")
      fi
      shift
      ;;
  esac
done

if [ -z "$ARCHIVE" ]; then
  RELEASE_DIR="$REPO_ROOT/release"
  if [ -d "$RELEASE_DIR" ]; then
    ARCHIVE="$(ls -1t "$RELEASE_DIR"/termiscope-linux-amd64-*.tar.gz 2>/dev/null | head -n 1)"
  fi
fi

if [ -z "$ARCHIVE" ] || [ ! -f "$ARCHIVE" ]; then
  echo "Error: package archive not found." >&2
  echo "Build first: powershell -File scripts/build_and_install_wsl.ps1" >&2
  echo "Or:         bash scripts/build_linux_amd64.sh" >&2
  exit 1
fi

if ! grep -qi microsoft /proc/version 2>/dev/null; then
  echo "Note: not running inside WSL; proceeding as generic Linux install."
fi

if [ "$EUID" -ne 0 ]; then
  echo "Error: run with sudo (systemd service install)." >&2
  echo "Example: sudo bash $0 $ARCHIVE -y" >&2
  exit 1
fi

HAS_Y=false
for a in "${INSTALL_ARGS[@]}"; do
  [ "$a" = "-y" ] || [ "$a" = "--non-interactive" ] && HAS_Y=true
done
[ "$HAS_Y" = false ] && INSTALL_ARGS+=(-y)

echo "=== TermiScope WSL install ==="
echo "Archive: $ARCHIVE"
echo "Existing config/data under the install dir will not be overwritten."
echo ""

exec bash "$SCRIPT_DIR/install_from_archive.sh" "$ARCHIVE" "${INSTALL_ARGS[@]}"
