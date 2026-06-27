#!/usr/bin/env bash
set -euo pipefail

SRC_WIN="/mnt/c/Users/yu/code/TermiScope"
BUILD_SRC="${HOME}/termiscope-build-src"
DEPLOY_DIR="${HOME}/termiscope-local"

cp "${SRC_WIN}/internal/middleware/origin.go" "${BUILD_SRC}/internal/middleware/"
cp "${SRC_WIN}/internal/middleware/cors.go" "${BUILD_SRC}/internal/middleware/"
cp "${SRC_WIN}/internal/handlers/ssh_ws.go" "${BUILD_SRC}/internal/handlers/"
cp "${SRC_WIN}/internal/handlers/monitor.go" "${BUILD_SRC}/internal/handlers/"
cp "${SRC_WIN}/cmd/server/main.go" "${BUILD_SRC}/cmd/server/"
cp "${SRC_WIN}/configs/config.yaml" "${DEPLOY_DIR}/configs/config.yaml"

tr -d '\r' < "${SRC_WIN}/scripts/wsl_go_build.sh" | bash

pkill -x TermiScope 2>/dev/null || true
sleep 1
cd "${DEPLOY_DIR}"
nohup ./TermiScope >> "${HOME}/termiscope.log" 2>&1 &
sleep 2
pgrep -a TermiScope
echo "Server restarted. Open http://$(hostname -I | awk '{print $1}'):3000"
