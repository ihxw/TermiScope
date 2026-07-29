#!/usr/bin/env bash
# Create git tag, push, and write release_notes.md for auto-release workflow.
# Usage: prepare_auto_release.sh <version-without-v-prefix>
set -euo pipefail

RAW_VERSION="${1:?version argument required, e.g. 1.5.19}"
VERSION="v${RAW_VERSION#v}"

echo "Preparing release: $VERSION"
# Tag 由后续 softprops/action-gh-release 创建，避免 git push tag 触发 release.yml 重复构建

# Prefer notes generated on Gitea, where the full commit history is available.
if [ -s release_notes.generated.md ] && grep -Fq "TermiScope $VERSION" release_notes.generated.md; then
  cp release_notes.generated.md release_notes.md
else
  # UTF-8 fallback for manual releases without generated notes.
  cat > release_notes.md <<EOF
## TermiScope $VERSION

自动发布版本 $VERSION

### 更新内容
本次发布未携带自动生成的变更清单，请查看项目提交历史。
EOF
fi

echo "version=$VERSION" >> "${GITHUB_OUTPUT:?GITHUB_OUTPUT not set}"
