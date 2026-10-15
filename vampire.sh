#!/usr/bin/env bash
# ==============================================================================
#  _   _                 _           _   _           _   _             
# | | | | __ _ _ __ ___ | |__   ___ | | | | ___  ___| |_(_)_ __   __ _ 
# | | | |/ _` | '_ ` _ \| '_ \ / _ \| | | |/ _ \/ __| __| | '_ \ / _` |
# \ \_/ / (_| | | | | | | |_) |  __/| |_| | (_) \__ \ |_| | | | | (_| |
#  \___/ \__,_|_| |_| |_|_.__/ \___| \___/ \___/|___/\__|_|_| |_|\__, |
#                                                                 |___/ 
#  VAMPIRE HOSTING - ALL-PORTS INSTANT PUBLIC IP ROUTER
#  Forward ALL 65,535 TCP/UDP Ports to your Private High-RAM VPS in 1 Command!
# ==============================================================================

set -e

VAMPIRE_DIR="/etc/vampire"
WG_DIR="/etc/wireguard"
BIN_DIR="/usr/local/bin"
WG_PORT=51820
GATEWAY_IP="10.0.0.1"
NODE_IP="10.0.0.2"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

banner() {
  echo -e "${PURPLE}${BOLD}"
  cat << "EOF"
  __      __                 _              _    _           _   _             
  \ \    / /                (_)            | |  | |         | | (_)            
   \ \  / /_ _ _ __ ___  _ __  _ _ __ ___  | |__| | ___  ___| |_ _ _ __   __ _ 
    \ \/ / _` | '_ ` _ \| '_ \| | '__/ _ \ |  __  |/ _ \/ __| __| | '_ \ / _` |
     \  / (_| | | | | | | |_) | | | |  __/ | |  | | (_) \__ \ |_| | | | | (_| |
      \/ \__,_|_| |_| |_| .__/|_|_|  \___| |_|  |_|\___/|___/\__|_|_| |_|\__, |
                        | |                                                __/ |
                        |_|   ALL-PORTS INSTANT PUBLIC IP ROUTER          |___/ 
EOF
  echo -e "${CYAN}  Route ALL 65,535 Ports from Public IPv4 to your Private High-RAM VPS!${NC}"
  echo -e "================================================================================\n"
}

check_root() {
  if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[ERROR] Please run as root:${NC} sudo bash $0 $@"
    exit 1
  fi
}

detect_public_interface() {
  local iface
  iface=$(ip route show default 2>/dev/null | awk '{print $5}' | head -n1)
  if [ -z "$iface" ]; then
    iface=$(ip link show | grep -v 'lo:' | grep 'state UP' | awk -F': ' '{print $2}' | head -n1)
  fi
  echo "${iface:-eth0}"
}

detect_public_ip() {
  local ip
  ip=$(curl -s4 --connect-timeout 3 https://api.ipify.org || \
       curl -s4 --connect-timeout 3 https://icanhazip.com || \
       curl -s4 --connect-timeout 3 https://ip.sb || \
       ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K\S+')
  echo "$ip"
}

detect_ssh_port() {
  local port
  port=$(ss -tlpn 2>/dev/null | grep -E 'sshd|ssh' | awk '{print $4}' | awk -F':' '{print $NF}' | head -n1)
  if [ -z "$port" ] && [ -f /etc/ssh/sshd_config ]; then
    port=$(grep -E '^Port ' /etc/ssh/sshd_config | awk '{print $2}' | head -n1)
  fi
  echo "${port:-22}"
}

install_packages() {
  echo -e "${CYAN}[+] Installing WireGuard and routing tools...${NC}"
  if command -v apt-get >/dev/null 2>&1; then
    DEBIAN_FRONTEND=noninteractive apt-get update -qq >/dev/null 2>&1
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq wireguard iptables iptables-persistent curl wget net-tools >/dev/null 2>&1
  elif command -v yum >/dev/null 2>&1; then
    yum install -y epel-release >/dev/null 2>&1 || true
    yum install -y wireguard-tools iptables curl wget >/dev/null 2>&1
  elif command -v pacman >/dev/null 2>&1; then
    pacman -Sy --noconfirm wireguard-tools iptables curl wget >/dev/null 2>&1
  fi
}

enable_ip_forwarding() {
  echo -e "${CYAN}[+] Enabling kernel IPv4 forwarding...${NC}"
  sed -i '/net.ipv4.ip_forward/d' /etc/sysctl.conf 2>/dev/null || true
  echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
  sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1
}

# ==============================================================================
# GATEWAY SETUP (Public IPv4 VPS)
# ==============================================================================
setup_gateway() {
  local custom_domain=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --domain) custom_domain="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  banner
  echo -e "${BOLD}${GREEN}=== SETTING UP VAMPIRE PUBLIC GATEWAY ===${NC}"
  echo -e "${YELLOW}All incoming traffic (except SSH & WireGuard) will route to your Private VPS.${NC}\n"

  install_packages
  enable_ip_forwarding

  PUBLIC_IFACE=$(detect_public_interface)
  PUBLIC_IP=$(detect_public_ip)
  SSH_PORT=$(detect_ssh_port)

  if [ -z "$custom_domain" ]; then
    read -rp "Enter domain/hostname (press ENTER to use $PUBLIC_IP): " custom_domain
  fi
  CONNECT_HOST="${custom_domain:-$PUBLIC_IP}"


  echo -e "${GREEN}[+] Public Interface:${NC} ${BOLD}$PUBLIC_IFACE${NC}"
  echo -e "${GREEN}[+] Public IPv4:${NC}      ${BOLD}$PUBLIC_IP${NC}"
  echo -e "${GREEN}[+] Detected SSH Port:${NC} ${BOLD}$SSH_PORT (Protected - will not be forwarded)${NC}"

  mkdir -p "$WG_DIR" "$VAMPIRE_DIR"
  chmod 700 "$WG_DIR"
  cd "$WG_DIR"

  # Generate server keys
  wg genkey | tee server_private.key | wg pubkey > server_public.key
  SERVER_PRIV=$(cat server_private.key)
  SERVER_PUB=$(cat server_public.key)

  # Pre-generate client keys right now so client needs ZERO manual steps!
  wg genkey | tee client_private.key | wg pubkey > client_public.key
  CLIENT_PRIV=$(cat client_private.key)
  CLIENT_PUB=$(cat client_public.key)

  # Configure wg0.conf on Gateway
  # NAT RULES:
  # 1. Protect SSH port on the public VPS (so you NEVER get locked out!)
  # 2. Protect WireGuard port (51820)
  # 3. Forward ALL other TCP and UDP ports (1-65535) directly to 10.0.0.2!
  cat <<EOF > "$WG_DIR/wg0.conf"
[Interface]
Address = $GATEWAY_IP/24
ListenPort = $WG_PORT
PrivateKey = $SERVER_PRIV

# Firewall & All-Ports Forwarding Rules
PostUp = iptables -A FORWARD -i $PUBLIC_IFACE -o wg0 -d $NODE_IP -j ACCEPT
PostUp = iptables -A FORWARD -i wg0 -o $PUBLIC_IFACE -j ACCEPT
PostUp = iptables -t nat -A PREROUTING -i $PUBLIC_IFACE -p tcp --dport $SSH_PORT -j ACCEPT
PostUp = iptables -t nat -A PREROUTING -i $PUBLIC_IFACE -p udp --dport $WG_PORT -j ACCEPT
PostUp = iptables -t nat -A PREROUTING -i $PUBLIC_IFACE -p tcp -j DNAT --to-destination $NODE_IP
PostUp = iptables -t nat -A PREROUTING -i $PUBLIC_IFACE -p udp -j DNAT --to-destination $NODE_IP
PostUp = iptables -t nat -A POSTROUTING -o wg0 -j MASQUERADE
PostUp = iptables -t nat -A POSTROUTING -o $PUBLIC_IFACE -j MASQUERADE

PostDown = iptables -D FORWARD -i $PUBLIC_IFACE -o wg0 -d $NODE_IP -j ACCEPT
PostDown = iptables -D FORWARD -i wg0 -o $PUBLIC_IFACE -j ACCEPT
PostDown = iptables -t nat -D PREROUTING -i $PUBLIC_IFACE -p tcp --dport $SSH_PORT -j ACCEPT
PostDown = iptables -t nat -D PREROUTING -i $PUBLIC_IFACE -p udp --dport $WG_PORT -j ACCEPT
PostDown = iptables -t nat -D PREROUTING -i $PUBLIC_IFACE -p tcp -j DNAT --to-destination $NODE_IP
PostDown = iptables -t nat -D PREROUTING -i $PUBLIC_IFACE -p udp -j DNAT --to-destination $NODE_IP
PostDown = iptables -t nat -D POSTROUTING -o wg0 -j MASQUERADE
PostDown = iptables -t nat -D POSTROUTING -o $PUBLIC_IFACE -j MASQUERADE

[Peer]
PublicKey = $CLIENT_PUB
AllowedIPs = $NODE_IP/32
EOF

  chmod 600 "$WG_DIR/wg0.conf"

  systemctl stop wg-quick@wg0 2>/dev/null || true
  systemctl enable --now wg-quick@wg0
  systemctl restart wg-quick@wg0

  # Install vampire command helper
  cp "$0" "$BIN_DIR/vampire" 2>/dev/null || true
  chmod +x "$BIN_DIR/vampire" 2>/dev/null || true

  echo -e "\n${GREEN}${BOLD}✓ VAMPIRE GATEWAY IS RUNNING AND READY!${NC}\n"
  echo -e "${CYAN}================================================================================${NC}"
  echo -e "${BOLD}${YELLOW}COPY & PASTE THIS EXACT 1-COMMAND ON YOUR PRIVATE HIGH-RAM VPS:${NC}\n"
  echo -e "${GREEN}${BOLD}curl -sSL https://iproute.vampirenodes.in | sudo bash -s -- node --server $CONNECT_HOST --server-key \"$SERVER_PUB\" --client-key \"$CLIENT_PRIV\"${NC}"
  echo -e "\n${CYAN}(Or if vampire.sh is already on your private VPS, run:)${NC}"
  echo -e "${GREEN}${BOLD}sudo bash vampire.sh node --server $CONNECT_HOST --server-key \"$SERVER_PUB\" --client-key \"$CLIENT_PRIV\"${NC}"
  echo -e "${CYAN}================================================================================${NC}"
  echo -e "\n${BOLD}Routing Details:${NC}"
  echo -e "  • Gateway Host:    ${GREEN}$CONNECT_HOST${NC} ($PUBLIC_IP)"
  echo -e "  • Protected SSH:   ${YELLOW}Port $SSH_PORT${NC} (Remains accessible on Public VPS)"
  echo -e "  • Forwarded Ports: ${GREEN}ALL OTHER PORTS (1 - 65535, TCP & UDP)${NC} -> Private VPS"
  echo -e "================================================================================\n"
}

# ==============================================================================
# NODE SETUP (Private / Non-Public High-RAM VPS)
# ==============================================================================
setup_node() {
  local server_ip=""
  local server_key=""
  local client_key=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --server) server_ip="$2"; shift 2 ;;
      --server-key) server_key="$2"; shift 2 ;;
      --client-key) client_key="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  banner
  echo -e "${BOLD}${GREEN}=== CONNECTING VAMPIRE PRIVATE NODE ===${NC}"
  echo -e "${YELLOW}Linking this high-RAM machine to Public IPv4 ($server_ip)...${NC}\n"

  if [ -z "$server_ip" ] || [ -z "$server_key" ] || [ -z "$client_key" ]; then
    echo -e "${RED}[ERROR] Missing arguments!${NC}"
    echo "Usage: sudo bash vampire.sh node --server <PUBLIC_IP> --server-key <KEY> --client-key <KEY>"
    exit 1
  fi

  install_packages
  mkdir -p "$WG_DIR" "$VAMPIRE_DIR"
  chmod 700 "$WG_DIR"

  cat <<EOF > "$WG_DIR/wg0.conf"
[Interface]
Address = $NODE_IP/24
PrivateKey = $client_key

[Peer]
PublicKey = $server_key
Endpoint = $server_ip:$WG_PORT
AllowedIPs = $GATEWAY_IP/32
PersistentKeepalive = 25
EOF

  chmod 600 "$WG_DIR/wg0.conf"

  systemctl stop wg-quick@wg0 2>/dev/null || true
  systemctl enable --now wg-quick@wg0
  systemctl restart wg-quick@wg0

  # Install vampire command helper
  cp "$0" "$BIN_DIR/vampire" 2>/dev/null || true
  chmod +x "$BIN_DIR/vampire" 2>/dev/null || true

  echo -e "\n${CYAN}[+] Testing tunnel link to Gateway ($GATEWAY_IP)...${NC}"
  sleep 2
  if ping -c 3 -W 2 "$GATEWAY_IP" >/dev/null 2>&1; then
    echo -e "${GREEN}${BOLD}✓ LINK ESTABLISHED! PING SUCCESSFUL!${NC}\n"
    echo -e "${CYAN}================================================================================${NC}"
    echo -e "${BOLD}${GREEN}CONGRATULATIONS! ALL 65,535 PORTS ARE NOW ROUTED!${NC}"
    echo -e "${CYAN}================================================================================${NC}"
    echo -e "Every service you run on this private high-RAM VPS is now immediately accessible"
    echo -e "on your Public IPv4: ${BOLD}${GREEN}$server_ip${NC}"
    echo -e ""
    echo -e "Examples:"
    echo -e "  • Web Server (Port 80/443)    → http://$server_ip / https://$server_ip"
    echo -e "  • Minecraft (Port 25565)      → $server_ip:25565"
    echo -e "  • Game/App Server (e.g. 7777) → $server_ip:7777"
    echo -e "  • Panel / Docker (Port 8080)  → http://$server_ip:8080"
    echo -e "  • Any port you open works automatically with ZERO configuration!"
    echo -e "${CYAN}================================================================================${NC}\n"
  else
    echo -e "${YELLOW}[!] Tunnel started, but ping test to $GATEWAY_IP timed out.${NC}"
    echo -e "Make sure UDP Port $WG_PORT is allowed in your Public VPS cloud firewall / security groups."
  fi
}

# ==============================================================================
# STATUS & UTILITIES
# ==============================================================================
show_status() {
  banner
  echo -e "${BOLD}WireGuard Interface Status:${NC}"
  if command -v wg >/dev/null 2>&1; then
    wg show || echo "No active WireGuard interfaces."
  fi
  echo -e "\n${BOLD}Systemd Service:${NC}"
  systemctl status wg-quick@wg0 --no-pager -l | head -n 10
}

uninstall_vampire() {
  banner
  echo -e "${RED}[+] Uninstalling Vampire IP Router...${NC}"
  systemctl stop wg-quick@wg0 2>/dev/null || true
  systemctl disable wg-quick@wg0 2>/dev/null || true
  rm -f "$WG_DIR/wg0.conf" "$BIN_DIR/vampire"
  echo -e "${GREEN}[✓] Vampire successfully uninstalled.${NC}"
}

# ==============================================================================
# MAIN DISPATCHER
# ==============================================================================
check_root

case "$1" in
  gateway|server)
    shift
    setup_gateway "$@"
    ;;
  node|client)
    shift
    setup_node "$@"
    ;;
  status)
    show_status
    ;;
  uninstall)
    uninstall_vampire
    ;;
  *)
    banner
    echo -e "${BOLD}USAGE:${NC}"
    echo -e "  ${CYAN}sudo bash vampire.sh gateway${NC}     Run on PUBLIC IPv4 VPS to setup the Gateway"
    echo -e "  ${CYAN}sudo bash vampire.sh node ...${NC}    Run on PRIVATE High-RAM VPS to connect"
    echo -e "  ${CYAN}sudo vampire status${NC}              Check connection and tunnel status"
    echo -e "  ${CYAN}sudo vampire uninstall${NC}           Remove Vampire and reset firewall"
    echo -e "================================================================================\n"
    ;;
esac
