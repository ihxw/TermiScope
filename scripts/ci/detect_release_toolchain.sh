#!/usr/bin/env bash
# Detect whether setup-go / setup-node / install_release_deps are needed on self-hosted runners.
# Writes setup_go, setup_node, install_os_deps (true|false) to GITHUB_OUTPUT.
set -euo pipefail

OUT="${GITHUB_OUTPUT:?GITHUB_OUTPUT must be set (run from GitHub/Gitea Actions)}"

NODE_MIN_MAJOR="${NODE_MIN_MAJOR:-20}"
SETUP_GO=true
SETUP_NODE=true
INSTALL_OS_DEPS=true

version_gte() {
  # true if $1 >= $2 (semver segments)
  [ "$(printf '%s\n%s' "$2" "$1" | sort -V | head -1)" = "$2" ]
}

# --- Go (go.mod minimum) ---
if command -v go >/dev/null 2>&1 && [ -f go.mod ]; then
  need=$(grep -E '^go ' go.mod | awk '{print $2}')
  have=$(go version | awk '{print $3}' | sed 's/^go//')
  if [ -n "$need" ] && version_gte "$have" "$need"; then
    SETUP_GO=false
    echo "[ci] Go ${have} already satisfies go.mod (>= ${need})"
  else
    echo "[ci] Go ${have} is below go.mod requirement (${need}); will run setup-go"
  fi
else
  echo "[ci] Go not found; will run setup-go"
fi

# --- Node.js + npm ---
if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
  major=$(node -p "parseInt(process.versions.node.split('.')[0], 10)")
  if [ "$major" -ge "$NODE_MIN_MAJOR" ]; then
    SETUP_NODE=false
    echo "[ci] Node $(node --version) / npm $(npm --version) already satisfy >= ${NODE_MIN_MAJOR}"
  else
    echo "[ci] Node $(node --version) is below ${NODE_MIN_MAJOR}; will run setup-node"
  fi
else
  echo "[ci] node/npm not found; will run setup-node"
fi

# --- zip / tar (Linux packaging) ---
if command -v zip >/dev/null 2>&1 && command -v tar >/dev/null 2>&1; then
  INSTALL_OS_DEPS=false
  echo "[ci] zip and tar already present"
else
  echo "[ci] missing zip/tar; will run install_release_deps.sh"
fi

{
  echo "setup_go=${SETUP_GO}"
  echo "setup_node=${SETUP_NODE}"
  echo "install_os_deps=${INSTALL_OS_DEPS}"
} >> "$OUT"
