#!/usr/bin/env bash
# Compare web/package.json version with the latest GitHub Release tag.
# Sets GITHUB_OUTPUT: changed=true|false, version=<current semver>
set -euo pipefail

read_version() {
  node -e "console.log(require('./web/package.json').version)"
}

CURRENT_VERSION=$(read_version)
echo "package.json version: $CURRENT_VERSION"

REPO="${GITHUB_REPOSITORY:-}"
TOKEN="${GITHUB_TOKEN:-}"

if [ -z "$REPO" ] || [ -z "$TOKEN" ]; then
  echo "GITHUB_REPOSITORY and GITHUB_TOKEN are required (set GITHUB_TOKEN: \${{ github.token }} in workflow env)" >&2
  exit 1
fi

LATEST_TAG=""
HTTP_CODE=$(curl -sS -o /tmp/latest_release.json -w "%{http_code}" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/${REPO}/releases/latest" || true)

if [ "$HTTP_CODE" = "200" ]; then
  LATEST_TAG=$(node -e "
    const fs = require('fs');
    const data = JSON.parse(fs.readFileSync('/tmp/latest_release.json', 'utf8'));
    process.stdout.write(data.tag_name || '');
  ")
elif [ "$HTTP_CODE" = "404" ]; then
  echo "No GitHub releases yet; treating latest as 0.0.0"
  LATEST_TAG="v0.0.0"
else
  echo "Failed to fetch latest release (HTTP ${HTTP_CODE})" >&2
  cat /tmp/latest_release.json >&2 || true
  exit 1
fi

echo "Latest GitHub release tag: ${LATEST_TAG:-<none>}"

RESULT=$(node -e "
const current = process.argv[1].replace(/^v/, '');
const latest = (process.argv[2] || '0.0.0').replace(/^v/, '');

function parts(v) {
  return v.split('.').map((n) => parseInt(n, 10) || 0);
}

function compare(a, b) {
  const pa = parts(a);
  const pb = parts(b);
  const len = Math.max(pa.length, pb.length);
  for (let i = 0; i < len; i++) {
    const da = pa[i] ?? 0;
    const db = pb[i] ?? 0;
    if (da > db) return 1;
    if (da < db) return -1;
  }
  return 0;
}

const cmp = compare(current, latest);
if (cmp > 0) {
  console.log('should_release=true');
} else if (cmp === 0) {
  console.log('should_release=false reason=same_as_latest_release');
} else {
  console.log('should_release=false reason=older_than_latest_release');
}
" "$CURRENT_VERSION" "$LATEST_TAG")

echo "$RESULT"

if echo "$RESULT" | grep -q 'should_release=true'; then
  echo "changed=true" >> "${GITHUB_OUTPUT:?GITHUB_OUTPUT not set}"
  echo "version=${CURRENT_VERSION}" >> "${GITHUB_OUTPUT}"
  echo "Release needed: ${CURRENT_VERSION} > ${LATEST_TAG#v}"
else
  echo "changed=false" >> "${GITHUB_OUTPUT}"
  echo "Skip release: ${CURRENT_VERSION} is not newer than ${LATEST_TAG:-0.0.0}"
fi
