#!/usr/bin/env bash
# Install OS packages required by build_release.sh on self-hosted Linux runners.
# Does not use interactive sudo (CI has no TTY). Skips install when sudo needs a password.
set -euo pipefail

REQUIRED=(zip tar)
PACKAGES=()

for pkg in "${REQUIRED[@]}"; do
  command -v "$pkg" >/dev/null 2>&1 || PACKAGES+=("$pkg")
done

if [ ${#PACKAGES[@]} -eq 0 ]; then
  echo "[ci] zip and tar already present"
  exit 0
fi

echo "[ci] Missing: ${PACKAGES[*]}"

run_as_root() {
  if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    sudo -n "$@"
  else
    return 1
  fi
}

installed=false

if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  if run_as_root apt-get update -qq && run_as_root apt-get install -y -qq "${PACKAGES[@]}"; then
    installed=true
  fi
elif command -v dnf >/dev/null 2>&1; then
  if run_as_root dnf install -y "${PACKAGES[@]}"; then
    installed=true
  fi
elif command -v yum >/dev/null 2>&1; then
  if run_as_root yum install -y "${PACKAGES[@]}"; then
    installed=true
  fi
fi

still_missing=()
for pkg in "${PACKAGES[@]}"; do
  command -v "$pkg" >/dev/null 2>&1 || still_missing+=("$pkg")
done

if [ ${#still_missing[@]} -eq 0 ]; then
  echo "[ci] Installed: ${PACKAGES[*]}"
  exit 0
fi

if [ "$installed" = false ]; then
  echo "[ci] Warning: could not install packages (no root / passwordless sudo)." >&2
  echo "[ci] On the runner host, run once (outside CI):" >&2
  echo "       sudo apt-get update && sudo apt-get install -y ${still_missing[*]}" >&2
fi

echo "[ci] Still missing: ${still_missing[*]}" >&2
exit 1
