#!/usr/bin/env bash
# Build TermiScope locally and run in WSL (no sudo required).
# Usage: bash scripts/build_and_run_wsl.sh [--run-only]

set -euo pipefail

ROOT_DIR="${TERMISCOPE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
APP_NAME="TermiScope"
DEPLOY_DIR="${TERMISCOPE_DEPLOY_DIR:-$HOME/termiscope-local}"
TOOLS_DIR="${TERMISCOPE_TOOLS_DIR:-$ROOT_DIR/.build-tools}"
GO_VERSION="1.25.5"
NODE_VERSION="20.18.1"

BUILD_ONLY=false
RUN_ONLY=false
for arg in "$@"; do
  case "$arg" in
    --build-only) BUILD_ONLY=true ;;
    --run-only) RUN_ONLY=true ;;
  esac
done

log() { echo "[termiscope] $*"; }

download_file() {
  local url="$1" dest="$2"
  if [[ -f "$dest" ]] && [[ -s "$dest" ]]; then
    return
  fi
  mkdir -p "$(dirname "$dest")"
  if command -v curl >/dev/null; then
    curl -fsSL "$url" -o "$dest"
  elif command -v wget >/dev/null; then
    wget -q -O "$dest" "$url"
  else
    echo "Need curl or wget to download: $url" >&2
    echo "Or pre-download to: $dest" >&2
    exit 1
  fi
}

ensure_go() {
  local go_bin="$TOOLS_DIR/go/bin/go"
  if [[ -x "$go_bin" ]]; then
    export PATH="$TOOLS_DIR/go/bin:$PATH"
    return
  fi
  # Avoid extracting Go onto /mnt/c (drvfs utime errors break the toolchain).
  if [[ "$TOOLS_DIR" == /mnt/* ]]; then
    echo "Set TERMISCOPE_TOOLS_DIR to a Linux path (e.g. \$HOME/.local/termiscope-build-tools)." >&2
    exit 1
  fi

  log "Installing Go ${GO_VERSION} to ${TOOLS_DIR}/go ..."
  mkdir -p "$TOOLS_DIR"
  local arch="amd64"
  [[ "$(uname -m)" == "aarch64" ]] && arch="arm64"
  local tarball="go${GO_VERSION}.linux-${arch}.tar.gz"
  local archive="$TOOLS_DIR/${tarball}"
  local url="https://go.dev/dl/${tarball}"
  if [[ ! -f "$archive" ]]; then
    download_file "$url" "$archive"
  else
    log "Using cached ${archive}"
  fi
  rm -rf "$TOOLS_DIR/go"
  tar -C "$TOOLS_DIR" -xzf "$archive"
  export PATH="$TOOLS_DIR/go/bin:$PATH"
  go version
}

ensure_node() {
  local node_bin="$TOOLS_DIR/node/bin/node"
  if [[ -x "$node_bin" ]]; then
    export PATH="$TOOLS_DIR/node/bin:$PATH"
    return
  fi
  if [[ "$TOOLS_DIR" == /mnt/* ]]; then
    echo "Set TERMISCOPE_TOOLS_DIR to a Linux path (e.g. \$HOME/.local/termiscope-build-tools)." >&2
    exit 1
  fi

  log "Installing Node ${NODE_VERSION} to ${TOOLS_DIR}/node ..."
  mkdir -p "$TOOLS_DIR"
  local arch="x64"
  [[ "$(uname -m)" == "aarch64" ]] && arch="arm64"
  local tarball="node-v${NODE_VERSION}-linux-${arch}.tar.gz"
  local archive="$TOOLS_DIR/${tarball}"
  local url="https://nodejs.org/dist/v${NODE_VERSION}/${tarball}"
  if [[ ! -f "$archive" ]]; then
    download_file "$url" "$archive"
  else
    log "Using cached ${archive}"
  fi
  rm -rf "$TOOLS_DIR/node"
  mkdir -p "$TOOLS_DIR/node"
  tar -xzf "$archive" -C "$TOOLS_DIR/node" --strip-components=1
  export PATH="$TOOLS_DIR/node/bin:$PATH"
  node -v
  npm -v
}

build_release() {
  local version
  version="$(node -e "console.log(require('./web/package.json').version)")"
  log "Building version ${version} ..."

  log "1/3 Frontend (npm install + build) ..."
  (cd "$ROOT_DIR/web" && npm install --no-audit --no-fund && npm run build)

  if [[ ! -d "$ROOT_DIR/web/dist" ]]; then
    echo "Frontend build failed: web/dist not found" >&2
    exit 1
  fi

  log "2/3 Backend (linux binary) ..."
  mkdir -p "$DEPLOY_DIR"
  if [[ -f "$ROOT_DIR/.build-tools/cacert.pem" ]]; then
    export SSL_CERT_FILE="$ROOT_DIR/.build-tools/cacert.pem"
  elif [[ -f "/mnt/c/Users/yu/code/TermiScope/.build-tools/cacert.pem" ]]; then
    export SSL_CERT_FILE="/mnt/c/Users/yu/code/TermiScope/.build-tools/cacert.pem"
  fi
  CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -ldflags "-X github.com/ihxw/termiscope/internal/config.Version=${version}" \
    -o "$DEPLOY_DIR/${APP_NAME}" "$ROOT_DIR/cmd/server/main.go"

  log "3/3 Deploy layout ..."
  mkdir -p "$DEPLOY_DIR/web/dist" "$DEPLOY_DIR/configs" "$DEPLOY_DIR/data" "$DEPLOY_DIR/logs"
  rm -rf "$DEPLOY_DIR/web/dist"
  mkdir -p "$DEPLOY_DIR/web/dist"
  cp -a "$ROOT_DIR/web/dist/." "$DEPLOY_DIR/web/dist/"
  cp "$ROOT_DIR/configs/config.yaml" "$DEPLOY_DIR/configs/config.yaml"
  cp "$ROOT_DIR/LICENSE" "$DEPLOY_DIR/" 2>/dev/null || true

  log "Build complete -> ${DEPLOY_DIR}"
}

run_server() {
  log "Starting ${APP_NAME} at http://localhost:3000 (Ctrl+C to stop) ..."
  cd "$DEPLOY_DIR"
  export TERMISCOPE_CONFIG="${DEPLOY_DIR}/configs/config.yaml"
  exec "./${APP_NAME}"
}

main() {
  mkdir -p "$TOOLS_DIR" "$DEPLOY_DIR"

  if [[ "$RUN_ONLY" == false ]]; then
    ensure_go
    ensure_node
    build_release
  elif [[ ! -x "$DEPLOY_DIR/${APP_NAME}" ]]; then
    echo "Binary not found. Run without --run-only first." >&2
    exit 1
  fi

  if [[ "$BUILD_ONLY" == true ]]; then
    log "Build finished. Start with: bash scripts/build_and_run_wsl.sh --run-only"
    exit 0
  fi

  run_server
}

main "$@"
