#!/usr/bin/env bash
set -euo pipefail

TOOLS="${HOME}/.local/termiscope-build-tools"
SRC_WIN="/mnt/c/Users/yu/code/TermiScope"
BUILD_SRC="${HOME}/termiscope-build-src"
DEPLOY_DIR="${HOME}/termiscope-local"

echo "[termiscope] Syncing source to Linux filesystem: ${BUILD_SRC}"
rm -rf "${BUILD_SRC}"
mkdir -p "${BUILD_SRC}"
tar -C "${SRC_WIN}" \
  --exclude=node_modules \
  --exclude=.git \
  --exclude=release \
  --exclude=.build-tools \
  --exclude=mobile \
  -cf - . | tar -C "${BUILD_SRC}" -xf -

mkdir -p "${TOOLS}"
cp -f "${SRC_WIN}/.build-tools/"*.tar.gz "${TOOLS}/" 2>/dev/null || true

export TERMISCOPE_ROOT="${BUILD_SRC}"
export TERMISCOPE_TOOLS_DIR="${TOOLS}"
export TERMISCOPE_DEPLOY_DIR="${DEPLOY_DIR}"
export PATH="${TOOLS}/go/bin:${TOOLS}/node/bin:${PATH}"

cd "${BUILD_SRC}"
tr -d '\r' < "${SRC_WIN}/scripts/build_and_run_wsl.sh" > /tmp/build_and_run_wsl.sh
bash /tmp/build_and_run_wsl.sh --build-only

echo ""
echo "[termiscope] Deployed to: ${DEPLOY_DIR}"
echo "[termiscope] Start server:"
echo "  wsl bash -c 'cd ~/termiscope-local && ./TermiScope'"
