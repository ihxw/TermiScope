#!/bin/bash
# 从本地离线安装包安装 TermiScope，不下载文件或安装系统依赖。
# 保留现有 configs/config.yaml、data/ 和 logs/。
#
# Run from extracted package root:
#   sudo ./scripts/install_local.sh -y
set -e

DEFAULT_INSTALL_DIR="/opt/termiscope"
SERVICE_NAME="termiscope"
NONINTERACTIVE=false
INSTALL_DIR=""
USER_PORT=""
SERVICE_MANAGER=""
OPENRC_RUN=""

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

check_dependencies() {
  local dependency
  local missing=()
  local dependencies=(uname dirname basename mkdir cp chmod rm ls grep head sed tr awk cat cut)
  if [ ! -f "$INSTALL_DIR/configs/config.yaml" ]; then
    dependencies+=(openssl)
  fi
  for dependency in "${dependencies[@]}"; do
    if ! command -v "$dependency" >/dev/null 2>&1; then
      missing+=("$dependency")
    fi
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    echo "错误：缺少依赖命令：${missing[*]}。请先使用当前发行版的软件包管理器安装后重试；离线安装器不会联网安装依赖。" >&2
    exit 1
  fi
}

detect_service_manager() {
  # 实际连接 systemd，避免将只装有 systemctl 的容器误判为 systemd 主机。
  if command -v systemctl >/dev/null 2>&1 && systemctl show-environment >/dev/null 2>&1; then
    SERVICE_MANAGER="systemd"
  elif command -v rc-service >/dev/null 2>&1 && command -v rc-update >/dev/null 2>&1 && command -v openrc-run >/dev/null 2>&1; then
    SERVICE_MANAGER="openrc"
    OPENRC_RUN="$(command -v openrc-run)"
  else
    echo "错误：未找到可用的 systemd 或 OpenRC，安装已中止；请先在宿主机启用服务管理器。" >&2
    exit 1
  fi
}

generate_secret() {
  local secret
  secret=$(openssl rand -base64 48) || return 1
  printf '%s' "$secret" | tr -d '\n' | cut -c1-32
}

# OpenRC 配置由 shell 读取，安装目录需要保留为原始字符串。
escape_openrc_value() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\$/\\$/g' -e 's/`/\\`/g'
}

# systemd 的 ExecStart 会解释反斜线、引号和百分号说明符。
escape_systemd_value() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/%/%%/g'
}

get_local_ips() {
  if command -v hostname >/dev/null 2>&1; then
    hostname -I 2>/dev/null | tr ' ' '\n' || true
  fi

  if command -v ip >/dev/null 2>&1; then
    ip -o -4 addr show scope global 2>/dev/null | awk '{split($4, a, "/"); print a[1]}' || true
  fi

  if command -v ifconfig >/dev/null 2>&1; then
    ifconfig 2>/dev/null | awk '/inet / {print $2}' || true
  fi
}

build_allowed_origins_yaml() {
  {
    printf '  allowed_origins:\n'
    printf '    - "http://localhost:%s"\n' "$PORT"
    printf '    - "http://127.0.0.1:%s"\n' "$PORT"
    get_local_ips | while IFS= read -r ip_addr; do
      case "$ip_addr" in
        ""|*:*|127.*|0.0.0.0|169.254.*) continue ;;
      esac
      printf '    - "http://%s:%s"\n' "$ip_addr" "$PORT"
    done
  } | awk '!seen[$0]++'
}

usage() {
  sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
  echo ""
  echo "Options:"
  echo "  --install-dir PATH   Install directory (default: /opt/termiscope)"
  echo "  --port PORT          HTTP port for new installs only (default: 3000)"
  echo "  -y, --non-interactive  No prompts"
  echo "  -h, --help           Show help"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --install-dir|--port)
      if [ $# -lt 2 ] || [ -z "$2" ] || [[ "$2" == --* ]]; then
        echo "错误：$1 缺少参数值。" >&2
        exit 1
      fi
      if [ "$1" = "--install-dir" ]; then
        INSTALL_DIR="$2"
      else
        USER_PORT="$2"
      fi
      shift 2
      ;;
    -y|--non-interactive) NONINTERACTIVE=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

if [ ! -t 0 ]; then
  NONINTERACTIVE=true
fi

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Please run as root (sudo)${NC}"
  exit 1
fi

INSTALL_DIR="${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}"
check_dependencies
if [ "$(uname -s)" != "Linux" ]; then
  echo "错误：离线安装器只支持使用 systemd 或 OpenRC 的 Linux 系统。" >&2
  exit 1
fi
detect_service_manager
if [ "$SERVICE_MANAGER" = "openrc" ] && ! [[ "$INSTALL_DIR" =~ ^[a-zA-Z0-9_./:+,@%=-]+$ ]]; then
  echo "错误：OpenRC 安装路径不支持空白或 shell 特殊字符，请使用常规绝对路径。" >&2
  exit 1
fi

if readlink -f "$0" >/dev/null 2>&1; then
  SCRIPT_PATH="$(readlink -f "$0")"
else
  SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
fi
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
if [ "$(basename "$SCRIPT_DIR")" = "scripts" ]; then
  PACKAGE_DIR="$(dirname "$SCRIPT_DIR")"
else
  PACKAGE_DIR="$SCRIPT_DIR"
fi

if [ ! -f "$PACKAGE_DIR/TermiScope" ] || [ ! -d "$PACKAGE_DIR/web/dist" ]; then
  echo -e "${RED}Error: need TermiScope binary and web/dist in package${NC}"
  echo "  PACKAGE_DIR=$PACKAGE_DIR"
  exit 1
fi

case "$INSTALL_DIR" in
  /*) ;;
  *) echo "错误：安装目录必须是绝对路径。" >&2; exit 1 ;;
esac
if [[ "$INSTALL_DIR" == *$'\n'* ]] || [[ "$INSTALL_DIR" == *$'\r'* ]]; then
  echo "错误：安装目录不能包含换行符。" >&2
  exit 1
fi
if [ -n "$USER_PORT" ] && { ! [[ "$USER_PORT" =~ ^[0-9]{1,5}$ ]] || [ "$((10#$USER_PORT))" -lt 1 ] || [ "$((10#$USER_PORT))" -gt 65535 ]; }; then
  echo "错误：端口必须是 1 至 65535 的整数。" >&2
  exit 1
fi

echo -e "${GREEN}=== TermiScope Local Install ===${NC}"
echo -e "Package:  $PACKAGE_DIR"
echo -e "Target:   $INSTALL_DIR"

HAS_CONFIG=false
HAS_DATA=false
HAS_LOGS=false
if [ -f "$INSTALL_DIR/configs/config.yaml" ]; then
  HAS_CONFIG=true
fi
if [ -f "$INSTALL_DIR/data/termiscope.db" ] || [ -n "$(ls -A "$INSTALL_DIR/data" 2>/dev/null)" ]; then
  HAS_DATA=true
fi
if [ -n "$(ls -A "$INSTALL_DIR/logs" 2>/dev/null)" ]; then
  HAS_LOGS=true
fi

if [ "$HAS_CONFIG" = true ]; then
  PORT=$(grep -E '^[[:space:]]*port:' "$INSTALL_DIR/configs/config.yaml" | head -1 | sed -E 's/.*port:[[:space:]]*//' | tr -d ' ')
  [ -z "$PORT" ] && PORT=3000
else
  if [ -n "$USER_PORT" ]; then
    PORT="$((10#$USER_PORT))"
  elif [ "$NONINTERACTIVE" = true ]; then
    PORT=3000
  else
    read -r -p "Server port [3000]: " PORT
    PORT=${PORT:-3000}
  fi
  # 在停止旧服务或改写安装目录前，确认随机密钥能够正常生成。
  JWT_SECRET=$(generate_secret)
  ENCRYPTION_KEY=$(generate_secret)
  ALLOWED_ORIGINS_YAML=$(build_allowed_origins_yaml)
fi

if [ "$SERVICE_MANAGER" = "openrc" ]; then
  if rc-service "$SERVICE_NAME" status >/dev/null 2>&1; then
    echo -e "${YELLOW}正在停止 $SERVICE_NAME...${NC}"
    rc-service "$SERVICE_NAME" stop
  fi
elif systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
  echo -e "${YELLOW}Stopping $SERVICE_NAME...${NC}"
  systemctl stop "$SERVICE_NAME"
fi

mkdir -p "$INSTALL_DIR"/{configs,data,logs,agents,web}

echo "Installing binary..."
cp -f "$PACKAGE_DIR/TermiScope" "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/TermiScope"

echo "Installing web assets..."
rm -rf "$INSTALL_DIR/web/dist"
mkdir -p "$INSTALL_DIR/web/dist"
cp -a "$PACKAGE_DIR/web/dist/." "$INSTALL_DIR/web/dist/"

if [ -d "$PACKAGE_DIR/agents" ] && [ -n "$(ls -A "$PACKAGE_DIR/agents" 2>/dev/null)" ]; then
  echo "正在更新安装包内的 Agent，保留目录中的额外文件..."
  if ! cp -af "$PACKAGE_DIR/agents/." "$INSTALL_DIR/agents/"; then
    echo "错误: Agent 文件复制失败，安装已中止；请检查权限与磁盘空间。" >&2
    exit 1
  fi
fi

echo "Installing helper scripts..."
if [ -d "$PACKAGE_DIR/scripts" ]; then
  mkdir -p "$INSTALL_DIR/scripts"
  cp -r "$PACKAGE_DIR/scripts/"* "$INSTALL_DIR/scripts/" 2>/dev/null || true
elif [ -d "$SCRIPT_DIR" ] && [ "$(basename "$SCRIPT_DIR")" = "scripts" ]; then
  mkdir -p "$INSTALL_DIR/scripts"
  cp -r "$SCRIPT_DIR/"* "$INSTALL_DIR/scripts/" 2>/dev/null || true
fi

for script in repair_database.sh uninstall.sh; do
  if [ -f "$PACKAGE_DIR/scripts/$script" ]; then
    cp -f "$PACKAGE_DIR/scripts/$script" "$INSTALL_DIR/"
  elif [ -f "$SCRIPT_DIR/$script" ]; then
    cp -f "$SCRIPT_DIR/$script" "$INSTALL_DIR/"
  fi
  chmod +x "$INSTALL_DIR/$script" 2>/dev/null || true
done

if [ "$HAS_DATA" = true ]; then
  echo -e "${YELLOW}Preserving existing data directory (database not touched).${NC}"
else
  echo -e "${GREEN}Data directory ready (empty): $INSTALL_DIR/data${NC}"
fi

if [ "$HAS_LOGS" = true ]; then
  echo -e "${YELLOW}Preserving existing logs directory.${NC}"
fi

if [ -f "$PACKAGE_DIR/configs/config.yaml.example" ]; then
  cp -n "$PACKAGE_DIR/configs/config.yaml.example" "$INSTALL_DIR/configs/config.yaml.example" 2>/dev/null || true
fi

if [ "$HAS_CONFIG" = true ]; then
  echo -e "${YELLOW}Preserving existing config: $INSTALL_DIR/configs/config.yaml${NC}"
else
  cat > "$INSTALL_DIR/configs/config.yaml" <<EOF
server:
  port: $PORT
  mode: release
  # 通过 HTTPS 反向代理或公网域名访问时必须取消注释并填写；Agent 使用此地址回传监控数据。
  # public_base_url: https://termiscope.example.com
$ALLOWED_ORIGINS_YAML
  max_upload_size: 1048576000

database:
  path: ./data/termiscope.db

security:
  jwt_secret: "$JWT_SECRET"
  encryption_key: "$ENCRYPTION_KEY"
  smtp_tls_skip_verify: false

log:
  level: info
  file: ./logs/app.log
EOF
  echo -e "${GREEN}Created $INSTALL_DIR/configs/config.yaml${NC}"
fi

if [ "$SERVICE_MANAGER" = "openrc" ]; then
  echo "正在配置 OpenRC 服务..."
  OPENRC_INSTALL_DIR=$(escape_openrc_value "$INSTALL_DIR")
  mkdir -p /etc/init.d
  cat > "/etc/init.d/$SERVICE_NAME" <<EOF
#!$OPENRC_RUN

name="TermiScope Server"
description="TermiScope 监控与 SSH 管理服务"
command="$OPENRC_INSTALL_DIR/TermiScope"
directory="$OPENRC_INSTALL_DIR"
pidfile="/run/$SERVICE_NAME.pid"
command_background=true

depend() {
    use dns
    need net
}

start_pre() {
    checkpath -d -o root:root -m 755 /run
}
EOF
  chmod +x "/etc/init.d/$SERVICE_NAME"
  rc-update add "$SERVICE_NAME" default
  echo -e "${GREEN}正在启动 $SERVICE_NAME...${NC}"
  rc-service "$SERVICE_NAME" start
  rc-service "$SERVICE_NAME" status || true
else
  echo "Installing systemd unit..."
  SYSTEMD_INSTALL_DIR=$(escape_systemd_value "$INSTALL_DIR")
  # WorkingDirectory 直接读取路径，不进行 ExecStart 的引号和反斜线解码。
  SYSTEMD_WORKING_DIR=$(printf '%s' "$INSTALL_DIR" | sed 's/%/%%/g')
  mkdir -p /etc/systemd/system
  cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=TermiScope Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$SYSTEMD_WORKING_DIR
ExecStart="$SYSTEMD_INSTALL_DIR/TermiScope"
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable "$SERVICE_NAME"
  echo -e "${GREEN}Starting $SERVICE_NAME...${NC}"
  systemctl start "$SERVICE_NAME"
  systemctl --no-pager status "$SERVICE_NAME" || true
fi

echo -e "${GREEN}=== Installation complete ===${NC}"
echo -e "URL:    http://<server-ip>:${PORT}"
echo -e "Config: $INSTALL_DIR/configs/config.yaml"
echo -e "Data:   $INSTALL_DIR/data/ (unchanged if existed)"
echo -e "Logs:   $INSTALL_DIR/logs/ (unchanged if existed)"
echo -e "Repair: sudo $INSTALL_DIR/repair_database.sh --data-dir $INSTALL_DIR/data"
