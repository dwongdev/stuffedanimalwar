#!/bin/bash

# StuffedAnimalWar Pi Setup - Installation Script
# Jaemzware LLC
#
# This script configures a Raspberry Pi for dual-mode operation:
# - AP mode for "in the woods" use (no internet needed)
# - Home WiFi mode for local network access

set -e  # Exit on error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAW_DIR="/home/jaemzware/stuffedanimalwar"
AA_DIR="/home/jaemzware/analogarchive"

echo "=========================================="
echo "StuffedAnimalWar Pi Setup"
echo "Jaemzware LLC"
echo "=========================================="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run with sudo: sudo ./install.sh"
    exit 1
fi

echo "[1/12] Updating system packages..."
apt update
apt upgrade -y

echo "[2/12] Installing system dependencies..."
apt install -y nginx avahi-daemon network-manager jq samba samba-common-bin

echo "[3/12] Configuring Samba (SMB) for network access..."
# Backup original smb.conf if it exists
if [ -f /etc/samba/smb.conf ]; then
    cp /etc/samba/smb.conf /etc/samba/smb.conf.backup
fi

# Create Samba configuration
cat > /etc/samba/smb.conf << 'EOF'
[global]
   workgroup = WORKGROUP
   server string = StuffedAnimalWar Pi
   netbios name = stuffedanimalwar
   security = user
   map to guest = bad user
   dns proxy = no

[jaemzware]
   path = /home/jaemzware
   browseable = yes
   read only = no
   create mask = 0775
   directory mask = 0775
   valid users = jaemzware
   force user = jaemzware
   force group = jaemzware
EOF

# Set Samba password for jaemzware user (same as SSH password)
echo "  - Setting Samba password for jaemzware user..."
echo "  - You'll be prompted to enter a password for SMB access"
smbpasswd -a jaemzware

# Enable and start Samba
systemctl enable smbd
systemctl restart smbd

echo "[4/12] Installing Node.js..."
if ! command -v node &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt install -y nodejs
    echo "Node.js $(node --version) installed"
else
    echo "Node.js $(node --version) already installed"
fi

echo "[5/12] Installing Node.js dependencies for StuffedAnimalWar..."
cd "$SAW_DIR"
sudo -u jaemzware npm install

echo "[6/12] Installing Node.js dependencies for AnalogArchive..."
if [ -d "$AA_DIR" ]; then
    cd "$AA_DIR"
    sudo -u jaemzware npm install
    echo "AnalogArchive dependencies installed"
else
    echo "AnalogArchive not found, skipping"
fi

echo "[7/12] Stopping conflicting services..."
systemctl stop apache2 2>/dev/null || true
systemctl disable apache2 2>/dev/null || true

echo "[8/12] Generating SSL certificates..."
cd "$SCRIPT_DIR"
sudo -u jaemzware bash "$SCRIPT_DIR/generate-certs.sh"

echo "[9/12] Configuring NetworkManager AP connection..."
# Create AP connection profile
nmcli connection delete StuffedAnimalWAP 2>/dev/null || true
nmcli connection add type wifi ifname wlan0 con-name StuffedAnimalWAP autoconnect no ssid StuffedAnimalWAP
nmcli connection modify StuffedAnimalWAP 802-11-wireless.mode ap 802-11-wireless.band bg ipv4.method shared
nmcli connection modify StuffedAnimalWAP wifi-sec.key-mgmt wpa-psk wifi-sec.psk "stuffedanimal"

echo "[10/12] Installing nginx configurations..."
cp "$SCRIPT_DIR/nginx-stuffedanimalwar.conf" /etc/nginx/sites-available/
ln -sf /etc/nginx/sites-available/nginx-stuffedanimalwar.conf /etc/nginx/sites-enabled/

# Remove default nginx site
rm -f /etc/nginx/sites-enabled/default

# Test nginx config
nginx -t

echo "[11/12] Installing WiFi Manager and application services..."
cp "$SCRIPT_DIR/wifi-manager.service" /etc/systemd/system/
chmod +x "$SCRIPT_DIR/wifi-manager.sh"

cp "$SCRIPT_DIR/stuffedanimalwar.service" /etc/systemd/system/

# Install analogarchive service if it exists
if [ -d "$AA_DIR" ]; then
    echo "  - Installing AnalogArchive service..."
    cp "$SCRIPT_DIR/analogarchive.service" /etc/systemd/system/
fi

echo "[12/12] Setting hostname and enabling services..."
hostnamectl set-hostname stuffedanimalwar

systemctl daemon-reload
systemctl enable wifi-manager.service
systemctl enable nginx
systemctl enable stuffedanimalwar.service

if [ -f "/etc/systemd/system/analogarchive.service" ]; then
    systemctl enable analogarchive.service
fi

echo ""
echo "=========================================="
echo "Installation complete!"
echo "=========================================="
echo ""
echo "The Pi will start in AP mode on first boot."
echo "  - WiFi Name: StuffedAnimalWAP"
echo "  - Password: stuffedanimal"
echo "  - Setup URL: https://stuffedanimalwar.local/setup"
echo ""
echo "Network access via SMB:"
echo "  - Server: \\\\stuffedanimalwar.local\\jaemzware"
echo "  - macOS: smb://stuffedanimalwar.local/jaemzware"
echo "  - Username: jaemzware"
echo ""
echo "Reboot now? (y/n)"
read -r response
if [[ "$response" =~ ^[Yy]$ ]]; then
    reboot
fi