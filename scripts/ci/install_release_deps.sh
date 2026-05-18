#!/usr/bin/env bash
# Install OS packages required by build_release.sh on self-hosted Linux runners.
# Safe to run on GitHub-hosted ubuntu-latest (no-op if already installed).
set -euo pipefail

PACKAGES=()

command -v zip >/dev/null 2>&1 || PACKAGES+=(zip)
command -v tar >/dev/null 2>&1 || PACKAGES+=(tar)
command -v jq >/dev/null 2>&1 || PACKAGES+=(jq)

if [ ${#PACKAGES[@]} -eq 0 ]; then
  echo "[ci] zip, tar, jq already present"
  exit 0
fi

echo "[ci] Installing: ${PACKAGES[*]}"

if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  if command -v sudo >/dev/null 2>&1; then
    sudo apt-get update -qq
    sudo apt-get install -y -qq "${PACKAGES[@]}"
  else
    apt-get update -qq
    apt-get install -y -qq "${PACKAGES[@]}"
  fi
elif command -v dnf >/dev/null 2>&1; then
  if command -v sudo >/dev/null 2>&1; then
    sudo dnf install -y "${PACKAGES[@]}"
  else
    dnf install -y "${PACKAGES[@]}"
  fi
elif command -v yum >/dev/null 2>&1; then
  if command -v sudo >/dev/null 2>&1; then
    sudo yum install -y "${PACKAGES[@]}"
  else
    yum install -y "${PACKAGES[@]}"
  fi
else
  echo "[ci] Warning: no supported package manager; install manually: ${PACKAGES[*]}" >&2
  exit 1
fi

echo "[ci] Done"
