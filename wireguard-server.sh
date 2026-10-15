#!/usr/bin/env bash
# ==============================================================================
# WireGuard Server Setup Script (Run on PUBLIC IPv4 VPS)
# Tested on: Ubuntu 20.04/22.04/24.04, Debian 11/12
# ==============================================================================
set -e

if [ "$EUID" -ne 0 ]; then
  echo "[-] Please run as root: sudo bash wireguard-server.sh"
  exit 1
fi

echo "[+] Updating packages and installing WireGuard & iptables..."
apt-get update -y
apt-get install -y wireguard iptables iptables-persistent qrencode

# 1. Enable IPv4 forwarding in kernel
echo "[+] Enabling IPv4 IP forwarding..."
sed -i '/net.ipv4.ip_forward/d' /etc/sysctl.conf
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p /etc/sysctl.conf

# 2. Detect public network interface
DEFAULT_IFACE=$(ip route show default | awk '{print $5}' | head -n1)
if [ -z "$DEFAULT_IFACE" ]; then
  DEFAULT_IFACE="eth0"
fi
echo "[+] Detected default public interface: $DEFAULT_IFACE"

# 3. Ask for port forwarding details
read -rp "Enter ports to forward (TCP/UDP, comma-separated, e.g., 80,443,25565): " FORWARD_PORTS

# 4. Generate keys
WG_DIR="/etc/wireguard"
mkdir -p "$WG_DIR"
cd "$WG_DIR"
umask 077

if [ ! -f "server_private.key" ]; then
  echo "[+] Generating Server WireGuard keys..."
  wg genkey | tee server_private.key | wg pubkey > server_public.key
fi

SERVER_PRIV=$(cat server_private.key)
SERVER_PUB=$(cat server_public.key)

echo "=========================================================="
echo "Server Public Key: $SERVER_PUB"
echo "=========================================================="
read -rp "Enter the Client's Public Key (generated on Private VPS): " CLIENT_PUB

# Build iptables rules for each port
POSTUP_RULES=""
POSTDOWN_RULES=""

IFS=',' read -ra ADDR <<< "$FORWARD_PORTS"
for PORT in "${ADDR[@]}"; do
  PORT=$(echo "$PORT" | xargs)
  if [ -n "$PORT" ]; then
    POSTUP_RULES+="PostUp = iptables -A FORWARD -i $DEFAULT_IFACE -o wg0 -p tcp --dport $PORT -d 10.0.0.2 -j ACCEPT"$'\n'
    POSTUP_RULES+="PostUp = iptables -A FORWARD -i $DEFAULT_IFACE -o wg0 -p udp --dport $PORT -d 10.0.0.2 -j ACCEPT"$'\n'
    POSTUP_RULES+="PostUp = iptables -t nat -A PREROUTING -i $DEFAULT_IFACE -p tcp --dport $PORT -j DNAT --to-destination 10.0.0.2:$PORT"$'\n'
    POSTUP_RULES+="PostUp = iptables -t nat -A PREROUTING -i $DEFAULT_IFACE -p udp --dport $PORT -j DNAT --to-destination 10.0.0.2:$PORT"$'\n'

    POSTDOWN_RULES+="PostDown = iptables -D FORWARD -i $DEFAULT_IFACE -o wg0 -p tcp --dport $PORT -d 10.0.0.2 -j ACCEPT"$'\n'
    POSTDOWN_RULES+="PostDown = iptables -D FORWARD -i $DEFAULT_IFACE -o wg0 -p udp --dport $PORT -d 10.0.0.2 -j ACCEPT"$'\n'
    POSTDOWN_RULES+="PostDown = iptables -t nat -D PREROUTING -i $DEFAULT_IFACE -p tcp --dport $PORT -j DNAT --to-destination 10.0.0.2:$PORT"$'\n'
    POSTDOWN_RULES+="PostDown = iptables -t nat -D PREROUTING -i $DEFAULT_IFACE -p udp --dport $PORT -j DNAT --to-destination 10.0.0.2:$PORT"$'\n'
  fi
done

POSTUP_RULES+="PostUp = iptables -t nat -A POSTROUTING -o wg0 -j MASQUERADE"$'\n'
POSTDOWN_RULES+="PostDown = iptables -t nat -D POSTROUTING -o wg0 -j MASQUERADE"$'\n'

# Write wg0.conf
cat <<EOF > "$WG_DIR/wg0.conf"
[Interface]
Address = 10.0.0.1/24
ListenPort = 51820
PrivateKey = $SERVER_PRIV

# Firewall / Port forwarding rules
$POSTUP_RULES
$POSTDOWN_RULES

[Peer]
PublicKey = $CLIENT_PUB
AllowedIPs = 10.0.0.2/32
EOF

echo "[+] Starting and enabling WireGuard service..."
systemctl enable wg-quick@wg0
systemctl restart wg-quick@wg0

echo ""
echo "[✓] Public VPS Setup Complete!"
echo "Server Public Key: $SERVER_PUB"
echo "WireGuard Port: 51820 (Ensure UDP port 51820 is open in your cloud firewall/security groups)"
