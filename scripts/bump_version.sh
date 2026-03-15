#!/usr/bin/env bash
set -euo pipefail

PKG="web/package.json"
if [ ! -f "$PKG" ]; then
  echo "Package file not found: $PKG" >&2
  exit 1
fi

# Avoid running if last commit is already a bump to prevent recursion
last_msg=$(git log -1 --pretty=%B 2>/dev/null || true)
if [[ "$last_msg" == Bump\ version\ to* ]]; then
  echo "Last commit is a version bump, skipping."
  exit 0
fi

# Extract version (portable: use sed-compatible pattern)
ver=$(sed -En 's/.*"version"[[:space:]]*:[[:space:]]*"([0-9]+\.[0-9]+\.[0-9]+)".*/\1/p' "$PKG" | tr -d '\r' || true)
if [ -z "$ver" ]; then
  echo "Failed to parse version from $PKG" >&2
  exit 1
fi
IFS='.' read -r major minor patch <<< "$ver"
patch=$((patch + 1))
new="$major.$minor.$patch"

# Replace version string in file
perl -0777 -pe "s/\"version\"\s*:\s*\"[0-9]+\.[0-9]+\.[0-9]+\"/\"version\": \"$new\"/s" -i "$PKG"

git add "$PKG"
# Commit only if there are staged changes
if git diff --cached --quiet; then
  echo "No changes to commit."
  exit 0
fi

git commit -m "Bump version to $new"

echo "Version bumped to $new"
