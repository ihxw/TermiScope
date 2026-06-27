#!/bin/bash
# Install TermiScope from a local offline package (no GitHub download).
# Never overwrites existing configs/config.yaml or files under data/.
#
# Run from extracted package root:
#   sudo ./scripts/install_local.sh -y
set -e

DEFAULT_INSTALL_DIR="/opt/termiscope"
SERVICE_NAME="termiscope"
NONINTERACTIVE=false
INSTALL_DIR=""
USER_PORT=""

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

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
    --install-dir) INSTALL_DIR="$2"; shift 2 ;;
    --port) USER_PORT="$2"; shift 2 ;;
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

INSTALL_DIR="${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}"

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

if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
  echo -e "${YELLOW}Stopping $SERVICE_NAME...${NC}"
  systemctl stop "$SERVICE_NAME" || true
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
  echo "Installing agents (merge, no delete)..."
  cp -an "$PACKAGE_DIR/agents/." "$INSTALL_DIR/agents/" 2>/dev/null || \
    cp -a "$PACKAGE_DIR/agents/." "$INSTALL_DIR/agents/" 2>/dev/null || true
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
  PORT=$(grep -E '^\s*port:' "$INSTALL_DIR/configs/config.yaml" | head -1 | sed -E 's/.*port:\s*//' | tr -d ' ')
  [ -z "$PORT" ] && PORT=3000
else
  if [ -n "$USER_PORT" ]; then
    PORT="$USER_PORT"
  elif [ "$NONINTERACTIVE" = true ]; then
    PORT=3000
  else
    read -p "Server port [3000]: " PORT
    PORT=${PORT:-3000}
  fi

  JWT_SECRET=$(openssl rand -base64 48 | tr -d '\n' | cut -c1-32)
  ENCRYPTION_KEY=$(openssl rand -base64 48 | tr -d '\n' | cut -c1-32)

  cat > "$INSTALL_DIR/configs/config.yaml" <<EOF
server:
  port: $PORT
  mode: release
  allowed_origins:
    - "*"
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

echo "Installing systemd unit..."
cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=TermiScope Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/TermiScope
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

echo -e "${GREEN}=== Installation complete ===${NC}"
echo -e "URL:    http://<server-ip>:${PORT}"
echo -e "Config: $INSTALL_DIR/configs/config.yaml"
echo -e "Data:   $INSTALL_DIR/data/ (unchanged if existed)"
echo -e "Logs:   $INSTALL_DIR/logs/ (unchanged if existed)"
echo -e "Repair: sudo $INSTALL_DIR/repair_database.sh --data-dir $INSTALL_DIR/data"
