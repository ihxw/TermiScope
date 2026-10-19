#!/bin/bash
# 从本地 .tar.gz 安装包安装，支持使用 systemd 或 OpenRC 的 Linux 系统。
# 保留已有配置和数据库，不联网安装系统依赖。
#
# Usage:
#   sudo bash scripts/install_from_archive.sh /path/to/termiscope-linux-amd64-1.5.16.tar.gz
#   sudo bash scripts/install_from_archive.sh ./release/termiscope-linux-amd64-1.5.16.tar.gz --install-dir /opt/termiscope -y
set -e

ARCHIVE=""
INSTALL_ARGS=()

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    --install-dir|--port|-y|--non-interactive)
      INSTALL_ARGS+=("$1")
      if [ "$1" = "--install-dir" ] || [ "$1" = "--port" ]; then
        if [ $# -lt 2 ] || [ -z "$2" ] || [[ "$2" == --* ]]; then
          echo "错误：$1 缺少参数值。" >&2
          exit 1
        fi
        INSTALL_ARGS+=("$2")
        shift
      fi
      shift
      ;;
    *)
      if [ -z "$ARCHIVE" ]; then
        ARCHIVE="$1"
      else
        INSTALL_ARGS+=("$1")
      fi
      shift
      ;;
  esac
done

if [ "$EUID" -ne 0 ]; then
  echo "错误：请使用 root 权限运行（sudo bash $0）。" >&2
  exit 1
fi

# 归档入口只检查解包所需命令；服务管理器及运行依赖由包内安装器检查。
MISSING_DEPENDENCIES=()
for dependency in bash tar gzip find head dirname basename mkdir rm chmod; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    MISSING_DEPENDENCIES+=("$dependency")
  fi
done
if [ "${#MISSING_DEPENDENCIES[@]}" -gt 0 ]; then
  echo "错误：缺少依赖命令：${MISSING_DEPENDENCIES[*]}。请先使用当前发行版的软件包管理器安装后重试；离线安装器不会联网安装依赖。" >&2
  exit 1
fi

if [ -z "$ARCHIVE" ]; then
  echo "Error: archive path required" >&2
  echo "Example: sudo bash $0 ./release/termiscope-linux-amd64-1.5.16.tar.gz -y" >&2
  exit 1
fi

if [ ! -f "$ARCHIVE" ]; then
  echo "Error: archive not found: $ARCHIVE" >&2
  exit 1
fi

if readlink -f "$ARCHIVE" >/dev/null 2>&1; then
  ARCHIVE="$(readlink -f "$ARCHIVE")"
else
  ARCHIVE="$(cd "$(dirname "$ARCHIVE")" && pwd)/$(basename "$ARCHIVE")"
fi

EXTRACT_ROOT="${TERMISCOPE_INSTALL_TMP:-/tmp/termiscope-install-$$}"
mkdir -p "$EXTRACT_ROOT"
trap 'rm -rf "$EXTRACT_ROOT"' EXIT

echo "Extracting $ARCHIVE ..."
tar -xzf "$ARCHIVE" -C "$EXTRACT_ROOT"

PKG_DIR="$(find "$EXTRACT_ROOT" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
if [ -z "$PKG_DIR" ] || [ ! -f "$PKG_DIR/TermiScope" ]; then
  echo "Error: invalid package (missing TermiScope binary)" >&2
  exit 1
fi

INSTALL_SCRIPT="$PKG_DIR/scripts/install_local.sh"
if [ ! -f "$INSTALL_SCRIPT" ]; then
  echo "Error: install_local.sh not found in package" >&2
  exit 1
fi

chmod +x "$PKG_DIR/TermiScope" "$INSTALL_SCRIPT" 2>/dev/null || true
bash "$INSTALL_SCRIPT" "${INSTALL_ARGS[@]}"
