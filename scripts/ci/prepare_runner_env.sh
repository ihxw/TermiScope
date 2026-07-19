#!/usr/bin/env bash
# Self-hosted runners often lack HOME at the listener level; setup-go runs `go env`
# before job env is visible to Node actions. Export via GITHUB_ENV and create dirs.
set -euo pipefail

export HOME="${HOME:-/root}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-/root/.cache}"
export GOCACHE="${GOCACHE:-/root/.cache/go-build}"

mkdir -p "$XDG_CACHE_HOME" "$GOCACHE"

if [ -n "${GITHUB_ENV:-}" ]; then
  {
    echo "HOME=${HOME}"
    echo "XDG_CACHE_HOME=${XDG_CACHE_HOME}"
    echo "GOCACHE=${GOCACHE}"
  } >>"$GITHUB_ENV"
fi

echo "[ci] runner env: HOME=${HOME} GOCACHE=${GOCACHE}"
