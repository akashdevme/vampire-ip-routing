#!/usr/bin/env bash
# ==============================================================================
# WireGuard Client Setup Script (Run on PRIVATE / NAT VPS)
# Tested on: Ubuntu 20.04/22.04/24.04, Debian 11/12
# ==============================================================================
set -e

if [ "$EUID" -ne 0 ]; then
  echo "[-] Please run as root: sudo bash wireguard-client.sh"
  exit 1
fi

echo "[+] Installing WireGuard..."
apt-get update -y
apt-get install -y wireguard

WG_DIR="/etc/wireguard"
mkdir -p "$WG_DIR"
cd "$WG_DIR"
umask 077

if [ ! -f "client_private.key" ]; then
  echo "[+] Generating Client WireGuard keys..."
  wg genkey | tee client_private.key | wg pubkey > client_public.key
fi

CLIENT_PRIV=$(cat client_private.key)
CLIENT_PUB=$(cat client_public.key)

echo "=========================================================="
echo "YOUR CLIENT PUBLIC KEY: $CLIENT_PUB"
echo "(Provide this key to the Public VPS setup script)"
echo "=========================================================="

read -rp "Enter Public VPS IPv4 address: " PUBLIC_SERVER_IP
read -rp "Enter Server Public Key: " SERVER_PUB

cat <<EOF > "$WG_DIR/wg0.conf"
[Interface]
Address = 10.0.0.2/24
PrivateKey = $CLIENT_PRIV

[Peer]
PublicKey = $SERVER_PUB
Endpoint = $PUBLIC_SERVER_IP:51820
AllowedIPs = 10.0.0.0/24
# Keep NAT session active
PersistentKeepalive = 25
EOF

echo "[+] Starting and enabling WireGuard..."
systemctl enable wg-quick@wg0
systemctl restart wg-quick@wg0

echo ""
echo "[✓] Client Setup Complete!"
echo "[+] Testing connection to Public VPS..."
sleep 2
ping -c 3 10.0.0.1 || echo "[!] Could not ping 10.0.0.1 yet. Please ensure the Public VPS is running and port 51820 UDP is open."
