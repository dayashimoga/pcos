#!/usr/bin/env bash
# PCOS Linux / NAS Storage Node One-Command Installer
# Usage: curl -sSL https://.../install.sh | bash -s -- <pairing-code>
set -e

SERVER_URL="${PCOS_SERVER_URL:-https://pcos-control-plane.dayashimoga.workers.dev}"
PAIRING_CODE="$1"
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/pcos"

echo "=========================================================="
echo "   ☁ PCOS - Personal Cloud Operating System"
echo "       Linux & NAS Storage Node Installer"
echo "=========================================================="

if [ -z "$PAIRING_CODE" ]; then
    echo "1. Open PCOS Web: ${SERVER_URL}/#/devices"
    echo "2. Click [Connect Physical Device] to get your 6-digit code."
    read -p "Enter 6-digit pairing code > " PAIRING_CODE
fi

mkdir -p "$CONFIG_DIR"
mkdir -p "$HOME/PCOS"

# Detect binary
if [ -f "./target/release/pcos-agent" ]; then
    cp "./target/release/pcos-agent" "$INSTALL_DIR/pcos-agent"
elif [ -f "./pcos-agent" ]; then
    cp "./pcos-agent" "$INSTALL_DIR/pcos-agent"
fi
chmod +x "$INSTALL_DIR/pcos-agent"

echo "Enrolling device with PCOS Edge Control Plane..."
"$INSTALL_DIR/pcos-agent" --config "$CONFIG_DIR/agent.toml" enroll "$PAIRING_CODE" --server "$SERVER_URL"

# Install systemd service if available
if command -v systemctl >/dev/null 2>&1; then
    cp "$(dirname "$0")/pcos-agent.service" /etc/systemd/system/pcos-agent.service
    systemctl daemon-reload
    systemctl enable --now pcos-agent
    echo "✓ PCOS Agent background service installed and started via systemd."
else
    # Fallback to nohup / background process for minimal NAS environments
    nohup "$INSTALL_DIR/pcos-agent" --config "$CONFIG_DIR/agent.toml" --daemon > /var/log/pcos-agent.log 2>&1 &
    echo "✓ PCOS Agent started in background (PID: $!)."
fi

echo "=========================================================="
echo "🎉 PCOS Storage Node is active and connected!"
echo "=========================================================="
