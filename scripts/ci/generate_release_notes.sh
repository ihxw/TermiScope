#!/usr/bin/env bash
# Generate user-facing notes from commits since the previous package version.
set -euo pipefail

RAW_VERSION="${1:?version argument required, e.g. 1.7.30}"
OUTPUT="${2:-release_notes.generated.md}"
VERSION="${RAW_VERSION#v}"

CURRENT_VERSION=$(sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' web/package.json | head -n 1)
if [ -z "$CURRENT_VERSION" ] || [ "$CURRENT_VERSION" != "$VERSION" ]; then
  echo "Version argument $VERSION does not match web/package.json (${CURRENT_VERSION:-unknown})" >&2
  exit 1
fi

read_version_at() {
  git show "${1}:web/package.json" 2>/dev/null |
    sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' |
    head -n 1
}

BASE_COMMIT=""
PREVIOUS_VERSION=""
while IFS= read -r commit; do
  commit_version=$(read_version_at "$commit" || true)
  if [ -n "$commit_version" ] && [ "$commit_version" != "$VERSION" ]; then
    BASE_COMMIT="$commit"
    PREVIOUS_VERSION="$commit_version"
    break
  fi
done < <(git log --format='%H' -- web/package.json)

if [ -n "$BASE_COMMIT" ]; then
  RANGE="${BASE_COMMIT}..HEAD"
else
  RANGE="HEAD"
fi

TMP_SUBJECTS=$(mktemp)
trap 'rm -f "$TMP_SUBJECTS"' EXIT
git log --reverse --no-merges --format='%s' "$RANGE" > "$TMP_SUBJECTS"

mkdir -p "$(dirname "$OUTPUT")"
{
  printf '## TermiScope v%s\n\n' "$VERSION"
  if [ -n "$PREVIOUS_VERSION" ]; then
    printf '从 v%s 升级到 v%s。\n\n' "$PREVIOUS_VERSION" "$VERSION"
  fi
  printf '### 更新内容\n\n'

  count=0
  while IFS= read -r subject; do
    subject=${subject//$'\r'/}
    [ -n "$subject" ] || continue
    case "$subject" in
      "chore: 更新版本至 "*|"chore: 更新版本到 "*|"chore: bump version"*|"chore(release):"*|"Release v"*|"release: v"*)
        continue
        ;;
    esac
    printf -- '- %s\n' "$subject"
    count=$((count + 1))
  done < "$TMP_SUBJECTS"

  if [ "$count" -eq 0 ]; then
    printf -- '- 完成 v%s 的内部优化与依赖更新。\n' "$VERSION"
  fi
} > "$OUTPUT"

echo "Generated $OUTPUT from ${RANGE}"
