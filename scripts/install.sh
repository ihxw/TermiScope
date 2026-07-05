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
    echo "  -y, --non-interactive   No prompts"
    echo "  -h, --help              Show help"
}

# Parse arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --install-dir)
            if [ $# -lt 2 ]; then
                echo "Missing value for --install-dir"
                exit 1
            fi
            INSTALL_DIR="$2"
            shift 2
            ;;
        --port)
            if [ $# -lt 2 ]; then
                echo "Missing value for --port"
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

# Auto-detect non-interactive mode (piped stdin, cron, etc.)
if [ ! -t 0 ]; then
    NONINTERACTIVE=true
fi

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Detect OS.
UNAME_OS=$(uname -s)
case "$UNAME_OS" in
    Linux) TARGET_OS="linux" ;;
    Darwin) TARGET_OS="darwin" ;;
    *) echo -e "${RED}Unsupported OS: $UNAME_OS${NC}"; exit 1 ;;
esac

# Check if we're on Alpine
IS_ALPINE=false
if [ "$TARGET_OS" = "linux" ] && [ -f "/etc/alpine-release" ]; then
    IS_ALPINE=true
fi

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
        read -p "Install location [$DEFAULT_INSTALL_DIR]: " USER_DIR
        INSTALL_DIR=${USER_DIR:-$DEFAULT_INSTALL_DIR}
    fi
    IS_UPDATE=false
fi

echo -e "Installing to: ${GREEN}$INSTALL_DIR${NC}"

# 3. Stop Service if running
if [ "$TARGET_OS" = "darwin" ]; then
    if launchctl print "system/${MACOS_PLIST_ID}" >/dev/null 2>&1; then
        echo -e "${YELLOW}Stopping existing service...${NC}"
        launchctl bootout system "$MACOS_PLIST_PATH" 2>/dev/null || \
            launchctl bootout "system/${MACOS_PLIST_ID}" 2>/dev/null || true
    fi
elif [ "$IS_ALPINE" = true ]; then
    if rc-service $SERVICE_NAME status >/dev/null 2>&1; then
        echo -e "${YELLOW}Stopping existing service...${NC}"
        rc-service $SERVICE_NAME stop 2>/dev/null || true
    fi
else
    if systemctl is-active --quiet $SERVICE_NAME 2>/dev/null; then
        echo -e "${YELLOW}Stopping existing service...${NC}"
        systemctl stop $SERVICE_NAME 2>/dev/null || true
    fi
fi

# 4. Create Directories
echo "Creating directories..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/configs"
mkdir -p "$INSTALL_DIR/data"
mkdir -p "$INSTALL_DIR/logs"
mkdir -p "$INSTALL_DIR/agents"
mkdir -p "$INSTALL_DIR/web" 

# 5. Copy Files / Download Logic
# Locate source directory (portable: works on GNU and BusyBox readlink)
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

# Check if we are in Offline Mode (Binary and Web Dist exist locally)
LOCAL_BINARY=$(find "$PACKAGE_DIR" -maxdepth 1 -name "TermiScope*" -type f -not -name "*.*" | head -n 1)
if [ -n "$LOCAL_BINARY" ] && [ -d "$PACKAGE_DIR/web/dist" ]; then
    echo "Files found locally. Proceeding with offline installation..."
else
    echo "Complete files (binary or web/dist) not found locally. Initiating Online Installation from GitHub..."
    
    # Dependencies check
    command -v curl >/dev/null 2>&1 || { echo >&2 "Error: curl is required but not installed."; exit 1; }
    command -v tar >/dev/null 2>&1 || { echo >&2 "Error: tar is required but not installed."; exit 1; }

    # Detect Arch
    ARCH=$(uname -m)
    case $ARCH in
        x86_64|amd64) ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
        armv7l|armv6l) ARCH="arm" ;;
        *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
    esac
    OS="$TARGET_OS"

    echo "Detected System: $OS/$ARCH"

    # Get Latest Version Information
    echo "Fetching latest version info..."
    LATEST_URL="https://api.github.com/repos/ihxw/TermiScope/releases/latest"
    RESPONSE=$(curl -fsSL "$LATEST_URL")
    
    # Extract version tag for display
    VERSION=$(echo "$RESPONSE" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    
    if [ -z "$VERSION" ]; then
        echo "Error: Could not retrieve latest version from GitHub."
        # Print response for debugging if needed, or just exit
        exit 1
    fi
    
    echo "Latest Version: $VERSION"

    # Find the correct asset URL for this OS and architecture.
    # Pattern: ends with linux-amd64.tar.gz, darwin-arm64.tar.gz, etc.
    SEARCH_PATTERN="${OS}-${ARCH}\.tar\.gz$"
    DOWNLOAD_URL=$(echo "$RESPONSE" | grep -o 'https://[^"]*' | grep -E "$SEARCH_PATTERN" | head -n 1)

    if [ -z "$DOWNLOAD_URL" ]; then
        echo "Error: Could not find a release asset for: $OS-$ARCH"
        exit 1
    fi

    # Extract filename from URL
    FILE_NAME=$(basename "$DOWNLOAD_URL")
    
    TMP_DIR=$(mktemp -d)
    echo "Downloading from $DOWNLOAD_URL ..."
    curl -fL -o "$TMP_DIR/$FILE_NAME" "$DOWNLOAD_URL"
    
    if [ $? -ne 0 ]; then
        echo "Error: Download failed."
        exit 1
    fi

    echo "Extracting..."
    tar -xzf "$TMP_DIR/$FILE_NAME" -C "$TMP_DIR"
    
    # Find the extracted directory
    EXTRACTED_DIR=$(find "$TMP_DIR" -maxdepth 1 -type d -name "TermiScope*" | head -n 1)

    if [ -z "$EXTRACTED_DIR" ]; then
        EXTRACTED_DIR="$TMP_DIR"
    fi

    # Copy files directly from the extracted package instead of re-running install.sh
    # (to avoid infinite recursion since the inner script is the same as this one)
    echo "Installing files from downloaded package..."

    # Copy binary
    if [ -f "$EXTRACTED_DIR/TermiScope" ]; then
        cp -f "$EXTRACTED_DIR/TermiScope" "$INSTALL_DIR/"
        chmod +x "$INSTALL_DIR/TermiScope"
    else
        echo "Error: TermiScope binary not found in downloaded package."
        rm -rf "$TMP_DIR"
        exit 1
    fi

    # Copy web assets
    if [ -d "$EXTRACTED_DIR/web/dist" ]; then
        rm -rf "$INSTALL_DIR/web/dist"
        cp -r "$EXTRACTED_DIR/web/dist" "$INSTALL_DIR/web/"
    else
        echo "Error: web/dist not found in downloaded package."
        rm -rf "$TMP_DIR"
        exit 1
    fi

    # Copy agents
    if [ -d "$EXTRACTED_DIR/agents" ]; then
        cp -r "$EXTRACTED_DIR/agents/"* "$INSTALL_DIR/agents/" 2>/dev/null || true
    fi

    # Copy script templates
    if [ -d "$EXTRACTED_DIR/scripts" ]; then
        mkdir -p "$INSTALL_DIR/scripts"
        cp -r "$EXTRACTED_DIR/scripts/"* "$INSTALL_DIR/scripts/" 2>/dev/null || true
    fi

    # Copy uninstall script to root for convenience
    if [ -f "$EXTRACTED_DIR/scripts/uninstall.sh" ]; then
        cp -f "$EXTRACTED_DIR/scripts/uninstall.sh" "$INSTALL_DIR/"
        chmod +x "$INSTALL_DIR/uninstall.sh"
    fi

    rm -rf "$TMP_DIR"
    # Skip the offline copy section below — files are already installed
    SKIP_LOCAL_COPY=true
fi

if [ "$SKIP_LOCAL_COPY" != "true" ]; then
echo "Copying binary..."
if [ -f "$PACKAGE_DIR/TermiScope" ]; then
    cp -f "$PACKAGE_DIR/TermiScope" "$INSTALL_DIR/"
else
    BINARY=$(find "$PACKAGE_DIR" -maxdepth 1 -name "TermiScope*" -type f -not -name "*.*" | head -n 1)
    if [ -n "$BINARY" ]; then
         cp -f "$BINARY" "$INSTALL_DIR/TermiScope"
    else
         echo -e "${RED}Error: Binary 'TermiScope' not found in source directory!${NC}"
         exit 1
    fi
fi
chmod +x "$INSTALL_DIR/TermiScope"

echo "Copying web assets..."
rm -rf "$INSTALL_DIR/web/dist"
if [ -d "$PACKAGE_DIR/web/dist" ]; then
    cp -r "$PACKAGE_DIR/web/dist" "$INSTALL_DIR/web/"
else
    echo -e "${RED}Error: web/dist directory not found in source!${NC}"
    exit 1
fi

echo "Copying agents..."
cp -r "$PACKAGE_DIR/agents/"* "$INSTALL_DIR/agents/" 2>/dev/null || true

echo "Copying uninstall script..."
if [ -f "$PACKAGE_DIR/scripts/uninstall.sh" ]; then
    cp -f "$PACKAGE_DIR/scripts/uninstall.sh" "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/uninstall.sh"
    # Create symlink for easier access? Optional.
elif [ -f "$PACKAGE_DIR/uninstall.sh" ]; then
    cp -f "$PACKAGE_DIR/uninstall.sh" "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/uninstall.sh"
fi
fi

# 6. Config Handling
if [ -f "$INSTALL_DIR/configs/config.yaml" ]; then
    echo -e "${YELLOW}Preserving existing configuration.${NC}"
    
    # Read port from existing config
    PORT=$(grep -E '^\s*port:' "$INSTALL_DIR/configs/config.yaml" | sed 's/.*port:\s*//' | tr -d ' ')
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
        read -p "Enter server port [3000]: " USER_PORT
        PORT=${USER_PORT:-3000}
    fi
    
    echo -e "Set port to ${GREEN}$PORT${NC}"
    
    echo ""
    echo -e "${GREEN}=== Security Keys Configuration ===${NC}"
    echo ""
    
    command -v openssl >/dev/null 2>&1 || { echo >&2 "Error: openssl is required but not installed."; exit 1; }

    # Generate JWT Secret (32+ characters)
    DEFAULT_JWT_SECRET=$(openssl rand -base64 48 | tr -d '\n' | cut -c1-32)
    echo -e "${YELLOW}JWT Secret Configuration${NC}"
    echo "A secure random JWT secret has been generated."
    echo -e "Default value: ${GREEN}$DEFAULT_JWT_SECRET${NC}"
    if [ "$NONINTERACTIVE" = true ]; then
        JWT_SECRET="$DEFAULT_JWT_SECRET"
        echo -e "${GREEN}✓ Using generated JWT secret${NC}"
    else
        read -p "Press Enter to use default, or type your own (min 32 chars): " USER_JWT_SECRET
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
    DEFAULT_ENCRYPTION_KEY=$(openssl rand -base64 48 | tr -d '\n' | cut -c1-32)
    echo -e "${YELLOW}Encryption Key Configuration${NC}"
    echo "A secure random encryption key has been generated."
    echo -e "Default value: ${GREEN}$DEFAULT_ENCRYPTION_KEY${NC}"
    if [ "$NONINTERACTIVE" = true ]; then
        ENCRYPTION_KEY="$DEFAULT_ENCRYPTION_KEY"
        echo -e "${GREEN}✓ Using generated encryption key${NC}"
    else
        read -p "Press Enter to use default, or type your own (exactly 32 chars): " USER_ENCRYPTION_KEY
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
    
    cat > "$INSTALL_DIR/configs/config.yaml" <<EOF
server:
  port: $PORT
  mode: release
  allowed_origins: []
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
elif [ "$IS_ALPINE" = true ]; then
    # Alpine using OpenRC
    echo "Detected Alpine Linux, using OpenRC..."
    cat > "/etc/init.d/$SERVICE_NAME" <<EOF
#!/sbin/openrc-run

name="TermiScope Server"
description="$name - Universal monitoring and SSH management platform"
command="$INSTALL_DIR/TermiScope"
pidfile="/var/run/$SERVICE_NAME.pid"
command_background=true

depend() {
    use dns
    need net
}

start_pre() {
    checkpath -d -o root:root 755 /var/run
}
EOF
    chmod +x "/etc/init.d/$SERVICE_NAME"
    rc-service $SERVICE_NAME start
    rc-service $SERVICE_NAME add
else
    # systemd
    cat > "/etc/systemd/system/$SERVICE_NAME.service" <<EOF
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
    systemctl enable $SERVICE_NAME
    echo -e "${GREEN}Starting service...${NC}"
    systemctl start $SERVICE_NAME
fi

echo -e "${GREEN}=== Installation Complete ===${NC}"
echo -e "Dashboard: http://<your-ip>:${PORT:-8080}"
echo -e "Config: $INSTALL_DIR/configs/config.yaml"

# 8. Done — no cleanup needed. Online installs already removed temp files,
# and offline/source installs should never delete their source directory.
echo -e "${GREEN}Installation finished successfully.${NC}"
