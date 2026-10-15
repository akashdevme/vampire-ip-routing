#!/usr/bin/env bash
# ==============================================================================
# Install & Setup FRP Client (Run on PRIVATE / NAT VPS)
# ==============================================================================
set -e

if [ "$EUID" -ne 0 ]; then
  echo "[-] Please run as root: sudo bash install-frpc.sh"
  exit 1
fi

FRP_VERSION="0.58.1"
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/frp"

echo "[+] Downloading FRP v${FRP_VERSION}..."
ARCH=$(uname -m)
case "$ARCH" in
  x86_64) FRP_ARCH="amd64" ;;
  aarch64) FRP_ARCH="arm64" ;;
  *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

TMP_DIR=$(mktemp -d)
cd "$TMP_DIR"
wget -q "https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_${FRP_ARCH}.tar.gz"
tar -zxf "frp_${FRP_VERSION}_linux_${FRP_ARCH}.tar.gz"
cd "frp_${FRP_VERSION}_linux_${FRP_ARCH}"

cp frpc "$INSTALL_DIR/"
mkdir -p "$CONFIG_DIR"

read -rp "Enter Public VPS IP: " PUBLIC_IP
read -rp "Enter auth.token (from frps.toml on Public VPS): " TOKEN
read -rp "Enter ports to forward from Private to Public (e.g. 80,443): " PORTS

cat <<EOF > "$CONFIG_DIR/frpc.toml"
serverAddr = "$PUBLIC_IP"
serverPort = 7000
auth.token = "$TOKEN"
EOF

IFS=',' read -ra ADDR <<< "$PORTS"
for PORT in "${ADDR[@]}"; do
  PORT=$(echo "$PORT" | xargs)
  if [ -n "$PORT" ]; then
    cat <<EOF >> "$CONFIG_DIR/frpc.toml"

[[proxies]]
name = "forward-$PORT"
type = "tcp"
localIP = "127.0.0.1"
localPort = $PORT
remotePort = $PORT
EOF
  fi
done

cat <<EOF > /etc/systemd/system/frpc.service
[Unit]
Description=FRP Client
After=network.target

[Service]
Type=simple
ExecStart=$INSTALL_DIR/frpc -c $CONFIG_DIR/frpc.toml
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now frpc

rm -rf "$TMP_DIR"

echo "=========================================================="
echo "[✓] FRP Client is running!"
echo "Forwarded Ports: $PORTS"
echo "Config file: $CONFIG_DIR/frpc.toml"
echo "Status: systemctl status frpc"
echo "=========================================================="
