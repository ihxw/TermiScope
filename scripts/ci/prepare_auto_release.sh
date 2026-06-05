#!/usr/bin/env bash
# Create git tag, push, and write release_notes.md for auto-release workflow.
# Usage: prepare_auto_release.sh <version-without-v-prefix>
set -euo pipefail

RAW_VERSION="${1:?version argument required, e.g. 1.5.19}"
VERSION="v${RAW_VERSION#v}"

echo "Preparing release: $VERSION"
# Tag 由后续 softprops/action-gh-release 创建，避免 git push tag 触发 release.yml 重复构建

# UTF-8 release notes (no BOM)
cat > release_notes.md <<EOF
## TermiScope $VERSION

自动发布版本 $VERSION

### 更新内容
请查看提交历史了解详细变更。
EOF

echo "version=$VERSION" >> "${GITHUB_OUTPUT:?GITHUB_OUTPUT not set}"
