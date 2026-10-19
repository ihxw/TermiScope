#!/bin/bash
set -e

# Default settings
DEFAULT_INSTALL_DIR="${TERMISCOPE_INSTALL_DIR:-/opt/termiscope}"
SERVICE_NAME="${TERMISCOPE_SERVICE_NAME:-termiscope}"
MACOS_PLIST_ID="com.termiscope.server"
MACOS_PLIST_PATH="/Library/LaunchDaemons/${MACOS_PLIST_ID}.plist"
NONINTERACTIVE=false
INSTALL_DIR=""
USER_PORT=""

usage() {
    echo "Usage: sudo bash install.sh [options]"
    echo ""
    echo "Options:"
    echo "  --install-dir PATH      Install directory (default: /opt/termiscope)"
    echo "  --port PORT             HTTP port for new installs only (default: 3000)"
    echo "  --docker                使用 Docker Compose 部署 TermiScope"
    echo "  -y, --non-interactive   No prompts"
    echo "  -h, --help              Show help"
}

# Parse arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --docker)
            SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
            if [ -f "${SCRIPT_DIR}/docker_deploy.sh" ]; then
                exec bash "${SCRIPT_DIR}/docker_deploy.sh" up
            elif [ -f "./scripts/docker_deploy.sh" ]; then
                exec bash "./scripts/docker_deploy.sh" up
            else
                echo "未找到 docker_deploy.sh 脚本"
                exit 1
            fi
            ;;
        --install-dir)
            if [ $# -lt 2 ] || [ -z "$2" ] || [[ "$2" == --* ]]; then
                echo "错误: --install-dir 缺少参数值。" >&2
                exit 1
            fi
            INSTALL_DIR="$2"
            shift 2
            ;;
        --port)
            if [ $# -lt 2 ] || [ -z "$2" ] || [[ "$2" == --* ]]; then
                echo "错误: --port 缺少参数值。" >&2
                exit 1
            fi
            USER_PORT="$2"
            shift 2
            ;;
        --non-interactive|-y)
            NONINTERACTIVE=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

can_prompt() {
    if [ -t 0 ]; then
        return 0
    fi

    if [ -c /dev/tty ] && { true < /dev/tty; } 2>/dev/null && { true > /dev/tty; } 2>/dev/null; then
        return 0
    fi

    return 1
}

# Auto-detect non-interactive mode only when no terminal is available for prompts.
if ! can_prompt; then
    NONINTERACTIVE=true
fi

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

prompt_input() {
    prompt="$1"
    var_name="$2"

    if [ -t 0 ]; then
        read -r -p "$prompt" "$var_name"
    elif [ -c /dev/tty ]; then
        if ! printf "%s" "$prompt" > /dev/tty; then
            return 1
        fi
        if ! IFS= read -r "$var_name" < /dev/tty; then
            return 1
        fi
    else
        return 1
    fi
}

get_local_ips() {
    if command -v hostname >/dev/null 2>&1; then
        hostname -I 2>/dev/null | tr ' ' '\n' || true
    fi

    if command -v ip >/dev/null 2>&1; then
        ip -o -4 addr show scope global 2>/dev/null | awk '{split($4, a, "/"); print a[1]}' || true
    fi

    if command -v route >/dev/null 2>&1 && command -v ipconfig >/dev/null 2>&1; then
        default_iface=$(route get default 2>/dev/null | awk '/interface:/{print $2; exit}')
        if [ -n "$default_iface" ]; then
            ipconfig getifaddr "$default_iface" 2>/dev/null || true
        fi
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

check_base_dependencies() {
    local dependency
    local missing=()
    for dependency in uname dirname basename find head mkdir cp chmod rm grep sed tr awk cat cut mktemp; do
        if ! command -v "$dependency" >/dev/null 2>&1; then
            missing+=("$dependency")
        fi
    done
    if [ ${#missing[@]} -gt 0 ]; then
        echo "错误: 缺少基础命令 ${missing[*]}，请使用系统软件包管理器安装后重试。" >&2
        return 1
    fi
}

check_base_dependencies

# Detect OS.
UNAME_OS=$(uname -s)
case "$UNAME_OS" in
    Linux) TARGET_OS="linux" ;;
    Darwin) TARGET_OS="darwin" ;;
    *) echo -e "${RED}Unsupported OS: $UNAME_OS${NC}"; exit 1 ;;
esac

detect_service_manager() {
    if [ "$TARGET_OS" = "darwin" ]; then
        SERVICE_MANAGER="launchd"
    elif command -v systemctl >/dev/null 2>&1 && systemctl show-environment >/dev/null 2>&1; then
        SERVICE_MANAGER="systemd"
    elif command -v rc-service >/dev/null 2>&1 && command -v rc-update >/dev/null 2>&1 && command -v openrc-run >/dev/null 2>&1; then
        SERVICE_MANAGER="openrc"
        OPENRC_RUN=$(command -v openrc-run)
    else
        echo "错误: 未检测到可用的 systemd 或 OpenRC，请在启用服务管理器后安装，或使用 Docker 部署。" >&2
        return 1
    fi
}

install_dependencies() {
    local dependency
    local missing=()
    for dependency in "$@"; do
        if ! command -v "$dependency" >/dev/null 2>&1; then
            missing+=("$dependency")
        fi
    done
    [ ${#missing[@]} -gt 0 ] || return 0

    if [ "$TARGET_OS" != "linux" ]; then
        echo "错误: 缺少依赖 ${missing[*]}，请手动安装后重试。" >&2
        return 1
    fi

    echo "正在安装缺少的依赖: ${missing[*]}"
    # 同时补齐 HTTPS 下载所需的系统证书；只在确有缺失时调用包管理器。
    local packages=("${missing[@]}" ca-certificates)
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -qq && apt-get install -y "${packages[@]}" || return 1
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y "${packages[@]}" || return 1
    elif command -v yum >/dev/null 2>&1; then
        yum install -y "${packages[@]}" || return 1
    elif command -v microdnf >/dev/null 2>&1; then
        microdnf install -y "${packages[@]}" || return 1
    elif command -v apk >/dev/null 2>&1; then
        apk add --no-cache "${packages[@]}" || return 1
    elif command -v pacman >/dev/null 2>&1; then
        pacman -S --needed --noconfirm "${packages[@]}" || return 1
    elif command -v zypper >/dev/null 2>&1; then
        zypper --non-interactive install "${packages[@]}" || return 1
    else
        echo "错误: 未找到支持的包管理器，请手动安装 ${missing[*]} 后重试。" >&2
        return 1
    fi

    for dependency in "${missing[@]}"; do
        if ! command -v "$dependency" >/dev/null 2>&1; then
            echo "错误: 安装依赖后仍找不到 $dependency，请检查软件源与 PATH。" >&2
            return 1
        fi
    done
}

stop_existing_service() {
    case "$SERVICE_MANAGER" in
        launchd)
            if launchctl print "system/${MACOS_PLIST_ID}" >/dev/null 2>&1; then
                launchctl bootout system "$MACOS_PLIST_PATH" 2>/dev/null || \
                    launchctl bootout "system/${MACOS_PLIST_ID}"
            fi
            ;;
        openrc)
            if rc-service "$SERVICE_NAME" status >/dev/null 2>&1; then
                rc-service "$SERVICE_NAME" stop
            fi
            ;;
        systemd)
            if systemctl is-active --quiet "$SERVICE_NAME"; then
                systemctl stop "$SERVICE_NAME"
            fi
            ;;
    esac
}

# OpenRC 配置由 shell 读取；systemd 还会展开百分号说明符。
escape_service_path() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\$/\\$/g' -e 's/`/\\`/g'
}

escape_systemd_path() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/%/%%/g'
}

# Check root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Please run as root${NC}"
  exit 1
fi

echo -e "${GREEN}=== TermiScope Installer ===${NC}"

# 2. Determine Install Directory
if [ -n "$INSTALL_DIR" ]; then
    IS_UPDATE=false
    if [ -d "$INSTALL_DIR" ]; then
        IS_UPDATE=true
    fi
elif [ -d "$DEFAULT_INSTALL_DIR" ]; then
    echo -e "${YELLOW}Detected existing installation at $DEFAULT_INSTALL_DIR${NC}"
    INSTALL_DIR="$DEFAULT_INSTALL_DIR"
    IS_UPDATE=true
else
    if [ "$NONINTERACTIVE" = true ]; then
        INSTALL_DIR="$DEFAULT_INSTALL_DIR"
    else
        prompt_input "Install location [$DEFAULT_INSTALL_DIR]: " USER_DIR
        INSTALL_DIR=${USER_DIR:-$DEFAULT_INSTALL_DIR}
    fi
    IS_UPDATE=false
fi

echo -e "Installing to: ${GREEN}$INSTALL_DIR${NC}"

# 在下载、停止旧服务和写入文件前完成系统及依赖检查。
case "$INSTALL_DIR" in
    /*) ;;
    *) echo "错误: 安装目录必须是绝对路径。" >&2; exit 1 ;;
esac
if [[ "$INSTALL_DIR" == *$'\n'* ]] || [[ "$INSTALL_DIR" == *$'\r'* ]]; then
    echo "错误: 安装目录不能包含换行符。" >&2
    exit 1
fi
if [ -n "$USER_PORT" ]; then
    if ! [[ "$USER_PORT" =~ ^[0-9]{1,5}$ ]] || [ "$((10#$USER_PORT))" -lt 1 ] || [ "$((10#$USER_PORT))" -gt 65535 ]; then
        echo "错误: 端口必须是 1 至 65535 的整数。" >&2
        exit 1
    fi
    USER_PORT="$((10#$USER_PORT))"
fi
detect_service_manager
if [ "$SERVICE_MANAGER" = "openrc" ] && ! [[ "$INSTALL_DIR" =~ ^[a-zA-Z0-9_./:+,@%=-]+$ ]]; then
    echo "错误: OpenRC 安装路径不支持空白或 shell 特殊字符，请使用常规绝对路径。" >&2
    exit 1
fi

# 保持在线脚本自包含，可直接以 curl | bash 方式执行。
if readlink -f "$0" >/dev/null 2>&1; then
    SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
else
    SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
fi
if [ "$(basename "$SCRIPT_DIR")" = "scripts" ]; then
    PACKAGE_DIR=$(dirname "$SCRIPT_DIR")
else
    PACKAGE_DIR="$SCRIPT_DIR"
fi

LOCAL_BINARY=$(find "$PACKAGE_DIR" -maxdepth 1 -name "TermiScope*" -type f -not -name "*.*" | head -n 1)
REQUIRED_COMMANDS=()
if [ ! -f "$INSTALL_DIR/configs/config.yaml" ]; then
    REQUIRED_COMMANDS+=(openssl)
fi
if [ -n "$LOCAL_BINARY" ] && [ -d "$PACKAGE_DIR/web/dist" ]; then
    echo "Files found locally. Proceeding with offline installation..."
    for dependency in "${REQUIRED_COMMANDS[@]}"; do
        if ! command -v "$dependency" >/dev/null 2>&1; then
            echo "错误: 离线安装缺少 $dependency，请预先安装依赖后重试。" >&2
            exit 1
        fi
    done
else
    echo "正在从 GitHub 在线安装..."
    install_dependencies curl tar gzip "${REQUIRED_COMMANDS[@]}"

    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64|amd64) ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
        armv7l|armv7) ARCH="arm" ;;
        *) echo "错误: 不支持的架构 $ARCH" >&2; exit 1 ;;
    esac
    echo "Detected System: $TARGET_OS/$ARCH"

    RESPONSE=$(curl -fsSL "https://api.github.com/repos/ihxw/TermiScope/releases/latest")
    VERSION=$(printf '%s\n' "$RESPONSE" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    if [ -z "$VERSION" ]; then
        echo "错误: 无法获取 GitHub 最新版本。" >&2
        exit 1
    fi
    echo "Latest Version: $VERSION"

    SEARCH_PATTERN="${TARGET_OS}-${ARCH}\.tar\.gz$"
    DOWNLOAD_URL=$(printf '%s\n' "$RESPONSE" | grep -o 'https://[^"]*' | grep -E "$SEARCH_PATTERN" | head -n 1)
    if [ -z "$DOWNLOAD_URL" ]; then
        echo "错误: 未找到匹配 $TARGET_OS-$ARCH 的发布包。" >&2
        exit 1
    fi

    TMP_DIR=$(mktemp -d)
    trap 'rm -rf "$TMP_DIR"' EXIT
    FILE_NAME=$(basename "$DOWNLOAD_URL")
    echo "Downloading from $DOWNLOAD_URL ..."
    curl -fL -o "$TMP_DIR/$FILE_NAME" "$DOWNLOAD_URL"
    tar -xzf "$TMP_DIR/$FILE_NAME" -C "$TMP_DIR"

    PACKAGE_DIR=$(find "$TMP_DIR" -maxdepth 1 -type d -name "TermiScope*" | head -n 1)
    PACKAGE_DIR=${PACKAGE_DIR:-$TMP_DIR}
    LOCAL_BINARY="$PACKAGE_DIR/TermiScope"
    if [ ! -f "$LOCAL_BINARY" ] || [ ! -d "$PACKAGE_DIR/web/dist" ]; then
        echo "错误: 发布包缺少 TermiScope 或 web/dist。" >&2
        exit 1
    fi
fi

# 确认随机数工具可以工作，避免停服后才发现依赖运行失败。
if [ ! -f "$INSTALL_DIR/configs/config.yaml" ]; then
    SECRET_OUTPUT=$(openssl rand -base64 48)
    DEFAULT_JWT_SECRET=$(printf '%s' "$SECRET_OUTPUT" | tr -d '\n' | cut -c1-32)
    SECRET_OUTPUT=$(openssl rand -base64 48)
    DEFAULT_ENCRYPTION_KEY=$(printf '%s' "$SECRET_OUTPUT" | tr -d '\n' | cut -c1-32)
    unset SECRET_OUTPUT
fi

stop_existing_service
mkdir -p "$INSTALL_DIR"/{configs,data,logs,agents,web}
echo "Copying binary..."
cp -f "$LOCAL_BINARY" "$INSTALL_DIR/TermiScope"
chmod +x "$INSTALL_DIR/TermiScope"
echo "Copying web assets..."
rm -rf "$INSTALL_DIR/web/dist"
cp -r "$PACKAGE_DIR/web/dist" "$INSTALL_DIR/web/"
if [ -d "$PACKAGE_DIR/agents" ]; then
    cp -af "$PACKAGE_DIR/agents/." "$INSTALL_DIR/agents/"
fi
if [ -d "$PACKAGE_DIR/scripts" ]; then
    mkdir -p "$INSTALL_DIR/scripts"
    cp -r "$PACKAGE_DIR/scripts/." "$INSTALL_DIR/scripts/"
    if [ -f "$PACKAGE_DIR/scripts/uninstall.sh" ]; then
        cp -f "$PACKAGE_DIR/scripts/uninstall.sh" "$INSTALL_DIR/"
        chmod +x "$INSTALL_DIR/uninstall.sh"
    fi
elif [ -f "$PACKAGE_DIR/uninstall.sh" ]; then
    cp -f "$PACKAGE_DIR/uninstall.sh" "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/uninstall.sh"
fi

# 6. Config Handling
if [ -f "$INSTALL_DIR/configs/config.yaml" ]; then
    echo -e "${YELLOW}Preserving existing configuration.${NC}"
    
    # Read port from existing config
    PORT=$(grep -E '^[[:space:]]*port:' "$INSTALL_DIR/configs/config.yaml" | head -n 1 | sed 's/.*port:[[:space:]]*//' | tr -d ' ')
    if [ -z "$PORT" ]; then
        PORT=8080  # Fallback default
    fi
    echo -e "Detected port: ${GREEN}$PORT${NC}"
else
    echo "Installing default configuration..."
    
    # Prompt for Port
    if [ -n "$USER_PORT" ]; then
        PORT="$USER_PORT"
    elif [ "$NONINTERACTIVE" = true ]; then
        PORT=3000
    else
        prompt_input "Enter server port [3000]: " USER_PORT
        PORT=${USER_PORT:-3000}
    fi
    
    echo -e "Set port to ${GREEN}$PORT${NC}"
    
    echo ""
    echo -e "${GREEN}=== Security Keys Configuration ===${NC}"
    echo ""
    
    command -v openssl >/dev/null 2>&1 || { echo >&2 "Error: openssl is required but not installed."; exit 1; }

    # Generate JWT Secret (32+ characters)
    echo -e "${YELLOW}JWT Secret Configuration${NC}"
    echo "A secure random JWT secret has been generated."
    echo -e "Default value: ${GREEN}$DEFAULT_JWT_SECRET${NC}"
    if [ "$NONINTERACTIVE" = true ]; then
        JWT_SECRET="$DEFAULT_JWT_SECRET"
        echo -e "${GREEN}✓ Using generated JWT secret${NC}"
    else
        prompt_input "Press Enter to use default, or type your own (min 32 chars): " USER_JWT_SECRET
        if [ -z "$USER_JWT_SECRET" ]; then
            JWT_SECRET="$DEFAULT_JWT_SECRET"
            echo -e "${GREEN}✓ Using generated JWT secret${NC}"
        else
            if [ ${#USER_JWT_SECRET} -lt 32 ]; then
                echo -e "${RED}✗ Error: JWT secret must be at least 32 characters!${NC}"
                exit 1
            fi
            JWT_SECRET="$USER_JWT_SECRET"
            echo -e "${GREEN}✓ Using custom JWT secret${NC}"
        fi
    fi
    
    echo ""
    
    # Generate Encryption Key (exactly 32 characters)
    echo -e "${YELLOW}Encryption Key Configuration${NC}"
    echo "A secure random encryption key has been generated."
    echo -e "Default value: ${GREEN}$DEFAULT_ENCRYPTION_KEY${NC}"
    if [ "$NONINTERACTIVE" = true ]; then
        ENCRYPTION_KEY="$DEFAULT_ENCRYPTION_KEY"
        echo -e "${GREEN}✓ Using generated encryption key${NC}"
    else
        prompt_input "Press Enter to use default, or type your own (exactly 32 chars): " USER_ENCRYPTION_KEY
        if [ -z "$USER_ENCRYPTION_KEY" ]; then
            ENCRYPTION_KEY="$DEFAULT_ENCRYPTION_KEY"
            echo -e "${GREEN}✓ Using generated encryption key${NC}"
        else
            if [ ${#USER_ENCRYPTION_KEY} -ne 32 ]; then
                echo -e "${RED}✗ Error: Encryption key must be exactly 32 characters!${NC}"
                exit 1
            fi
            ENCRYPTION_KEY="$USER_ENCRYPTION_KEY"
            echo -e "${GREEN}✓ Using custom encryption key${NC}"
        fi
    fi
    
    echo ""
    echo "Creating configuration file..."
    ALLOWED_ORIGINS_YAML=$(build_allowed_origins_yaml)
    
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
    
    echo -e "${GREEN}✓ Configuration created successfully${NC}"
fi

# macOS marks downloaded, unsigned binaries with quarantine metadata. If that
# flag reaches launchd, Gatekeeper can block TermiScope before it starts.
if [ "$TARGET_OS" = "darwin" ] && command -v xattr >/dev/null 2>&1; then
    echo "Clearing macOS quarantine attributes..."
    xattr -dr com.apple.quarantine "$INSTALL_DIR" 2>/dev/null || true
fi

# 7. Service
echo "Configuring service..."
if [ "$TARGET_OS" = "darwin" ]; then
    INSTALL_DIR_XML=$(printf '%s' "$INSTALL_DIR" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' -e "s/'/\&apos;/g")
    cat > "$MACOS_PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${MACOS_PLIST_ID}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${INSTALL_DIR_XML}/TermiScope</string>
  </array>
  <key>WorkingDirectory</key>
  <string>${INSTALL_DIR_XML}</string>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${INSTALL_DIR_XML}/logs/launchd.out.log</string>
  <key>StandardErrorPath</key>
  <string>${INSTALL_DIR_XML}/logs/launchd.err.log</string>
</dict>
</plist>
EOF
    chmod 644 "$MACOS_PLIST_PATH"
    chown root:wheel "$MACOS_PLIST_PATH" 2>/dev/null || true
    echo -e "${GREEN}Starting service...${NC}"
    launchctl bootstrap system "$MACOS_PLIST_PATH" 2>/dev/null || launchctl load -w "$MACOS_PLIST_PATH"
    launchctl kickstart -k "system/${MACOS_PLIST_ID}" 2>/dev/null || true
elif [ "$SERVICE_MANAGER" = "openrc" ]; then
    echo "正在配置 OpenRC 服务..."
    OPENRC_INSTALL_DIR=$(escape_service_path "$INSTALL_DIR")
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
    rc-service "$SERVICE_NAME" start
else
    # systemd
    SYSTEMD_INSTALL_DIR=$(escape_systemd_path "$INSTALL_DIR")
    # WorkingDirectory 直接读取路径，不进行 ExecStart 的引号和反斜线解码。
    SYSTEMD_WORKING_DIR=$(printf '%s' "$INSTALL_DIR" | sed 's/%/%%/g')
    mkdir -p /etc/systemd/system
    cat > "/etc/systemd/system/$SERVICE_NAME.service" <<EOF
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
    echo -e "${GREEN}Starting service...${NC}"
    systemctl start "$SERVICE_NAME"
fi

echo -e "${GREEN}=== Installation Complete ===${NC}"
echo -e "Dashboard: http://<your-ip>:${PORT:-8080}"
echo -e "Config: $INSTALL_DIR/configs/config.yaml"

# 8. Done — no cleanup needed. Online installs already removed temp files,
# and offline/source installs should never delete their source directory.
echo -e "${GREEN}Installation finished successfully.${NC}"
