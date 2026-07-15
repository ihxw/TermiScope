#!/usr/bin/env bash
# Verify tools required by build_release.sh and release workflows.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

missing=()

check() {
  local name="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo -e "${GREEN}OK${NC}  $name — $($* 2>&1 | head -1)"
  else
    echo -e "${RED}MISSING${NC}  $name"
    missing+=("$name")
  fi
}

echo "=== Release build environment ==="

check "go" go version
check "node" node --version
check "npm" npm --version
check "tar" tar --version
check "zip" zip -v
check "git" git --version
check "bash" bash --version

# go.mod minimum version
if command -v go >/dev/null 2>&1; then
  need="$(grep -E '^go ' go.mod | awk '{print $2}')"
  have="$(go version | awk '{print $3}' | sed 's/^go//')"
  echo "      go.mod requires go ${need}, runner has go ${have}"
fi

if [ ! -f web/package-lock.json ]; then
  echo -e "${RED}MISSING${NC}  web/package-lock.json"
  missing+=("web/package-lock.json")
else
  echo -e "${GREEN}OK${NC}  web/package-lock.json"
fi

if [ ${#missing[@]} -gt 0 ]; then
  echo ""
  echo -e "${RED}Missing dependencies: ${missing[*]}${NC}" >&2
  echo "Self-hosted Linux: bash scripts/ci/install_release_deps.sh" >&2
  echo "Also ensure actions/setup-go and actions/setup-node ran before this step." >&2
  exit 1
fi

echo ""
echo "Environment ready for build_release.sh"
