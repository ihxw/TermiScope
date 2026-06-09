#!/bin/bash
# TermiScope orphan agent cleanup (host was deleted on server; host_id={{HOST_ID}})
# Run on the remote machine as root. No server callback is performed.

set -e

echo "========================================="
echo " TermiScope orphan agent cleanup"
echo " (deleted host_id={{HOST_ID}} on server)"
echo "========================================="
echo ""

OS=$(uname -s | tr '[:upper:]' '[:lower:]')
INSTALL_DIR="/opt/termiscope/agent"
SERVICE_NAME="termiscope-agent"

case $OS in
    linux)
        if command -v systemctl &> /dev/null; then
            INIT_SYSTEM="systemd"
            SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
        elif [ -f /etc/openwrt_release ]; then
            INIT_SYSTEM="procd"
            SERVICE_FILE="/etc/init.d/${SERVICE_NAME}"
        elif command -v initctl &> /dev/null; then
            INIT_SYSTEM="upstart"
            SERVICE_FILE="/etc/init/${SERVICE_NAME}.conf"
        elif [ -f /etc/rc.conf ]; then
            INIT_SYSTEM="freebsd"
            SERVICE_FILE="/usr/local/etc/rc.d/${SERVICE_NAME}"
            SERVICE_NAME="termiscope_agent"
        else
            INIT_SYSTEM="sysv"
            SERVICE_FILE="/etc/init.d/${SERVICE_NAME}"
        fi
        ;;
    darwin)
        INSTALL_DIR="$HOME/Library/TermiScope/agent"
        SERVICE_FILE="$HOME/Library/LaunchAgents/com.termiscope.agent.plist"
        INIT_SYSTEM="launchd"
        ;;
    *)
        echo "Unsupported OS: $OS"
        exit 1
        ;;
esac

echo "Detected: $OS ($INIT_SYSTEM)"
echo ""

echo "[1/3] Stopping service..."
case $INIT_SYSTEM in
    systemd)
        if systemctl is-active --quiet $SERVICE_NAME 2>/dev/null; then
            sudo systemctl stop $SERVICE_NAME
        fi
        sudo systemctl disable $SERVICE_NAME 2>/dev/null || true
        ;;
    procd)
        if [ -f "$SERVICE_FILE" ]; then
            $SERVICE_FILE stop || true
            $SERVICE_FILE disable || true
        fi
        ;;
    upstart)
        sudo initctl stop $SERVICE_NAME 2>/dev/null || true
        ;;
    freebsd)
        sudo service $SERVICE_NAME stop 2>/dev/null || true
        sudo sysrc ${SERVICE_NAME}_enable=NO 2>/dev/null || true
        ;;
    sysv)
        if [ -f "$SERVICE_FILE" ]; then
            sudo $SERVICE_FILE stop || true
            if command -v update-rc.d &> /dev/null; then
                sudo update-rc.d -f $SERVICE_NAME remove
            elif command -v chkconfig &> /dev/null; then
                sudo chkconfig $SERVICE_NAME off
                sudo chkconfig --del $SERVICE_NAME
            fi
        fi
        ;;
    launchd)
        launchctl unload $SERVICE_FILE 2>/dev/null || true
        ;;
esac

echo "[2/3] Removing service unit..."
if [ -f "$SERVICE_FILE" ]; then
    if [ "$OS" = "darwin" ]; then
        rm -f "$SERVICE_FILE"
    else
        sudo rm -f "$SERVICE_FILE"
    fi
fi
if [ "$INIT_SYSTEM" = "systemd" ]; then
    sudo systemctl daemon-reload
fi

echo "[3/3] Removing install directory..."
if [ -d "$INSTALL_DIR" ]; then
    if [ "$OS" = "darwin" ]; then
        rm -rf "$INSTALL_DIR"
    else
        sudo rm -rf "$INSTALL_DIR"
    fi
fi

# Legacy cron / shell loop installs
if crontab -l 2>/dev/null | grep -q termiscope; then
    echo "Removing termiscope entries from user crontab..."
    crontab -l 2>/dev/null | grep -v termiscope | crontab - 2>/dev/null || true
fi

echo ""
echo "Done. This machine should stop hitting /api/monitor/pulse for host_id={{HOST_ID}}."
