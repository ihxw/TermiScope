#!/usr/bin/env bash
# Print semver without leading "v". Usage: normalize_release_version.sh 1.5.36|v1.5.36
set -euo pipefail
echo "${1#v}"
