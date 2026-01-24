#!/bin/bash
set -e

# Default settings
DEFAULT_INSTALL_DIR="/opt/termiscope"
SERVICE_NAME="termiscope"

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Check root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Please run as root${NC}"
  exit 1
fi

echo -e "${GREEN}=== TermiScope Installer ===${NC}"

# 2. Determine Install Directory
if [ -d "$DEFAULT_INSTALL_DIR" ]; then
    echo -e "${YELLOW}Detected existing installation at $DEFAULT_INSTALL_DIR${NC}"
    INSTALL_DIR="$DEFAULT_INSTALL_DIR"
    IS_UPDATE=true
else
    # Prompt with default
    read -p "Install location [$DEFAULT_INSTALL_DIR]: " USER_DIR
    INSTALL_DIR=${USER_DIR:-$DEFAULT_INSTALL_DIR}
    IS_UPDATE=false
fi

echo -e "Installing to: ${GREEN}$INSTALL_DIR${NC}"

# 3. Stop Service if running
if systemctl is-active --quiet $SERVICE_NAME; then
    echo -e "${YELLOW}Stopping existing service...${NC}"
    systemctl stop $SERVICE_NAME
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
SOURCE_DIR=$(dirname "$(readlink -f "$0")")

# Check if we are in Offline Mode (Binary exists locally)
if [ -f "$SOURCE_DIR/TermiScope" ]; then
    echo "Files found locally. Proceeding with offline installation..."
else
    echo "Binary not found locally. Initiating Online Installation..."
    
    # Dependencies check
    command -v curl >/dev/null 2>&1 || { echo >&2 "Error: curl is required but not installed."; exit 1; }
    command -v tar >/dev/null 2>&1 || { echo >&2 "Error: tar is required but not installed."; exit 1; }

    # Detect Arch
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)  ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
    esac
    OS="linux"

    echo "Detected System: $OS/$ARCH"

    # Get Latest Version Information
    echo "Fetching latest version info..."
    LATEST_URL="https://api.github.com/repos/ihxw/TermiScope/releases/latest"
    RESPONSE=$(curl -s $LATEST_URL)
    
    # Extract version tag for display
    VERSION=$(echo "$RESPONSE" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    
    if [ -z "$VERSION" ]; then
        echo "Error: Could not retrieve latest version from GitHub."
        # Print response for debugging if needed, or just exit
        exit 1
    fi
    
    echo "Latest Version: $VERSION"

    # Find the correct asset URL for this architecture
    # Pattern: ends with linux-amd64.tar.gz or linux-arm64.tar.gz
    SEARCH_PATTERN="linux-${ARCH}\.tar\.gz"
    DOWNLOAD_URL=$(echo "$RESPONSE" | grep -o 'https://[^"]*' | grep -E "$SEARCH_PATTERN" | head -n 1)

    if [ -z "$DOWNLOAD_URL" ]; then
        echo "Error: Could not find a release asset for architecture: linux-$ARCH"
        exit 1
    fi

    # Extract filename from URL
    FILE_NAME=$(basename "$DOWNLOAD_URL")
    
    TMP_DIR=$(mktemp -d)
    echo "Downloading from $DOWNLOAD_URL ..."
    curl -L -o "$TMP_DIR/$FILE_NAME" "$DOWNLOAD_URL"
    
    if [ $? -ne 0 ]; then
        echo "Error: Download failed."
        exit 1
    fi

    echo "Extracting..."
    tar -xzf "$TMP_DIR/$FILE_NAME" -C "$TMP_DIR"
    
    # Find the extracted directory (it should provide TermiScope binary)
    # We look for a directory that contains the 'TermiScope' binary or 'install.sh'
    # Start by guessing the pattern TermiScope*
    EXTRACTED_DIR=$(find "$TMP_DIR" -maxdepth 1 -type d -name "TermiScope*" | head -n 1)

    if [ -z "$EXTRACTED_DIR" ]; then
        # If no subdirectory found, assume flattened
        EXTRACTED_DIR="$TMP_DIR"
    fi

    # Run the inner install script
    echo "Running installer from downloaded package..."
    if [ -f "$EXTRACTED_DIR/install.sh" ]; then
        bash "$EXTRACTED_DIR/install.sh"
        rm -rf "$TMP_DIR"
        exit 0
    else
        echo "Error: install.sh not found in extracted package."
        ls -R "$TMP_DIR"
        exit 1
    fi
fi

echo "Copying binary..."
if [ -f "$SOURCE_DIR/TermiScope" ]; then
    cp -f "$SOURCE_DIR/TermiScope" "$INSTALL_DIR/"
else
    BINARY=$(find "$SOURCE_DIR" -maxdepth 1 -name "TermiScope*" -type f -not -name "*.*" | head -n 1)
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
if [ -d "$SOURCE_DIR/web/dist" ]; then
    cp -r "$SOURCE_DIR/web/dist" "$INSTALL_DIR/web/"
else
    echo -e "${RED}Error: web/dist directory not found in source!${NC}"
    exit 1
fi

echo "Copying agents..."
cp -r "$SOURCE_DIR/agents/"* "$INSTALL_DIR/agents/" 2>/dev/null || true

echo "Copying uninstall script..."
if [ -f "$SOURCE_DIR/uninstall.sh" ]; then
    cp -f "$SOURCE_DIR/uninstall.sh" "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/uninstall.sh"
    # Create symlink for easier access? Optional.
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
    if [ -f "$SOURCE_DIR/configs/config.yaml" ]; then
        cp "$SOURCE_DIR/configs/config.yaml" "$INSTALL_DIR/configs/"
        
        # Prompt for Port
        read -p "Enter server port [8080]: " USER_PORT
        PORT=${USER_PORT:-8080}
        
        # Update Port in config
        sed -i "s/port: .*/port: $PORT/" "$INSTALL_DIR/configs/config.yaml"
        echo -e "Set port to ${GREEN}$PORT${NC}"
        
        echo ""
        echo -e "${GREEN}=== Security Keys Configuration ===${NC}"
        echo ""
        
        # Generate JWT Secret (32+ characters)
        DEFAULT_JWT_SECRET=$(openssl rand -base64 48 | tr -d '\n' | cut -c1-32)
        echo -e "${YELLOW}JWT Secret Configuration${NC}"
        echo "A secure random JWT secret has been generated."
        echo -e "Default value: ${GREEN}$DEFAULT_JWT_SECRET${NC}"
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
        
        echo ""
        
        # Generate Encryption Key (exactly 32 characters)
        DEFAULT_ENCRYPTION_KEY=$(openssl rand -base64 48 | tr -d '\n' | cut -c1-32)
        echo -e "${YELLOW}Encryption Key Configuration${NC}"
        echo "A secure random encryption key has been generated."
        echo -e "Default value: ${GREEN}$DEFAULT_ENCRYPTION_KEY${NC}"
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
        
        echo ""
        echo "Updating configuration file..."
        
        # Update JWT secret in config
        sed -i "s/jwt_secret: \".*\"/jwt_secret: \"$JWT_SECRET\"/" "$INSTALL_DIR/configs/config.yaml"
        
        # Update encryption key in config
        sed -i "s/encryption_key: \".*\"/encryption_key: \"$ENCRYPTION_KEY\"/" "$INSTALL_DIR/configs/config.yaml"
        
        echo -e "${GREEN}✓ Configuration updated with security keys${NC}"
    else
        echo -e "${RED}Warning: Default config not found in package!${NC}"
    fi
fi

# 7. Systemd Service
echo "Configuring systemd service..."
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

echo -e "${GREEN}=== Installation Complete ===${NC}"
echo -e "Dashboard: http://<your-ip>:${PORT:-8080}"
echo -e "Config: $INSTALL_DIR/configs/config.yaml"

# 8. Cleanup Prompt
read -p "Clean up installation temporary files? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Removing $SOURCE_DIR ..."
    # Be careful not to delete system root if running from strange place
    if [[ "$SOURCE_DIR" != "/" && "$SOURCE_DIR" != "/root" && "$SOURCE_DIR" != "/home" ]]; then
       rm -rf "$SOURCE_DIR"
       echo "Cleanup complete."
    else
       echo "Skipping cleanup (unsafe source directory)."
    fi
fi
