#!/usr/bin/env bash
# ==============================================================================
#  _   _                 _           _   _           _   _
# | | | | __ _ _ __ ___ | |__   ___ | | | | ___  ___| |_(_)_ __   __ _
# | | | |/ _` | '_ ` _ \| '_ \ / _ \| | | |/ _ \/ __| __| | '_ \ / _` |
# \ \_/ / (_| | | | | | | |_) |  __/| |_| | (_) \__ \ |_| | | | | (_| |
#  \___/ \__,_|_| |_| |_|_.__/ \___| \___/ \___/|___/\__|_|_| |_|\__, |
#                                                                  |___/
#  VAMPIRE HOSTING v2.1.0 -- 1-COMMAND 24/7 HIGH-PERFORMANCE IP ROUTER
#  Route ANY Non-Public High-RAM VPS to Public IPv4 with Built-in AI Support
#  GitHub: https://github.com/akashdevme/vampire-ip-routing
# ==============================================================================

set -euo pipefail

VAMPIRE_DIR="/etc/vampire"
BIN_DIR="/usr/local/bin"
FRP_VERSION="0.58.1"
DEFAULT_BIND_PORT="20000"
DASHBOARD_PORT="7500"
VAMPIRE_VERSION="2.1.0"
INSTALL_URL="https://iproute.vampirenodes.in"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

banner() {
  echo -e "${PURPLE}${BOLD}"
  cat << "BANNER"
  __   __                    _              _    _           _   _
  \ \ / /_ _ _ __ ___  _ __(_)_ __   ___  | |__| | ___  ___| |_(_)_ __   __ _
   \ V / _` | '_ ` _ \| '_ \ | '__/ _ \ | '_ \| |/ _ \/ __| __| | '_ \ / _` |
    | | (_| | | | | | | |_) | | | |  __/ | | | | | (_) \__ \ |_| | | | | (_| |
    |_|\__,_|_| |_| |_| .__/|_|_|  \___| |_| |_|_|\___/|___/\__|_|_| |_|\__, |
                       |_|   24/7 PUBLIC IPv4 ROUTER v2.1                 |___/
BANNER
  echo -e "${CYAN}  Bat High-RAM Private VPS to Public IPv4 in 1 command  |  Gemini AI built-in${NC}"
  echo -e "================================================================================\n"
}

log_info()  { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[!!]${NC} $*"; }
log_error() { echo -e "${RED}[XX]${NC} $*" >&2; }
log_step()  { echo -e "${CYAN}[->]${NC} $*"; }

check_root() {
  if [ "$EUID" -ne 0 ]; then
    log_error "Please run as root: sudo vampire $*"
    exit 1
  fi
}

detect_arch() {
  case "$(uname -m)" in
    x86_64)        echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    armv7l)        echo "arm"   ;;
    *)             echo "amd64" ;;
  esac
}

detect_public_ip() {
  curl -s4 --connect-timeout 4 https://api.ipify.org 2>/dev/null || \
  curl -s4 --connect-timeout 4 https://icanhazip.com  2>/dev/null || \
  curl -s4 --connect-timeout 4 https://ip.sb           2>/dev/null || \
  ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K\S+' || \
  echo "127.0.0.1"
}

install_dependencies() {
  mkdir -p "$BIN_DIR" "$VAMPIRE_DIR"
  log_step "Installing system dependencies..."
  if command -v apt-get >/dev/null 2>&1; then
    DEBIAN_FRONTEND=noninteractive apt-get update -qq >/dev/null 2>&1 || true
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
      curl wget tar openssl python3 jq net-tools >/dev/null 2>&1 || true
  elif command -v yum >/dev/null 2>&1; then
    yum install -y -q curl wget tar openssl python3 jq net-tools >/dev/null 2>&1 || true
  elif command -v apk >/dev/null 2>&1; then
    apk add --quiet curl wget tar openssl python3 jq net-tools >/dev/null 2>&1 || true
  fi
}

download_frp() {
  local mode="$1"
  if [ -f "$BIN_DIR/$mode" ]; then
    log_info "Core engine ${mode} already installed."
    return 0
  fi
  log_step "Downloading Vampire Core Engine (${mode} v${FRP_VERSION})..."
  local arch; arch=$(detect_arch)
  local tmp_dir; tmp_dir=$(mktemp -d)
  local url="https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_${arch}.tar.gz"

  wget -qO "$tmp_dir/frp.tar.gz" "$url" 2>/dev/null || \
  curl -sSL "$url" -o "$tmp_dir/frp.tar.gz" || {
    log_error "Failed to download ${mode}. Check your internet connection."
    rm -rf "$tmp_dir"; exit 1
  }

  tar -zxf "$tmp_dir/frp.tar.gz" -C "$tmp_dir"
  cp "$tmp_dir/frp_${FRP_VERSION}_linux_${arch}/$mode" "$BIN_DIR/"
  chmod +x "$BIN_DIR/$mode"
  rm -rf "$tmp_dir"
  log_info "Installed $mode to $BIN_DIR/$mode"
}

install_vampire_cmd() {
  if [ ! -f "$BIN_DIR/vampire" ]; then
    log_step "Installing vampire shortcut command..."
    curl -sSL "$INSTALL_URL" -o "$BIN_DIR/vampire" 2>/dev/null || \
      cp "$0" "$BIN_DIR/vampire" 2>/dev/null || true
    chmod +x "$BIN_DIR/vampire" 2>/dev/null || true
  fi
}

# ==============================================================================
# WATCHDOG
# ==============================================================================
setup_watchdog() {
  log_step "Installing Vampire auto-heal watchdog..."
  mkdir -p "$VAMPIRE_DIR"

  cat > "$VAMPIRE_DIR/watchdog.sh" << 'WATCHDOG'
#!/bin/bash
VAMPIRE_DIR="/etc/vampire"
LOG_FILE="$VAMPIRE_DIR/watchdog.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"; }

rotate_log() {
  if [ -f "$LOG_FILE" ] && [ "$(wc -l < "$LOG_FILE")" -gt 1000 ]; then
    tail -n 500 "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
  fi
}

while true; do
  rotate_log
  for svc in vampire-gateway vampire-node; do
    if systemctl is-enabled --quiet "$svc" 2>/dev/null; then
      if ! systemctl is-active --quiet "$svc"; then
        log "ALERT: $svc is DOWN. Restarting..."
        systemctl restart "$svc" && log "RECOVERED: $svc restarted OK." || log "FAILED: could not restart $svc"
      fi
    fi
  done
  sleep 30
done
WATCHDOG

  chmod +x "$VAMPIRE_DIR/watchdog.sh"

  cat > /etc/systemd/system/vampire-watchdog.service << EOF
[Unit]
Description=Vampire Hosting -- Auto Self-Heal Watchdog
After=vampire-gateway.service vampire-node.service

[Service]
Type=simple
User=root
ExecStart=/bin/bash $VAMPIRE_DIR/watchdog.sh
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now vampire-watchdog >/dev/null 2>&1
  log_info "Watchdog installed -- auto self-healing every 30 seconds!"
}

# ==============================================================================
# GATEWAY SETUP
# ==============================================================================
setup_gateway() {
  banner
  echo -e "${BOLD}${GREEN}=== SETTING UP VAMPIRE PUBLIC GATEWAY (24/7) ===${NC}"
  echo -e "${YELLOW}  All TCP/UDP traffic will route to your private high-RAM node.${NC}\n"

  install_dependencies
  download_frp "frps"
  install_vampire_cmd

  PUBLIC_IP=$(detect_public_ip)
  log_info "Detected Public IP: ${BOLD}$PUBLIC_IP${NC}"

  if [ -f "$VAMPIRE_DIR/frps.toml" ] && grep -q "auth.token" "$VAMPIRE_DIR/frps.toml"; then
    TOKEN=$(grep 'auth.token' "$VAMPIRE_DIR/frps.toml" | head -n1 | sed 's/.*= *"\(.*\)"/\1/')
    log_info "Reusing existing secure token."
  else
    TOKEN=$(openssl rand -hex 16)
    log_info "Generated new secure token."
  fi

  mkdir -p "$VAMPIRE_DIR"
  cat > "$VAMPIRE_DIR/frps.toml" << TOMLEOF
# Vampire Hosting Gateway Configuration
bindPort = $DEFAULT_BIND_PORT
auth.token = "$TOKEN"

webServer.addr = "0.0.0.0"
webServer.port = $DASHBOARD_PORT
webServer.user = "vampire"
webServer.password = "vampire123"
TOMLEOF

  cat > /etc/systemd/system/vampire-gateway.service << SVCEOF
[Unit]
Description=Vampire Hosting -- Public Gateway 24/7
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=$BIN_DIR/frps -c $VAMPIRE_DIR/frps.toml
Restart=always
RestartSec=3s
StartLimitInterval=0
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
SVCEOF

  systemctl daemon-reload
  systemctl enable --now vampire-gateway >/dev/null 2>&1
  sleep 1
  systemctl restart vampire-gateway

  cat > "$VAMPIRE_DIR/gateway.env" << ENVEOF
PUBLIC_IP=$PUBLIC_IP
TOKEN=$TOKEN
BIND_PORT=$DEFAULT_BIND_PORT
DASHBOARD_PORT=$DASHBOARD_PORT
SETUP_DATE=$(date -u +"%Y-%m-%d %H:%M UTC")
ENVEOF

  echo ""
  echo -e "${GREEN}${BOLD}[OK] VAMPIRE GATEWAY IS LIVE AND ACTIVE (24/7)!${NC}"
  echo -e "${CYAN}================================================================================${NC}"
  echo -e "${BOLD}${YELLOW}  RUN THIS 1-COMMAND ON YOUR PRIVATE HIGH-RAM VPS:${NC}"
  echo ""
  echo -e "  ${GREEN}${BOLD}curl -sSL $INSTALL_URL | sudo bash -s -- node --server $PUBLIC_IP --token $TOKEN${NC}"
  echo ""
  echo -e "  Public IP:     ${GREEN}${BOLD}$PUBLIC_IP${NC}"
  echo -e "  Control Port:  ${GREEN}$DEFAULT_BIND_PORT/TCP${NC}"
  echo -e "  Secret Token:  ${GREEN}$TOKEN${NC}"
  echo -e "  Dashboard:     ${CYAN}http://$PUBLIC_IP:$DASHBOARD_PORT${NC}  (vampire / vampire123)"
  echo -e "${CYAN}================================================================================${NC}\n"
}

# ==============================================================================
# NODE SETUP
# ==============================================================================
setup_node() {
  local server_ip="" token="" ports="80,443,25565"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --server|-s) server_ip="$2"; shift 2 ;;
      --token|-t)  token="$2";     shift 2 ;;
      --ports|-p)  ports="$2";     shift 2 ;;
      *) shift ;;
    esac
  done

  banner
  echo -e "${BOLD}${GREEN}=== SETTING UP VAMPIRE NODE (HOSTING WORKER) ===${NC}"
  echo -e "${YELLOW}  Connecting this High-RAM VPS to Public IPv4 Gateway via TCP...${NC}\n"

  if [ -z "$server_ip" ] || [ -z "$token" ]; then
    log_error "Server IP and Token are required!"
    echo "  Usage: sudo bash vampire.sh node --server <PUBLIC_IP> --token <TOKEN>"
    exit 1
  fi

  install_dependencies
  download_frp "frpc"
  install_vampire_cmd

  log_step "Configuring TCP tunnel to $server_ip:$DEFAULT_BIND_PORT ..."

  mkdir -p "$VAMPIRE_DIR"
  cat > "$VAMPIRE_DIR/frpc.toml" << TOMLEOF
# Vampire Node Client Configuration
serverAddr = "$server_ip"
serverPort = $DEFAULT_BIND_PORT
auth.token = "$token"

transport.heartbeatInterval = 10
transport.heartbeatTimeout = 30

[[proxies]]
name = "web-http"
type = "tcp"
localIP = "127.0.0.1"
localPort = 80
remotePort = 80

[[proxies]]
name = "web-https"
type = "tcp"
localIP = "127.0.0.1"
localPort = 443
remotePort = 443

[[proxies]]
name = "game-minecraft"
type = "tcp"
localIP = "127.0.0.1"
localPort = 25565
remotePort = 25565
TOMLEOF

  cat > /etc/systemd/system/vampire-node.service << SVCEOF
[Unit]
Description=Vampire Hosting -- Private Node 24/7
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=$BIN_DIR/frpc -c $VAMPIRE_DIR/frpc.toml
Restart=always
RestartSec=3s
StartLimitInterval=0
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
SVCEOF

  systemctl daemon-reload
  systemctl enable --now vampire-node >/dev/null 2>&1
  sleep 1
  systemctl restart vampire-node

  cat > "$VAMPIRE_DIR/node.env" << ENVEOF
GATEWAY_IP=$server_ip
TOKEN=$token
BIND_PORT=$DEFAULT_BIND_PORT
SETUP_DATE=$(date -u +"%Y-%m-%d %H:%M UTC")
ENVEOF

  start_test_page_silent
  sleep 2

  if systemctl is-active --quiet vampire-node; then
    echo ""
    echo -e "${GREEN}${BOLD}[OK] VAMPIRE NODE CONNECTED SUCCESSFULLY (24/7)!${NC}"
    echo -e "${CYAN}================================================================================${NC}"
    echo -e "  ${BOLD}Your Private High-RAM VPS is now LIVE on:${NC} ${GREEN}$server_ip${NC}"
    echo ""
    echo -e "  Active Default Routes:"
    echo -e "    HTTP  Port 80   -> ${GREEN}http://$server_ip${NC}"
    echo -e "    HTTPS Port 443  -> ${GREEN}https://$server_ip${NC}"
    echo -e "    Game  Port 25565-> ${GREEN}$server_ip:25565${NC}"
    echo ""
    echo -e "  Add more ports: ${YELLOW}sudo vampire add 7777${NC}"
    echo -e "  AI Support:     ${YELLOW}sudo vampire ai${NC}"
    echo -e "${CYAN}================================================================================${NC}\n"
  else
    log_error "Could not verify node. Check: journalctl -u vampire-node -n 30"
  fi
}

# ==============================================================================
# ADD PORT
# ==============================================================================
add_port() {
  local port="${1:-}" proto="${2:-both}"

  if [ -z "$port" ]; then
    echo -e "${RED}Usage: sudo vampire add <port> [tcp|udp|both]${NC}"
    echo "  Examples:"
    echo "    sudo vampire add 7777"
    echo "    sudo vampire add 30120 tcp"
    echo "    sudo vampire add 8211  udp"
    exit 1
  fi

  [ -f "$VAMPIRE_DIR/frpc.toml" ] || { log_error "Vampire Node not installed."; exit 1; }

  if grep -q "\"port-${port}-tcp\"\|\"port-${port}-udp\"" "$VAMPIRE_DIR/frpc.toml" 2>/dev/null; then
    log_warn "Port $port already configured. Restarting..."
    systemctl restart vampire-node
    log_info "Port $port active."; return 0
  fi

  log_step "Forwarding port $port ($proto)..."

  if [ "$proto" = "tcp" ] || [ "$proto" = "both" ]; then
    cat >> "$VAMPIRE_DIR/frpc.toml" << PORTEOF

# Added: $(date -u +"%Y-%m-%d %H:%M UTC")
[[proxies]]
name = "port-${port}-tcp"
type = "tcp"
localIP = "127.0.0.1"
localPort = $port
remotePort = $port
PORTEOF
  fi

  if [ "$proto" = "udp" ] || [ "$proto" = "both" ]; then
    cat >> "$VAMPIRE_DIR/frpc.toml" << PORTEOF

[[proxies]]
name = "port-${port}-udp"
type = "udp"
localIP = "127.0.0.1"
localPort = $port
remotePort = $port
PORTEOF
  fi

  systemctl restart vampire-node
  log_info "Port ${BOLD}$port ($proto)${NC} is now live 24/7!"
}

# ==============================================================================
# REMOVE PORT
# ==============================================================================
remove_port() {
  local port="${1:-}"
  [ -n "$port" ] || { echo -e "${RED}Usage: sudo vampire remove <port>${NC}"; exit 1; }
  [ -f "$VAMPIRE_DIR/frpc.toml" ] || { log_error "Vampire Node not installed."; exit 1; }

  python3 - "$VAMPIRE_DIR/frpc.toml" "$port" << 'PYEOF'
import sys, re
f = sys.argv[1]; p = sys.argv[2]
txt = open(f).read()
txt = re.sub(r'\n*# Added:.*\n(\[\[proxies\]\]\nname = "port-' + re.escape(p) + r'-(?:tcp|udp)".*?)(?=\n\[|\Z)', '', txt, flags=re.DOTALL)
txt = re.sub(r'\n*\[\[proxies\]\]\nname = "port-' + re.escape(p) + r'-(?:tcp|udp)".*?(?=\n\[|\Z)', '', txt, flags=re.DOTALL)
open(f,'w').write(txt.strip()+'\n')
print(f"Removed port {p} from config.")
PYEOF

  systemctl restart vampire-node
  log_info "Port $port removed and service restarted."
}

# ==============================================================================
# STATUS
# ==============================================================================
show_status() {
  banner
  echo -e "${BOLD}=== Vampire System Health =======================================================${NC}\n"

  local is_gw=false is_node=false

  if systemctl is-active --quiet vampire-gateway 2>/dev/null; then
    is_gw=true
    echo -e "  ${GREEN}[RUNNING]${NC} ${BOLD}Vampire Gateway${NC}  (Public IPv4 Master)"
    [ -f "$VAMPIRE_DIR/gateway.env" ] && { source "$VAMPIRE_DIR/gateway.env" 2>/dev/null || true
      echo -e "    Public IP:  ${CYAN}${PUBLIC_IP:-?}${NC}"
      echo -e "    Dashboard:  ${CYAN}http://${PUBLIC_IP:-?}:${DASHBOARD_PORT:-7500}${NC}"
    }
    echo ""
  else
    echo -e "  [STOPPED] Vampire Gateway"
  fi

  if systemctl is-active --quiet vampire-node 2>/dev/null; then
    is_node=true
    echo -e "  ${GREEN}[RUNNING]${NC} ${BOLD}Vampire Node${NC}  (Private High-RAM Worker)"
    [ -f "$VAMPIRE_DIR/node.env" ] && { source "$VAMPIRE_DIR/node.env" 2>/dev/null || true
      echo -e "    Gateway IP: ${CYAN}${GATEWAY_IP:-?}${NC}"
    }
    echo ""
    if [ -f "$VAMPIRE_DIR/frpc.toml" ]; then
      echo -e "  ${BOLD}Active Routes:${NC}"
      grep -E '^name = |^remotePort = ' "$VAMPIRE_DIR/frpc.toml" 2>/dev/null | \
        paste - - | awk '{gsub(/"/, ""); print "    * " $3 "  ->  Port " $6}' || true
      echo ""
    fi
  else
    echo -e "  [STOPPED] Vampire Node"
  fi

  systemctl is-active --quiet vampire-watchdog 2>/dev/null && \
    echo -e "  ${GREEN}[RUNNING]${NC} Vampire Watchdog (Auto Self-Heal)" || true
  systemctl is-active --quiet vampire-web 2>/dev/null && \
    echo -e "  ${GREEN}[RUNNING]${NC} Vampire Web (Landing Page Port 80)" || true

  echo ""
  if ! $is_gw && ! $is_node; then
    echo -e "  ${YELLOW}No active Vampire service.${NC}"
    echo -e "    Gateway:  sudo vampire gateway"
    echo -e "    Node:     sudo vampire node --server <IP> --token <TOKEN>"
  fi
  echo -e "${BOLD}================================================================================${NC}\n"
}

# ==============================================================================
# LOGS
# ==============================================================================
show_logs() {
  local svc="${1:-}"
  if systemctl is-active --quiet vampire-gateway 2>/dev/null && [ -z "$svc" -o "$svc" = "gateway" ]; then
    echo -e "${CYAN}${BOLD}=== Vampire Gateway Logs ===${NC}"
    journalctl -u vampire-gateway -n 60 --no-pager
  elif systemctl is-active --quiet vampire-node 2>/dev/null && [ -z "$svc" -o "$svc" = "node" ]; then
    echo -e "${CYAN}${BOLD}=== Vampire Node Logs ===${NC}"
    journalctl -u vampire-node -n 60 --no-pager
  else
    log_warn "No active service. Try: journalctl -u vampire-node -n 50 --no-pager"
  fi
}

# ==============================================================================
# UPDATE
# ==============================================================================
do_update() {
  banner
  log_step "Checking for Vampire updates..."
  local new_ver
  new_ver=$(curl -sSL "$INSTALL_URL" 2>/dev/null | grep 'VAMPIRE_VERSION=' | head -1 | cut -d'"' -f2 || echo "unknown")
  if [ "$new_ver" = "$VAMPIRE_VERSION" ]; then
    log_info "Vampire v$VAMPIRE_VERSION is already up to date!"
  else
    log_step "Updating Vampire: v$VAMPIRE_VERSION -> v$new_ver"
    curl -sSL "$INSTALL_URL" -o "$BIN_DIR/vampire" 2>/dev/null
    chmod +x "$BIN_DIR/vampire"
    log_info "Updated to v$new_ver"
  fi
}

# ==============================================================================
# LANDING PAGE (Port 80)
# ==============================================================================
start_test_page_silent() {
  mkdir -p /var/www/vampire
  if ! curl -sSL --connect-timeout 5 \
    "https://raw.githubusercontent.com/akashdevme/vampire-ip-routing/main/index.html" \
    -o /var/www/vampire/index.html 2>/dev/null; then
    cat > /var/www/vampire/index.html << 'FBHTML'
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><title>VampireHosting Active</title>
<style>body{background:#09090e;color:#e5e5f0;font-family:sans-serif;display:flex;align-items:center;justify-content:center;min-height:100vh}
.c{background:rgba(18,18,28,.85);border:1px solid rgba(168,85,247,.35);border-radius:24px;padding:40px;text-align:center;max-width:500px}
h1{background:linear-gradient(135deg,#fff 30%,#c084fc 70%,#f43f5e 100%);-webkit-background-clip:text;-webkit-text-fill-color:transparent;font-size:2.5rem}
.b{display:inline-flex;align-items:center;gap:8px;background:rgba(34,197,94,.15);border:1px solid rgba(34,197,94,.4);color:#4ade80;padding:6px 16px;border-radius:999px;margin-bottom:20px;font-size:.85rem;font-weight:700}
.d{width:8px;height:8px;background:#22c55e;border-radius:50%;box-shadow:0 0 10px #22c55e;animation:p 2s infinite}
@keyframes p{50%{opacity:.4}}p{color:#94a3b8;margin-top:12px}</style></head>
<body><div class="c"><div class="b"><div class="d"></div>Tunnel Active 24/7</div>
<h1>VampireHosting</h1><p>Your High-RAM Private VPS is now accessible on this Public IPv4.</p>
<p style="color:#c084fc;margin-top:16px;font-size:.9rem">Powered by vampirenodes.in</p></div></body></html>
FBHTML
  fi

  cat > /etc/systemd/system/vampire-web.service << SVCEOF
[Unit]
Description=Vampire Hosting -- Landing Page Port 80
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/var/www/vampire
ExecStart=/usr/bin/python3 -m http.server 80
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
SVCEOF

  systemctl daemon-reload
  systemctl enable --now vampire-web >/dev/null 2>&1
  systemctl restart vampire-web >/dev/null 2>&1 || true
}

start_test_page() {
  banner
  log_step "Starting landing page on Port 80..."
  start_test_page_silent
  log_info "Landing page LIVE 24/7! Open: http://$(detect_public_ip)"
}

# ==============================================================================
# GEMINI AI ASSISTANT
# ==============================================================================
GEMINI_SYSTEM_PROMPT="You are Vampire AI, the official technical support bot for VampireHosting (vampirenodes.in). VampireHosting uses FRP (fast reverse proxy) to route cheap, high-RAM private VPSs (NAT VPS, LXC containers, IPv6-only VPS) through a public IPv4 gateway using persistent TCP tunnels for 24/7 uptime. The key commands are: 'sudo vampire gateway' (on public VPS), 'sudo vampire node --server <IP> --token <TOKEN>' (on private VPS), 'sudo vampire add <port>' (forward extra ports), 'sudo vampire ai' (this assistant), 'sudo vampire status' (health check), 'sudo vampire logs' (view logs). Provide concise, accurate, copy-paste-ready Linux bash commands for: server setup, port forwarding, firewall (ufw/iptables), game server hosting (Minecraft 25565, FiveM 30120, Palworld 8211, Rust 28015, Pterodactyl wings), nginx reverse proxy, SSL/TLS (certbot), and debugging tunnels."

call_gemini() {
  local api_key="$1" query="$2"
  echo -e "\n  ${PURPLE}${DIM}Vampire AI is thinking...${NC}"

  local payload
  payload=$(jq -n \
    --arg sys "$GEMINI_SYSTEM_PROMPT" \
    --arg q   "$query" \
    '{ system_instruction:{parts:[{text:$sys}]},
       contents:[{role:"user",parts:[{text:$q}]}],
       generationConfig:{temperature:0.3,maxOutputTokens:1024} }')

  local response answer
  response=$(curl -s --connect-timeout 15 -X POST \
    "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=${api_key}" \
    -H "Content-Type: application/json" \
    -d "$payload" 2>/dev/null)

  answer=$(echo "$response" | jq -r '.candidates[0].content.parts[0].text // empty' 2>/dev/null)

  if [ -n "$answer" ]; then
    echo ""
    echo -e "${PURPLE}${BOLD}  === Vampire AI ================================================================${NC}"
    echo "$answer" | sed 's/^/  /'
    echo -e "${PURPLE}${BOLD}  ===============================================================================${NC}"
  else
    local err; err=$(echo "$response" | jq -r '.error.message // "Unknown error"' 2>/dev/null)
    log_error "Gemini API error: $err"
  fi
}

vampire_ai() {
  local prompt="$*"

  echo -e "\n${PURPLE}${BOLD}  Vampire AI -- Powered by Google Gemini${NC}\n"

  local api_key="${GEMINI_API_KEY:-}"
  [ -z "$api_key" ] && [ -f "$VAMPIRE_DIR/gemini.key" ] && api_key=$(cat "$VAMPIRE_DIR/gemini.key")

  if [ -z "$api_key" ]; then
    echo -e "  ${YELLOW}Gemini API Key not configured.${NC}"
    echo -e "  Get a FREE key at: ${CYAN}https://aistudio.google.com/app/apikey${NC}\n"
    read -rp "  Enter your Google Gemini API Key: " api_key
    [ -z "$api_key" ] && { log_error "API Key required."; exit 1; }
    mkdir -p "$VAMPIRE_DIR"
    echo "$api_key" > "$VAMPIRE_DIR/gemini.key"
    chmod 600 "$VAMPIRE_DIR/gemini.key"
    log_info "API Key saved at $VAMPIRE_DIR/gemini.key\n"
  fi

  if [ -n "$prompt" ]; then
    call_gemini "$api_key" "$prompt"
    return
  fi

  echo -e "  ${DIM}Interactive mode: type your question and press Enter. Type 'exit' to quit.${NC}\n"
  while true; do
    echo -ne "${CYAN}  You: ${NC}"
    IFS= read -r user_input || break
    [[ "${user_input:-}" =~ ^(exit|quit|bye)$ ]] && {
      echo -e "\n  ${PURPLE}Vampire AI signing off. Happy hosting!${NC}\n"; break; }
    [ -z "${user_input:-}" ] && continue
    call_gemini "$api_key" "$user_input"
    echo ""
  done
}

# ==============================================================================
# UNINSTALL
# ==============================================================================
uninstall_vampire() {
  banner
  echo -e "${RED}${BOLD}UNINSTALLING VAMPIRE IP ROUTER${NC}"
  read -rp "  Are you sure? (yes/no): " confirm
  [ "$confirm" = "yes" ] || { echo "  Cancelled."; exit 0; }

  systemctl stop vampire-gateway vampire-node vampire-web vampire-watchdog 2>/dev/null || true
  systemctl disable vampire-gateway vampire-node vampire-web vampire-watchdog 2>/dev/null || true
  rm -f /etc/systemd/system/vampire-{gateway,node,web,watchdog}.service
  systemctl daemon-reload
  rm -rf "$VAMPIRE_DIR" /var/www/vampire
  rm -f "$BIN_DIR/frps" "$BIN_DIR/frpc" "$BIN_DIR/vampire"
  log_info "Vampire completely removed."
}

# ==============================================================================
# MAIN
# ==============================================================================
check_root "$@"
CMD="${1:-help}"; shift || true

case "$CMD" in
  gateway|server)      setup_gateway "$@"; setup_watchdog ;;
  node|client)         setup_node "$@"; setup_watchdog ;;
  add|forward)         add_port "$@" ;;
  remove|del)          remove_port "$@" ;;
  page|web|landing)    start_test_page ;;
  ai|ask|chat|support) vampire_ai "$@" ;;
  status|health)       show_status ;;
  logs|log)            show_logs "$@" ;;
  update|upgrade)      do_update ;;
  watchdog)            setup_watchdog ;;
  uninstall)           uninstall_vampire ;;
  version|-v)          echo "Vampire IP Router v${VAMPIRE_VERSION}" ;;
  *)
    banner
    echo -e "${BOLD}  USAGE${NC}"
    echo ""
    echo -e "  ${BOLD}Setup:${NC}"
    echo -e "    ${CYAN}sudo vampire gateway${NC}                         On your PUBLIC VPS"
    echo -e "    ${CYAN}sudo vampire node --server IP --token TOKEN${NC}  On your PRIVATE VPS"
    echo ""
    echo -e "  ${BOLD}Ports:${NC}"
    echo -e "    ${CYAN}sudo vampire add <port> [tcp|udp|both]${NC}       Forward any port"
    echo -e "    ${CYAN}sudo vampire remove <port>${NC}                   Stop forwarding a port"
    echo ""
    echo -e "  ${BOLD}Monitoring:${NC}"
    echo -e "    ${CYAN}sudo vampire status${NC}                          Health of all services"
    echo -e "    ${CYAN}sudo vampire logs [gateway|node]${NC}             View live logs"
    echo -e "    ${CYAN}sudo vampire update${NC}                          Update vampire script"
    echo ""
    echo -e "  ${BOLD}AI & Web:${NC}"
    echo -e "    ${CYAN}sudo vampire ai${NC}                              Interactive Gemini AI chat"
    echo -e "    ${CYAN}sudo vampire ai \"question\"${NC}                  One-shot AI answer"
    echo -e "    ${CYAN}sudo vampire page${NC}                            Start landing page Port 80"
    echo ""
    echo -e "  ${BOLD}Other:${NC}"
    echo -e "    ${CYAN}sudo vampire uninstall${NC}                       Remove completely"
    echo -e "    ${CYAN}sudo vampire version${NC}                         Show version"
    echo ""
    echo -e "  ${DIM}1-cmd install: curl -sSL https://iproute.vampirenodes.in | sudo bash -s -- gateway${NC}"
    echo -e "${CYAN}================================================================================${NC}\n"
    ;;
esac
