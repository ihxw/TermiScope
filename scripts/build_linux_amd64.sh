#!/usr/bin/env bash
# Build TermiScope release package for Linux amd64 (offline install bundle).
set -euo pipefail

SRC_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$SRC_ROOT"
cd "$ROOT"

SKIP_WEB_EARLY=false
for arg in "$@"; do
  [ "$arg" = "--skip-web" ] && SKIP_WEB_EARLY=true
done

# npm/go on /mnt/c (drvfs) often fail with EPERM; build on a Linux filesystem instead.
if [[ "$SRC_ROOT" == /mnt/* ]]; then
  WORK_ROOT="${TERMISCOPE_BUILD_WORK:-$HOME/termiscope-build-work}"
  if [ "$SKIP_WEB_EARLY" = true ] && [ -d "$WORK_ROOT/web/dist" ] && [ -n "$(ls -A "$WORK_ROOT/web/dist" 2>/dev/null)" ]; then
    echo "[build] Using existing work tree at ${WORK_ROOT} (keeping web/dist)"
    ROOT="$WORK_ROOT"
    cd "$ROOT"
  else
    echo "[build] Syncing sources to ${WORK_ROOT} ..."
    mkdir -p "$WORK_ROOT"
    if command -v rsync >/dev/null 2>&1; then
      rsync -a --delete \
        --exclude release/ \
        --exclude .git/ \
        --exclude web/node_modules/ \
        --exclude data/ \
        "${SRC_ROOT}/" "${WORK_ROOT}/"
    else
      rm -rf "${WORK_ROOT:?}"/*
      tar -C "$SRC_ROOT" \
        --exclude=release \
        --exclude=.git \
        --exclude=web/node_modules \
        --exclude=data \
        -cf - . | tar -C "$WORK_ROOT" -xf -
    fi
    ROOT="$WORK_ROOT"
    cd "$ROOT"
  fi
fi

TOOLS_DIR="${TERMISCOPE_TOOLS_DIR:-$HOME/.local/termiscope-build-tools}"
if [ -x "$TOOLS_DIR/go/bin/go" ]; then
  export PATH="$TOOLS_DIR/go/bin:$TOOLS_DIR/node/bin:$PATH"
fi
if [ -f "$ROOT/.build-tools/cacert.pem" ]; then
  export SSL_CERT_FILE="$ROOT/.build-tools/cacert.pem"
fi

VERSION="$(grep -m1 '"version"' web/package.json | sed -E 's/.*"version":\s*"([^"]+)".*/\1/')"
OUT_NAME="termiscope-linux-amd64-${VERSION}"
# When sources are on drvfs (/mnt/c), stage the package on ext4 first.
STAGING_ROOT="${TERMISCOPE_RELEASE_STAGING:-}"
if [[ "$SRC_ROOT" == /mnt/* ]]; then
  STAGING_ROOT="${STAGING_ROOT:-$HOME/termiscope-release}"
fi
if [ -n "$STAGING_ROOT" ]; then
  OUT_DIR="${STAGING_ROOT}/${OUT_NAME}"
  ARCHIVE="${STAGING_ROOT}/${OUT_NAME}.tar.gz"
  FINAL_ARCHIVE="${SRC_ROOT}/release/${OUT_NAME}.tar.gz"
else
  OUT_DIR="${SRC_ROOT}/release/${OUT_NAME}"
  ARCHIVE="${SRC_ROOT}/release/${OUT_NAME}.tar.gz"
  FINAL_ARCHIVE="$ARCHIVE"
fi

SKIP_WEB=false
REBUILD_WEB=false
for arg in "$@"; do
  case "$arg" in
    --skip-web) SKIP_WEB=true ;;
    --rebuild-web) REBUILD_WEB=true ;;
  esac
done

echo "[build] TermiScope ${VERSION} linux/amd64"

if ! command -v go >/dev/null 2>&1; then
  echo "Error: go not found. Install Go or set TERMISCOPE_TOOLS_DIR (see scripts/build_and_run_wsl.sh)." >&2
  exit 1
fi

NEED_WEB_BUILD=false
if [ "$REBUILD_WEB" = true ] || [ ! -d web/dist ] || [ -z "$(ls -A web/dist 2>/dev/null)" ]; then
  NEED_WEB_BUILD=true
fi

if [ "$SKIP_WEB" = true ] && [ "$NEED_WEB_BUILD" = true ]; then
  echo "Error: web/dist is missing and --skip-web was set." >&2
  exit 1
fi

if [ "$SKIP_WEB" = false ] && [ "$NEED_WEB_BUILD" = true ]; then
  if ! command -v npm >/dev/null 2>&1; then
    echo "Error: npm not found. Install Node or run scripts/build_and_run_wsl.sh once to populate TERMISCOPE_TOOLS_DIR." >&2
    exit 1
  fi
  echo "[build] Building frontend..."
  (cd web && npm install --no-audit --no-fund && npm run build)
elif [ "$SKIP_WEB" = false ]; then
  echo "[build] Using existing web/dist (--rebuild-web to force)"
fi

if [ ! -d web/dist ] || [ -z "$(ls -A web/dist 2>/dev/null)" ]; then
  echo "Error: web/dist is missing after frontend build." >&2
  exit 1
fi

echo "[build] Building backend (CGO_ENABLED=0 GOOS=linux GOARCH=amd64)..."
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"/{web,configs,data,logs,agents,scripts}

CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
  -ldflags "-s -w -X github.com/ihxw/termiscope/internal/config.Version=${VERSION}" \
  -o "${OUT_DIR}/TermiScope" ./cmd/server

mkdir -p "${OUT_DIR}/web"
cp -r web/dist "${OUT_DIR}/web/"
cp configs/config.yaml "${OUT_DIR}/configs/config.yaml.example"
for _script in install_local.sh install_from_archive.sh install_wsl.sh uninstall.sh repair_database.sh; do
  cp "${SRC_ROOT}/scripts/${_script}" "${OUT_DIR}/scripts/"
done
chmod +x "${OUT_DIR}/TermiScope" "${OUT_DIR}/scripts/"*.sh

cat > "${OUT_DIR}/INSTALL.txt" <<EOF
TermiScope ${VERSION} — Linux amd64 offline package

WSL (Windows build + install):
  powershell.exe -File scripts/build_and_install_wsl.ps1

WSL / Linux (from archive):
  sudo bash scripts/install_wsl.sh /path/to/${OUT_NAME}.tar.gz -y

Install on target server (as root):
  tar -xzf ${OUT_NAME}.tar.gz
  cd ${OUT_NAME}
  sudo ./scripts/install_local.sh

Options:
  sudo ./scripts/install_local.sh --install-dir /opt/termiscope --port 3000 -y

Database repair:
  sudo systemctl stop termiscope
  sudo ./scripts/repair_database.sh --data-dir /opt/termiscope/data
  sudo systemctl start termiscope
EOF

echo "[build] Creating archive..."
mkdir -p "$(dirname "$ARCHIVE")"
rm -f "$ARCHIVE"
tar -czf "$ARCHIVE" -C "$(dirname "$OUT_DIR")" "${OUT_NAME}"

if [ -n "${STAGING_ROOT:-}" ]; then
  mkdir -p "${SRC_ROOT}/release"
  cp -f "$ARCHIVE" "$FINAL_ARCHIVE"
  ARCHIVE="$FINAL_ARCHIVE"
fi

echo "[build] Done:"
echo "  Directory: ${OUT_DIR}"
echo "  Archive:   ${ARCHIVE}"
ls -lh "$ARCHIVE" "${OUT_DIR}/TermiScope"
