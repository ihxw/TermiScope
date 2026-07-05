#!/usr/bin/env bash
set -euo pipefail

export SSL_CERT_FILE="/mnt/c/Users/yu/code/TermiScope/.build-tools/cacert.pem"
export PATH="${HOME}/.local/termiscope-build-tools/go/bin:${PATH}"

BUILD_SRC="${HOME}/termiscope-build-src"
DEPLOY_DIR="${HOME}/termiscope-local"
VERSION="$(node -e "console.log(require('${BUILD_SRC}/web/package.json').version)" 2>/dev/null || echo 1.5.13)"

cd "${BUILD_SRC}"
mkdir -p "${DEPLOY_DIR}"

echo "[termiscope] Building backend..."
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
  go build -ldflags "-X github.com/ihxw/termiscope/internal/config.Version=${VERSION}" \
  -o "${DEPLOY_DIR}/TermiScope" ./cmd/server/main.go

echo "[termiscope] Packaging deploy dir..."
rm -rf "${DEPLOY_DIR}/web/dist"
mkdir -p "${DEPLOY_DIR}/web/dist" "${DEPLOY_DIR}/configs" "${DEPLOY_DIR}/data" "${DEPLOY_DIR}/logs"
cp -a "${BUILD_SRC}/web/dist/." "${DEPLOY_DIR}/web/dist/"
cp "${BUILD_SRC}/configs/config.yaml" "${DEPLOY_DIR}/configs/config.yaml"

chmod +x "${DEPLOY_DIR}/TermiScope"
ls -la "${DEPLOY_DIR}/TermiScope"
echo "[termiscope] Done: ${DEPLOY_DIR}"
