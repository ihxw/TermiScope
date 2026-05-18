#!/usr/bin/env bash
# Create git tag, push, and write release_notes.md for auto-release workflow.
# Usage: prepare_auto_release.sh <version-without-v-prefix>
set -euo pipefail

RAW_VERSION="${1:?version argument required, e.g. 1.5.19}"
VERSION="v${RAW_VERSION#v}"

echo "Creating release: $VERSION"

git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"

git tag -a "$VERSION" -m "Release $VERSION"
git push origin "$VERSION"

# UTF-8 release notes (no BOM)
cat > release_notes.md <<EOF
## TermiScope $VERSION

自动发布版本 $VERSION

### 更新内容
请查看提交历史了解详细变更。
EOF

echo "version=$VERSION" >> "${GITHUB_OUTPUT:?GITHUB_OUTPUT not set}"
