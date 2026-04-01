#!/usr/bin/env bash
set -euo pipefail

# TermiScope Release Build Script (Bash)
# usage: ./build_release.sh

ROOT_DIR=$(cd "$(dirname "$0")" && pwd)
APP_NAME="TermiScope"
WEB_DIR="$ROOT_DIR/web"
RELEASE_DIR="$ROOT_DIR/release"
BIN_DIR="$ROOT_DIR/bin"
DIST_DIR="$WEB_DIR/dist"

echo "Build Version: $(node -e "console.log(require('./web/package.json').version)")"
VERSION=$(node -e "console.log(require('./web/package.json').version)")

TARGETS=("windows:amd64:exe:zip" "linux:amd64::tar.gz" "linux:arm64::tar.gz" "linux:arm:armv7:tar.gz" "darwin:amd64::tar.gz" "darwin:arm64::tar.gz")

echo "Starting TermiScope Release Build..."

# 1. Environment Check
echo "1. Checking environment..."
command -v go >/dev/null || { echo "Go is not installed." >&2; exit 1; }
command -v npm >/dev/null || { echo "Node.js (npm) is not installed." >&2; exit 1; }
command -v tar >/dev/null || echo "Warning: tar not found. Packaging may fail for some targets."

# 2. Cleanup
echo "2. Cleaning up..."
rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"
rm -rf "$BIN_DIR"

# 3. Build Frontend
echo "3. Building Frontend..."
(cd "$WEB_DIR" && npm install --no-audit --no-fund && npm run build)
if [ ! -d "$DIST_DIR" ]; then
  echo "Frontend build failed: dist directory not found." >&2
  exit 1
fi

# 3.5 Build Agents
echo "3.5 Building Agents..."
AGENT_DIR="$ROOT_DIR/agents"
mkdir -p "$AGENT_DIR"
AGENT_VERSION="$VERSION"
AGENT_LDFLAGS="-X main.Version=$AGENT_VERSION"

echo "   Building Agent linux/amd64..."
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -ldflags "$AGENT_LDFLAGS" -o "$AGENT_DIR/termiscope-agent-linux-amd64" ./cmd/agent

echo "   Building Agent linux/arm64..."
GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -ldflags "$AGENT_LDFLAGS" -o "$AGENT_DIR/termiscope-agent-linux-arm64" ./cmd/agent

echo "   Building Agent linux/arm (v7)..."
GOOS=linux GOARCH=arm GOARM=7 CGO_ENABLED=0 go build -ldflags "$AGENT_LDFLAGS" -o "$AGENT_DIR/termiscope-agent-linux-arm" ./cmd/agent

echo "   Building Agent windows/amd64..."
GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build -ldflags "$AGENT_LDFLAGS" -o "$AGENT_DIR/termiscope-agent-windows-amd64.exe" ./cmd/agent

echo "   Building Agent darwin/amd64..."
GOOS=darwin GOARCH=amd64 CGO_ENABLED=0 go build -ldflags "$AGENT_LDFLAGS" -o "$AGENT_DIR/termiscope-agent-darwin-amd64" ./cmd/agent || echo "darwin/amd64 build may fail on this runner"

echo "   Building Agent darwin/arm64..."
GOOS=darwin GOARCH=arm64 CGO_ENABLED=0 go build -ldflags "$AGENT_LDFLAGS" -o "$AGENT_DIR/termiscope-agent-darwin-arm64" ./cmd/agent || echo "darwin/arm64 build may fail on this runner"

# Normalize line endings for install scripts
if [ -f "$ROOT_DIR/scripts/install.sh" ]; then
  sed -i '' 's/\r$//' "$ROOT_DIR/scripts/install.sh" 2>/dev/null || true
fi
if [ -f "$ROOT_DIR/scripts/uninstall.sh" ]; then
  sed -i '' 's/\r$//' "$ROOT_DIR/scripts/uninstall.sh" 2>/dev/null || true
fi

echo "4. Building Backends and Packaging..."

for TARGET in "windows:amd64:exe:zip" "linux:amd64::tar.gz" "linux:arm64::tar.gz" "linux:arm:armv7:tar.gz" "darwin:amd64::tar.gz" "darwin:arm64::tar.gz"; do
  IFS=':' read -r OS ARCH EXTRA ARCHIVE <<< "$TARGET"
  PACKAGE_NAME="$APP_NAME-$VERSION-$OS-$ARCH"
  OUTPUT_DIR="$RELEASE_DIR/$PACKAGE_NAME"
  BINARY_NAME="$APP_NAME"
  if [ "$OS" = "windows" ]; then BINARY_NAME="$APP_NAME.exe"; fi
  BINARY_PATH="$OUTPUT_DIR/$BINARY_NAME"

  echo "   Building for $OS/$ARCH..."
  mkdir -p "$OUTPUT_DIR"

  # Copy web dist
  mkdir -p "$OUTPUT_DIR/web"
  cp -r "$DIST_DIR" "$OUTPUT_DIR/web/dist"

  # Copy configs
  mkdir -p "$OUTPUT_DIR/configs"
  cp "$ROOT_DIR/configs/config.yaml" "$OUTPUT_DIR/configs/"

  # Copy agents
  mkdir -p "$OUTPUT_DIR/agents"
  cp -r "$AGENT_DIR/"* "$OUTPUT_DIR/agents/" 2>/dev/null || true

  # Copy LICENSE
  cp "$ROOT_DIR/LICENSE" "$OUTPUT_DIR/" || true

  # Copy script templates
  mkdir -p "$OUTPUT_DIR/scripts"
  if compgen -G "$ROOT_DIR/scripts/*.tmpl" > /dev/null; then
    cp "$ROOT_DIR/scripts"/*.tmpl "$OUTPUT_DIR/scripts/" || true
  fi

  # For linux, include install/uninstall scripts with LF line endings
  if [ "$OS" = "linux" ]; then
    if [ -f "$ROOT_DIR/scripts/install.sh" ]; then cp "$ROOT_DIR/scripts/install.sh" "$OUTPUT_DIR/scripts/"; fi
    if [ -f "$ROOT_DIR/scripts/uninstall.sh" ]; then cp "$ROOT_DIR/scripts/uninstall.sh" "$OUTPUT_DIR/scripts/"; fi
  fi

  # Build server binary
  echo "   Using Version: $VERSION"
  export GOOS="$OS"
  export GOARCH="$ARCH"
  export CGO_ENABLED=0
  go build -ldflags "-X github.com/ihxw/termiscope/internal/config.Version=$VERSION" -o "$BINARY_PATH" ./cmd/server/main.go

  if [ ! -f "$BINARY_PATH" ]; then
    echo "Build failed for $OS/$ARCH" >&2
    exit 1
  fi

  # Archive
  ARCHIVE_PATH="$RELEASE_DIR/$PACKAGE_NAME.$ARCHIVE"
  echo "   Packaging $PACKAGE_NAME..."
  if [ "$ARCHIVE" = "zip" ]; then
    (cd "$RELEASE_DIR" && zip -r "$PACKAGE_NAME.zip" "$PACKAGE_NAME") >/dev/null
  else
    (cd "$RELEASE_DIR" && tar -czf "$PACKAGE_NAME.tar.gz" "$PACKAGE_NAME")
  fi

  # Cleanup
  rm -rf "$OUTPUT_DIR"
  echo "   Done: $ARCHIVE_PATH"
done

echo "Release build complete. Artifacts are in $RELEASE_DIR"
