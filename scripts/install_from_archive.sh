#!/bin/bash
# One-shot install from a local .tar.gz package (WSL or Linux server).
# Does not overwrite existing config.yaml or database files.
#
# Usage:
#   sudo bash scripts/install_from_archive.sh /path/to/termiscope-linux-amd64-1.5.16.tar.gz
#   sudo bash scripts/install_from_archive.sh ./release/termiscope-linux-amd64-1.5.16.tar.gz --install-dir /opt/termiscope -y
set -e

ARCHIVE=""
INSTALL_ARGS=()

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
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
  echo "Error: archive path required" >&2
  echo "Example: sudo bash $0 ./release/termiscope-linux-amd64-1.5.16.tar.gz -y" >&2
  exit 1
fi

if [ ! -f "$ARCHIVE" ]; then
  echo "Error: archive not found: $ARCHIVE" >&2
  exit 1
fi

if readlink -f "$ARCHIVE" >/dev/null 2>&1; then
  ARCHIVE="$(readlink -f "$ARCHIVE")"
else
  ARCHIVE="$(cd "$(dirname "$ARCHIVE")" && pwd)/$(basename "$ARCHIVE")"
fi

EXTRACT_ROOT="${TERMISCOPE_INSTALL_TMP:-/tmp/termiscope-install-$$}"
mkdir -p "$EXTRACT_ROOT"
trap 'rm -rf "$EXTRACT_ROOT"' EXIT

echo "Extracting $ARCHIVE ..."
tar -xzf "$ARCHIVE" -C "$EXTRACT_ROOT"

PKG_DIR="$(find "$EXTRACT_ROOT" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
if [ -z "$PKG_DIR" ] || [ ! -f "$PKG_DIR/TermiScope" ]; then
  echo "Error: invalid package (missing TermiScope binary)" >&2
  exit 1
fi

INSTALL_SCRIPT="$PKG_DIR/scripts/install_local.sh"
if [ ! -f "$INSTALL_SCRIPT" ]; then
  echo "Error: install_local.sh not found in package" >&2
  exit 1
fi

chmod +x "$PKG_DIR/TermiScope" "$INSTALL_SCRIPT" 2>/dev/null || true
bash "$INSTALL_SCRIPT" "${INSTALL_ARGS[@]}"
