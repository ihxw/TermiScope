#!/usr/bin/env bash
# Self-hosted replacement for actions/setup-go: bash inherits HOME/GOCACHE reliably;
# setup-go uses Node execSync and often fails when the runner listener has no HOME.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

export HOME="${HOME:-/root}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-/root/.cache}"
export GOCACHE="${GOCACHE:-/root/.cache/go-build}"
bash "$ROOT/scripts/ci/prepare_runner_env.sh"

version_gte() {
  [ "$(printf '%s\n%s' "$2" "$1" | sort -V | head -1)" = "$2" ]
}

need=$(grep -E '^go ' go.mod | awk '{print $2}')
if [ -z "$need" ]; then
  echo "go.mod has no 'go' directive" >&2
  exit 1
fi

find_tool_root() {
  local d
  for d in \
    "${RUNNER_TOOL_CACHE:-}" \
    "${AGENT_TOOLSDIRECTORY:-}" \
    "/root/actions-runner/_work/_tool" \
    "${RUNNER_WORKSPACE:+${RUNNER_WORKSPACE%/*}/_tool}"; do
    if [ -n "$d" ] && [ -d "$d/go" ]; then
      echo "$d"
      return 0
    fi
  done
  return 1
}

install_go_toolchain() {
  local ver="$1"
  local root="$2"
  local dest="${root}/go/${ver}/x64"
  local arch os tarball url tmp

  arch="$(uname -m)"
  case "$arch" in
    x86_64) arch=amd64 ;;
    aarch64) arch=arm64 ;;
  esac
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  tarball="go${ver}.${os}-${arch}.tar.gz"
  url="https://go.dev/dl/${tarball}"

  echo "[ci] downloading Go ${ver} from ${url}"
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  curl -fsSL "$url" -o "${tmp}/${tarball}"
  mkdir -p "$(dirname "$dest")"
  rm -rf "$dest"
  tar -C "$tmp" -xzf "${tmp}/${tarball}"
  mv "${tmp}/go" "$dest"
  echo "[ci] installed Go ${ver} to ${dest}"
}

resolve_go_bin() {
  local ver="$1"
  local root="$2"
  local candidate

  if [ -n "$root" ]; then
    candidate="${root}/go/${ver}/x64/bin/go"
    if [ -x "$candidate" ]; then
      echo "$candidate"
      return 0
    fi
    for candidate in "${root}/go"/*/x64/bin/go; do
      [ -x "$candidate" ] || continue
      if version_gte "$("$candidate" version | awk '{print $3}' | sed 's/^go//')" "$ver"; then
        echo "$candidate"
        return 0
      fi
    done
  fi

  if command -v go >/dev/null 2>&1; then
    local have
    have="$(go version | awk '{print $3}' | sed 's/^go//')"
    if version_gte "$have" "$ver"; then
      command -v go
      return 0
    fi
  fi
  return 1
}

tool_root=""
tool_root="$(find_tool_root)" || true

go_bin=""
if ! go_bin="$(resolve_go_bin "$need" "$tool_root")"; then
  tool_root="${tool_root:-/root/actions-runner/_work/_tool}"
  mkdir -p "$tool_root"
  install_go_toolchain "$need" "$tool_root"
  go_bin="${tool_root}/go/${need}/x64/bin/go"
fi

go_dir="$(dirname "$go_bin")"
export PATH="${go_dir}:${PATH}"

if [ -n "${GITHUB_PATH:-}" ]; then
  echo "$go_dir" >>"$GITHUB_PATH"
fi

echo "[ci] using $(go version)"
echo "[ci] GOCACHE=${GOCACHE} HOME=${HOME}"
go env GOMODCACHE
go env GOCACHE
go env >/dev/null
