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
for arg in "$@"; do
  case "$arg" in
    --skip-web) SKIP_WEB=true ;;
    --rebuild-web) ;; # no-op: frontend is always rebuilt unless --skip-web
  esac
done

echo "[build] TermiScope ${VERSION} linux/amd64"

if ! command -v go >/dev/null 2>&1; then
  echo "Error: go not found. Install Go or set TERMISCOPE_TOOLS_DIR (see scripts/build_and_run_wsl.sh)." >&2
  exit 1
fi

if [ "$SKIP_WEB" = true ]; then
  if [ ! -d web/dist ] || [ -z "$(ls -A web/dist 2>/dev/null)" ]; then
    echo "Error: web/dist is missing and --skip-web was set." >&2
    exit 1
  fi
  echo "[build] Skipping frontend (--skip-web)"
else
  if ! command -v npm >/dev/null 2>&1; then
    echo "Error: npm not found. Install Node or run scripts/build_and_run_wsl.sh once to populate TERMISCOPE_TOOLS_DIR." >&2
    exit 1
  fi
  echo "[build] Building frontend (always rebuild web/dist)..."
  (cd web && npm install --no-audit --no-fund && npm run build)
fi

if [ ! -d web/dist ] || [ -z "$(ls -A web/dist 2>/dev/null)" ]; then
  echo "Error: web/dist is missing after frontend build." >&2
  exit 1
fi

echo "[build] Building backend (CGO_ENABLED=0 GOOS=linux GOARCH=amd64)..."
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"/{web,configs,data,logs,agents,scripts}

echo "[build] Building bundled agents..."
AGENT_BUILD_DIR="${ROOT}/agents"
mkdir -p "$AGENT_BUILD_DIR"
AGENT_LDFLAGS="-s -w -X main.Version=${VERSION}"

CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags "$AGENT_LDFLAGS" -o "${AGENT_BUILD_DIR}/termiscope-agent-linux-amd64" ./cmd/agent
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -ldflags "$AGENT_LDFLAGS" -o "${AGENT_BUILD_DIR}/termiscope-agent-linux-arm64" ./cmd/agent
CGO_ENABLED=0 GOOS=linux GOARCH=arm GOARM=7 go build -ldflags "$AGENT_LDFLAGS" -o "${AGENT_BUILD_DIR}/termiscope-agent-linux-arm" ./cmd/agent
CGO_ENABLED=0 GOOS=windows GOARCH=amd64 go build -ldflags "$AGENT_LDFLAGS" -o "${AGENT_BUILD_DIR}/termiscope-agent-windows-amd64.exe" ./cmd/agent
CGO_ENABLED=0 GOOS=darwin GOARCH=amd64 go build -ldflags "$AGENT_LDFLAGS" -o "${AGENT_BUILD_DIR}/termiscope-agent-darwin-amd64" ./cmd/agent || echo "[build] Warning: darwin/amd64 agent build failed"
CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 go build -ldflags "$AGENT_LDFLAGS" -o "${AGENT_BUILD_DIR}/termiscope-agent-darwin-arm64" ./cmd/agent || echo "[build] Warning: darwin/arm64 agent build failed"

CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
  -ldflags "-s -w -X github.com/ihxw/termiscope/internal/config.Version=${VERSION}" \
  -o "${OUT_DIR}/TermiScope" ./cmd/server

mkdir -p "${OUT_DIR}/web"
cp -r web/dist "${OUT_DIR}/web/"
cp -r "${AGENT_BUILD_DIR}/"* "${OUT_DIR}/agents/"
cp configs/config.example.yaml "${OUT_DIR}/configs/config.yaml.example"
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
