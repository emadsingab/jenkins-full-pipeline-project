#!/bin/bash

# Stop script when any command fails that's useful for troubleshooting and avoiding run until the end and get error
set -euo pipefail

# Nexus latest version from Sonatype downloads page
NEXUS_VERSION="3.93.2-01"
NEXUS_FILE="nexus-${NEXUS_VERSION}-linux-x86_64.tar.gz"
NEXUS_URL="https://download.sonatype.com/nexus/3/${NEXUS_FILE}"

INSTALL_DIR="/opt/nexus"
NEXUS_USER="nexus"
TMP_DIR="/tmp/nexus-install"

# Install required packages
sudo apt update
sudo apt install -y wget tar

# Optional Java install
# New Nexus Linux archive includes its own platform-specific JDK,
# but keeping Java 17 installed is fine for compatibility/tools.
sudo apt install -y openjdk-17-jdk

# Create nexus user if not exists
if ! id "$NEXUS_USER" >/dev/null 2>&1; then
  sudo useradd --system --no-create-home "$NEXUS_USER"
fi

# Prepare directories
sudo mkdir -p "$INSTALL_DIR"
sudo rm -rf "$TMP_DIR"
sudo mkdir -p "$TMP_DIR"

cd "$TMP_DIR"

# Download Nexus
sudo wget "$NEXUS_URL" -O "$NEXUS_FILE"

# Extract directly into /opt/nexus
sudo tar xzvf "$NEXUS_FILE" -C "$INSTALL_DIR"

# Create stable symlink
sudo ln -sfn "$INSTALL_DIR/nexus-${NEXUS_VERSION}" "$INSTALL_DIR/current"

# Set nexus run user
echo 'run_as_user="nexus"' | sudo tee "$INSTALL_DIR/current/bin/nexus.rc" >/dev/null

# Permissions
sudo chown -R "$NEXUS_USER:$NEXUS_USER" "$INSTALL_DIR"

# Create systemd service
sudo tee /etc/systemd/system/nexus.service >/dev/null <<EOT
[Unit]
Description=Sonatype Nexus Repository Manager
After=network.target

[Service]
Type=forking
LimitNOFILE=65536
ExecStart=${INSTALL_DIR}/current/bin/nexus start
ExecStop=${INSTALL_DIR}/current/bin/nexus stop
User=${NEXUS_USER}
Restart=on-abort
TimeoutSec=600

[Install]
WantedBy=multi-user.target
EOT

# Reload and start service
sudo systemctl daemon-reload
sudo systemctl enable nexus
sudo systemctl restart nexus

echo "Nexus installed successfully."
echo "URL: http://SERVER_IP:8081"
echo "Initial admin password:"
echo "sudo cat ${INSTALL_DIR}/sonatype-work/nexus3/admin.password"