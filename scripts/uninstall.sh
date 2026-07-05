#!/bin/bash
SERVICE_NAME="termiscope"
DEFAULT_INSTALL_DIR="/opt/termiscope"
MACOS_PLIST_ID="com.termiscope.server"
MACOS_PLIST_PATH="/Library/LaunchDaemons/${MACOS_PLIST_ID}.plist"

if readlink -f "$0" >/dev/null 2>&1; then
    CURRENT_DIR=$(dirname "$(readlink -f "$0")")
else
    CURRENT_DIR=$(cd "$(dirname "$0")" && pwd)
fi

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Please run as root${NC}"
  exit 1
fi

UNAME_OS=$(uname -s)
case "$UNAME_OS" in
    Linux) TARGET_OS="linux" ;;
    Darwin) TARGET_OS="darwin" ;;
    *) echo -e "${RED}Unsupported OS: $UNAME_OS${NC}"; exit 1 ;;
esac

# Determine Install Directory
if [ -f "$CURRENT_DIR/TermiScope" ] && [ -d "$CURRENT_DIR/configs" ]; then
    # Running from actual install dir
    INSTALL_DIR="$CURRENT_DIR"
elif [ -d "$DEFAULT_INSTALL_DIR" ]; then
    # Running from standalone script/package, but found default install
    echo -e "${YELLOW}Detected installation at $DEFAULT_INSTALL_DIR${NC}"
    INSTALL_DIR="$DEFAULT_INSTALL_DIR"
else
    # Ask user
    read -p "Enter installation directory [$DEFAULT_INSTALL_DIR]: " USER_DIR
    INSTALL_DIR=${USER_DIR:-$DEFAULT_INSTALL_DIR}
fi

if [ ! -d "$INSTALL_DIR" ]; then
    echo -e "${RED}Error: Directory $INSTALL_DIR does not exist.${NC}"
    exit 1
fi

echo -e "${RED}WARNING: This will remove TermiScope and ALL data (logs, database, configs) from $INSTALL_DIR${NC}"
read -p "Are you sure you want to continue? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

echo "Stopping service..."
if [ "$TARGET_OS" = "darwin" ]; then
    if launchctl print "system/${MACOS_PLIST_ID}" >/dev/null 2>&1; then
        launchctl bootout system "$MACOS_PLIST_PATH" 2>/dev/null || \
            launchctl bootout "system/${MACOS_PLIST_ID}" 2>/dev/null || true
    fi
    rm -f "$MACOS_PLIST_PATH"
else
    if systemctl is-active --quiet $SERVICE_NAME; then
        systemctl stop $SERVICE_NAME
    fi
    systemctl disable $SERVICE_NAME 2>/dev/null || true
    rm -f "/etc/systemd/system/$SERVICE_NAME.service"
    systemctl daemon-reload
fi

echo "Removing files from $INSTALL_DIR..."
# Safety check: Don't rm -rf /
if [[ "$INSTALL_DIR" != "/" && "$INSTALL_DIR" != "/root" && "$INSTALL_DIR" != "/home" ]]; then
    rm -rf "$INSTALL_DIR"
    echo "Files removed."
else
    echo -e "${RED}Skipping unsafe delete of $INSTALL_DIR${NC}"
fi

echo -e "${GREEN}Uninstallation complete.${NC}"
