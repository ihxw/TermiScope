#!/usr/bin/env bash
set -euo pipefail

HOOK_DIR=".git/hooks"
if [ ! -d ".git" ]; then
  echo "Not a git repository (no .git)." >&2
  exit 1
fi

mkdir -p "$HOOK_DIR"
cat > "$HOOK_DIR/post-commit" <<'HOOK'
#!/usr/bin/env bash
# Post-commit hook: bump package.json version (if applicable)
# Avoid recursion: bump script checks last commit message.
SCRIPTDIR="$(cd "$(dirname "$0")/.." && pwd)/scripts"
if [ -x "$SCRIPTDIR/bump_version.sh" ]; then
  "$SCRIPTDIR/bump_version.sh" || true
fi
HOOK

chmod +x "$HOOK_DIR/post-commit"

echo "Installed post-commit hook to bump web/package.json on each commit."
