#!/usr/bin/env bash
# ==============================================================================
# Install & Setup FRP Server (Run on PUBLIC VPS)
# ==============================================================================
set -e

if [ "$EUID" -ne 0 ]; then
  echo "[-] Please run as root: sudo bash install-frps.sh"
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

cp frps "$INSTALL_DIR/"
mkdir -p "$CONFIG_DIR"

if [ ! -f "$CONFIG_DIR/frps.toml" ]; then
  TOKEN=$(openssl rand -hex 16)
  cat <<EOF > "$CONFIG_DIR/frps.toml"
bindPort = 7000
auth.token = "$TOKEN"

webServer.addr = "0.0.0.0"
webServer.port = 7500
webServer.user = "admin"
webServer.password = "admin$TOKEN"
EOF
  echo "[+] Generated token in $CONFIG_DIR/frps.toml: $TOKEN"
fi

cat <<EOF > /etc/systemd/system/frps.service
[Unit]
Description=FRP Server
After=network.target

[Service]
Type=simple
ExecStart=$INSTALL_DIR/frps -c $CONFIG_DIR/frps.toml
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now frps

rm -rf "$TMP_DIR"

echo "=========================================================="
echo "[✓] FRP Server is running!"
echo "Port: 7000"
echo "Config file: $CONFIG_DIR/frps.toml"
echo "Token: $(grep 'auth.token' $CONFIG_DIR/frps.toml)"
echo "=========================================================="
