#!/usr/bin/env bash
# ==============================================================================
#  _   _                 _           _   _           _   _
# | | | | __ _ _ __ ___ | |__   ___ | | | | ___  ___| |_(_)_ __   __ _
# | | | |/ _` | '_ ` _ \| '_ \ / _ \| | | |/ _ \/ __| __| | '_ \ / _` |
# \ \_/ / (_| | | | | | | |_) |  __/| |_| | (_) \__ \ |_| | | | | (_| |
#  \___/ \__,_|_| |_| |_|_.__/ \___| \___/ \___/|___/\__|_|_| |_|\__, |
#                                                                  |___/
#  VAMPIRE HOSTING v2.2.0 -- 1-COMMAND 24/7 HIGH-PERFORMANCE IP ROUTER
#  Route and Port Forward Any Server with 24/7 Persistent Uptime
#  GitHub: https://github.com/akashdevme/vampire-ip-routing
# ==============================================================================

set -euo pipefail

VAMPIRE_DIR="/etc/vampire"
BIN_DIR="/usr/local/bin"
FRP_VERSION="0.58.1"
DEFAULT_BIND_PORT="20000"
DASHBOARD_PORT="7500"
VAMPIRE_VERSION="2.2.0"
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
                       |_|   24/7 IP ROUTER v2.2                          |___/
BANNER
  echo -e "${CYAN}  1-Command 24/7 IP Router & Port Forwarding Tool  |  vampirenodes.in${NC}"
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
  log_step "Updating vampire command in $BIN_DIR/vampire..."
  if [ -f "$0" ] && [ "$0" != "$BIN_DIR/vampire" ]; then
    cp -f "$0" "$BIN_DIR/vampire" 2>/dev/null || true
  else
    curl -sSL "$INSTALL_URL" -o "$BIN_DIR/vampire" 2>/dev/null || true
  fi
  chmod +x "$BIN_DIR/vampire" 2>/dev/null || true
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

sync_open_ports() {
  [ -f "$VAMPIRE_DIR/frpc.toml" ] || return 0
  command -v ss >/dev/null 2>&1 || return 0

  # Scan listening TCP and UDP ports
  local open_ports
  open_ports=$(ss -tulpn 2>/dev/null | awk '
    NR>1 {
      proto = ($1 ~ /tcp/ ? "tcp" : ($1 ~ /udp/ ? "udp" : ""))
      if (proto != "") {
        split($5, a, ":")
        port = a[length(a)]
        if (port ~ /^[0-9]+$/ && port > 0 && port < 65536 && port != 22 && port != 20000 && port != 7500) {
          print port ":" proto
        }
      }
    }' | sort -u)

  local need_restart=false
  for item in $open_ports; do
    [ -n "$item" ] || continue
    local p="${item%%:*}"
    local proto="${item##*:}"
    local proxy_name="auto-${p}-${proto}"

    if ! grep -q "\"$proxy_name\"" "$VAMPIRE_DIR/frpc.toml" 2>/dev/null && ! grep -q "\"port-${p}-${proto}\"" "$VAMPIRE_DIR/frpc.toml" 2>/dev/null; then
      cat >> "$VAMPIRE_DIR/frpc.toml" << EOF

# Auto-forwarded listening port
[[proxies]]
name = "$proxy_name"
type = "$proto"
localIP = "127.0.0.1"
localPort = $p
remotePort = $p
EOF
      need_restart=true
      log "AUTO-FORWARD: Detected new listening port $p/$proto -> Auto-forwarded!"
    fi
  done

  if [ "$need_restart" = true ]; then
    systemctl restart vampire-node >/dev/null 2>&1 || true
  fi
}

while true; do
  rotate_log
  sync_open_ports
  for svc in vampire-gateway vampire-node frpc frps wg-quick@wg0 vampire-web vampire-app; do
    if systemctl is-enabled --quiet "$svc" 2>/dev/null; then
      if ! systemctl is-active --quiet "$svc"; then
        log "ALERT: $svc is DOWN. Restarting..."
        systemctl restart "$svc" && log "RECOVERED: $svc restarted OK." || log "FAILED: could not restart $svc"
      fi
    fi
  done
  sleep 10
done
WATCHDOG

  chmod +x "$VAMPIRE_DIR/watchdog.sh"

  cat > /etc/systemd/system/vampire-watchdog.service << EOF
[Unit]
Description=Vampire Hosting -- Auto Self-Heal Watchdog
After=network-online.target
Wants=network-online.target

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
  log_info "Watchdog active -- auto self-healing every 30 seconds!"
}

# ==============================================================================
# 24/7 AUTO-CONFIG & SSH DISCONNECT SHIELD
# ==============================================================================
apply_247_optimizations() {
  log_step "Enabling user lingering so SSH logout never kills processes..."
  mkdir -p /var/lib/systemd/linger 2>/dev/null || true
  touch /var/lib/systemd/linger/root 2>/dev/null || true
  loginctl enable-linger root 2>/dev/null || true
  if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    touch "/var/lib/systemd/linger/${SUDO_USER}" 2>/dev/null || true
    loginctl enable-linger "$SUDO_USER" 2>/dev/null || true
    log_info "Linger enabled for user: ${BOLD}$SUDO_USER${NC} and root"
  else
    log_info "Linger enabled for root"
  fi

  log_step "Configuring systemd-logind to protect background processes on logout..."
  mkdir -p /etc/systemd/logind.conf.d 2>/dev/null || true
  cat > /etc/systemd/logind.conf.d/99-vampire-247.conf << 'EOF'
[Login]
KillUserProcesses=no
KillExcludeUsers=root
EOF
  # Safe reload without dropping active SSH sessions
  systemctl reload systemd-logind >/dev/null 2>&1 || true
  log_info "systemd-logind configured: KillUserProcesses=no"

  log_step "Tuning TCP keepalive so tunnels never drop on idle..."
  mkdir -p /etc/sysctl.d 2>/dev/null || true
  cat > /etc/sysctl.d/99-vampire-keepalive.conf << 'EOF'
net.ipv4.tcp_keepalive_time = 60
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 6
EOF
  sysctl -p /etc/sysctl.d/99-vampire-keepalive.conf >/dev/null 2>&1 || true
  log_info "TCP keepalive active (60s probe cycle)"
}

setup_app_247() {
  local app_name="${1:-}" app_cmd="${2:-}" app_dir="${3:-}"

  banner
  echo -e "${BOLD}${GREEN}=== VAMPIRE 24/7 APP / GAME DAEMONIZER ===${NC}"
  echo -e "${YELLOW}  Convert any game server, website, or bot into a 24/7 auto-restarting service.${NC}\n"

  if [ -z "$app_name" ]; then
    read -rp "  Enter service name (e.g. minecraft, myweb, bot): " app_name
  fi
  app_name=$(echo "$app_name" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_-')
  [ -z "$app_name" ] && app_name="vampire-app"

  if [ -z "$app_cmd" ]; then
    read -rp "  Enter full start command (e.g. java -Xmx4G -jar server.jar nogui): " app_cmd
  fi
  [ -z "$app_cmd" ] && { log_error "Command cannot be empty."; exit 1; }

  if [ -z "$app_dir" ]; then
    read -rp "  Enter working directory [Default: $(pwd)]: " app_dir
    app_dir="${app_dir:-$(pwd)}"
  fi

  log_step "Creating 24/7 systemd service for: $app_name ..."

  cat > "/etc/systemd/system/${app_name}.service" << EOF
[Unit]
Description=Vampire 24/7 Service -- $app_name
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=$app_dir
ExecStart=$app_cmd
Restart=always
RestartSec=5s
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now "${app_name}.service" >/dev/null 2>&1
  systemctl restart "${app_name}.service"

  sleep 1
  if systemctl is-active --quiet "${app_name}.service"; then
    log_info "Service ${BOLD}$app_name${NC} is now running 24/7 in the background!"
    echo ""
    echo -e "  Manage your service:"
    echo -e "    Status:   ${CYAN}systemctl status $app_name${NC}"
    echo -e "    Logs:     ${CYAN}journalctl -u $app_name -f${NC}"
    echo -e "    Restart:  ${CYAN}systemctl restart $app_name${NC}"
    echo -e "    Stop:     ${CYAN}systemctl stop $app_name${NC}"
    echo ""
  else
    log_warn "Service started but may have exited. Check: journalctl -u $app_name -n 30"
  fi
}

setup_247() {
  local subcmd="${1:-}"

  # Make sure /usr/local/bin/vampire is updated on the system
  install_vampire_cmd >/dev/null 2>&1 || true

  if [ "$subcmd" = "app" ] || [ "$subcmd" = "service" ]; then
    shift || true
    setup_app_247 "$@"
    return
  fi

  if [ "$subcmd" = "run" ]; then
    shift || true
    local run_cmd="$*"
    setup_app_247 "vampire-app" "$run_cmd" "$(pwd)"
    return
  fi

  # If user passed a quoted command directly: sudo vampire 247 "java -jar server.jar"
  if [ -n "$subcmd" ] && [ "$subcmd" != "all" ]; then
    local run_cmd="$subcmd"
    if [ $# -gt 0 ]; then
      run_cmd="$run_cmd $*"
    fi
    setup_app_247 "vampire-app" "$run_cmd" "$(pwd)"
    return
  fi

  banner
  echo -e "${BOLD}${GREEN}=== VAMPIRE 24/7 AUTO-CONFIG & DISCONNECT SHIELD ===${NC}"
  echo -e "${YELLOW}  Locking system so services NEVER stop when SSH closes or VPS reboots.${NC}\n"

  apply_247_optimizations

  log_step "Verifying auto-healing watchdog & systemd services..."
  setup_watchdog

  local any_found=false
  for svc in vampire-gateway vampire-node frpc frps wg-quick@wg0 vampire-web vampire-app; do
    if [ -f "/etc/systemd/system/${svc}.service" ] || [ -f "/lib/systemd/system/${svc}.service" ] || systemctl is-enabled --quiet "$svc" 2>/dev/null; then
      systemctl daemon-reload >/dev/null 2>&1 || true
      systemctl enable --now "$svc" >/dev/null 2>&1 || true
      systemctl restart "$svc" >/dev/null 2>&1 || true
      log_info "Service active & enabled on boot: ${BOLD}$svc${NC}"
      any_found=true
    fi
  done

  if ! $any_found; then
    log_warn "No active routing tunnel service found yet (vampire-gateway, vampire-node, frpc, or wg0)."
    echo -e "  To set up routing: ${CYAN}sudo vampire gateway${NC} (Gateway) or ${CYAN}sudo vampire node ...${NC} (Node)"
  fi

  echo ""
  echo -e "${GREEN}${BOLD}[OK] 24/7 AUTO-CONFIG COMPLETE!${NC}"
  echo -e "${CYAN}================================================================================${NC}"
  echo -e "  ${BOLD}Protections Active:${NC}"
  echo -e "    * SSH Disconnect Shield:  ${GREEN}Active (KillUserProcesses disabled)${NC}"
  echo -e "    * User Lingering:         ${GREEN}Enabled (processes survive logout)${NC}"
  echo -e "    * Auto-Heal Watchdog:     ${GREEN}Running (checks every 30s)${NC}"
  echo -e "    * TCP Keepalive:          ${GREEN}Optimized (no idle timeouts)${NC}"
  echo -e "    * Boot Auto-Start:        ${GREEN}Enabled in systemd${NC}"
  echo ""
  echo -e "  ${BOLD}${YELLOW}Want to run a Game Server / Website / Bot 24/7?${NC}"
  echo -e "  One-command 24/7 daemonizer:"
  echo -e "    ${CYAN}sudo vampire 247 run \"java -Xmx4G -jar server.jar nogui\"${NC}"
  echo -e "    or interactive wizard: ${CYAN}sudo vampire 247 app${NC}"
  echo -e "    or screen: ${CYAN}screen -S myapp${NC} -> run app -> press ${BOLD}Ctrl+A, D${NC} to detach."
  echo -e "${CYAN}================================================================================${NC}\n"
}

# ==============================================================================
# GATEWAY SETUP
# ==============================================================================
setup_gateway() {
  banner
  echo -e "${BOLD}${GREEN}=== SETTING UP VAMPIRE GATEWAY (24/7) ===${NC}"
  echo -e "${YELLOW}  All TCP/UDP traffic will route to your connected node.${NC}\n"

  install_dependencies
  download_frp "frps"
  install_vampire_cmd

  PUBLIC_IP=$(detect_public_ip)
  log_info "Detected Gateway IP: ${BOLD}$PUBLIC_IP${NC}"

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
Description=Vampire Hosting -- Gateway 24/7
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
  echo -e "${BOLD}${YELLOW}  RUN THIS 1-COMMAND ON YOUR NODE SERVER:${NC}"
  echo ""
  echo -e "  ${GREEN}${BOLD}curl -sSL $INSTALL_URL | sudo bash -s -- node --server $PUBLIC_IP --token $TOKEN${NC}"
  echo ""
  echo -e "  Gateway IP:    ${GREEN}${BOLD}$PUBLIC_IP${NC}"
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
  echo -e "${BOLD}${GREEN}=== SETTING UP VAMPIRE NODE ===${NC}"
  echo -e "${YELLOW}  Connecting this server to Gateway via TCP...${NC}\n"

  if [ -z "$server_ip" ] || [ -z "$token" ]; then
    log_error "Server IP and Token are required!"
    echo "  Usage: sudo bash vampire.sh node --server <GATEWAY_IP> --token <TOKEN>"
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
name = "vampire-success"
type = "tcp"
localIP = "127.0.0.1"
localPort = 9090
remotePort = 9090

# Auto-Forward ALL Ports Range (1-65535 TCP & UDP)
{{- range \$_ , \$v := parseNumberRangePair "1-21,23-7499,7501-19999,20001-65535" "1-21,23-7499,7501-19999,20001-65535" }}
[[proxies]]
name = "all-ports-tcp-{{ \$v.First }}"
type = "tcp"
localIP = "127.0.0.1"
localPort = {{ \$v.First }}
remotePort = {{ \$v.Second }}
{{- end }}

{{- range \$_ , \$v := parseNumberRangePair "1-65535" "1-65535" }}
[[proxies]]
name = "all-ports-udp-{{ \$v.First }}"
type = "udp"
localIP = "127.0.0.1"
localPort = {{ \$v.First }}
remotePort = {{ \$v.Second }}
{{- end }}
TOMLEOF

  cat > /etc/systemd/system/vampire-node.service << SVCEOF
[Unit]
Description=Vampire Hosting -- Node 24/7
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
    echo -e "  ${BOLD}Your Node is now LIVE on Gateway:${NC} ${GREEN}$server_ip${NC}"
    echo ""
    echo -e "  ${GREEN}${BOLD}✓ AUTOMATIC ALL-PORT FORWARDING ACTIVE!${NC}"
    echo -e "    ${YELLOW}Every port you open on this machine is automatically forwarded in real-time.${NC}"
    echo -e "    ${YELLOW}Zero manual port commands required &mdash; just start your game or app!${NC}"
    echo ""
    echo -e "  Default Services:"
    echo -e "    Success Page:     ${CYAN}http://$server_ip:9090${NC}"
    echo -e "    SSH on Port 24:   ${CYAN}sudo vampire setup ssh${NC}"
    echo -e "    Status & Health:  ${CYAN}sudo vampire status${NC}"
    echo -e "${CYAN}================================================================================${NC}\n"
  else
    log_error "Could not verify node. Check: journalctl -u vampire-node -n 30"
  fi
}

# ==============================================================================
# ADD PORT
# ==============================================================================
# ==============================================================================
# SSH SETUP (PORT 24, ROOT LOGIN, AUTH PASSWORD)
# ==============================================================================
setup_ssh() {
  banner
  echo -e "${BOLD}${GREEN}=== SETTING UP SSH ON PORT 24 ===${NC}"
  echo -e "${YELLOW}  Configuring SSH daemon: Port 24, PermitRootLogin=yes, PasswordAuthentication=yes${NC}\n"

  log_step "Checking OpenSSH server installation..."
  if ! command -v sshd >/dev/null 2>&1; then
    log_step "Installing OpenSSH server..."
    if command -v apt-get >/dev/null 2>&1; then
      DEBIAN_FRONTEND=noninteractive apt-get update -qq >/dev/null 2>&1 || true
      DEBIAN_FRONTEND=noninteractive apt-get install -y -qq openssh-server >/dev/null 2>&1 || true
    elif command -v yum >/dev/null 2>&1; then
      yum install -y -q openssh-server >/dev/null 2>&1 || true
    elif command -v apk >/dev/null 2>&1; then
      apk add --quiet openssh >/dev/null 2>&1 || true
    fi
  fi

  log_step "Configuring SSH on Port 24..."
  mkdir -p /etc/ssh /etc/ssh/sshd_config.d

  # Write drop-in config for modern OpenSSH
  cat > /etc/ssh/sshd_config.d/99-vampire-ssh.conf << 'EOF'
Port 24
PermitRootLogin yes
PasswordAuthentication yes
PubkeyAuthentication yes
KbdInteractiveAuthentication yes
EOF

  # Ensure main /etc/ssh/sshd_config also reflects Port 24, PermitRootLogin yes, PasswordAuthentication yes
  if [ -f /etc/ssh/sshd_config ]; then
    if ! grep -q -E "^Port 24" /etc/ssh/sshd_config; then
      echo "Port 24" >> /etc/ssh/sshd_config
    fi
    if grep -q -E "^#?PermitRootLogin" /etc/ssh/sshd_config; then
      sed -i -E 's/^#?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
    else
      echo "PermitRootLogin yes" >> /etc/ssh/sshd_config
    fi
    if grep -q -E "^#?PasswordAuthentication" /etc/ssh/sshd_config; then
      sed -i -E 's/^#?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
    else
      echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config
    fi
  fi

  # Support Ubuntu 22.10 / 24.04 systemd socket activation if enabled
  if [ -f /lib/systemd/system/ssh.socket ] || [ -f /etc/systemd/system/ssh.socket ]; then
    mkdir -p /etc/systemd/system/ssh.socket.d/
    cat > /etc/systemd/system/ssh.socket.d/listen.conf << 'EOF'
[Socket]
ListenStream=
ListenStream=24
ListenStream=22
EOF
    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl restart ssh.socket >/dev/null 2>&1 || true
  fi

  # Root Password Setup (auth password)
  local ROOT_PASS="${1:-}"
  echo ""
  echo -e "${CYAN}--- Root Password Setup (Auth Password) ---${NC}"
  if [ -z "$ROOT_PASS" ]; then
    echo -e "Enter a password for the root user (or press Enter to auto-generate a secure password):"
    read -rs -p "  Password: " ROOT_PASS </dev/tty 2>/dev/null || true
    echo ""
  fi

  if [ -z "$ROOT_PASS" ]; then
    ROOT_PASS="Vampire@$(openssl rand -hex 3)!"
    echo "root:$ROOT_PASS" | chpasswd
    echo -e "  Generated root password: ${YELLOW}${BOLD}$ROOT_PASS${NC}"
    log_info "Root password generated and applied."
  else
    echo "root:$ROOT_PASS" | chpasswd
    log_info "Root password updated successfully."
  fi

  log_step "Restarting SSH service..."
  systemctl restart ssh >/dev/null 2>&1 || \
  systemctl restart sshd >/dev/null 2>&1 || \
  service ssh restart >/dev/null 2>&1 || \
  service sshd restart >/dev/null 2>&1 || true

  # Firewall rules
  command -v ufw >/dev/null 2>&1 && ufw allow 24/tcp >/dev/null 2>&1 || true
  command -v iptables >/dev/null 2>&1 && iptables -I INPUT -p tcp --dport 24 -j ACCEPT >/dev/null 2>&1 || true

  # If running on a Node with vampire tunnel, forward port 24 automatically
  if [ -f "$VAMPIRE_DIR/frpc.toml" ]; then
    log_step "Forwarding port 24 through Vampire tunnel..."
    if ! grep -q "\"port-24-tcp\"\|\"vampire-ssh-24\"" "$VAMPIRE_DIR/frpc.toml"; then
      cat >> "$VAMPIRE_DIR/frpc.toml" << 'PORTEOF'

# Vampire SSH Port 24
[[proxies]]
name = "vampire-ssh-24"
type = "tcp"
localIP = "127.0.0.1"
localPort = 24
remotePort = 24
PORTEOF
      systemctl restart vampire-node >/dev/null 2>&1 || true
      log_info "Port 24 forwarded to Gateway."
    fi
  fi

  # Detect public IP to provide the exact command
  local pub_ip=""
  if [ -f "$VAMPIRE_DIR/node.env" ]; then
    pub_ip=$(grep '^GATEWAY_IP=' "$VAMPIRE_DIR/node.env" | head -1 | cut -d'=' -f2 | tr -d '"')
  fi
  if [ -z "$pub_ip" ] && [ -f "$VAMPIRE_DIR/gateway.env" ]; then
    pub_ip=$(grep '^PUBLIC_IP=' "$VAMPIRE_DIR/gateway.env" | head -1 | cut -d'=' -f2 | tr -d '"')
  fi
  if [ -z "$pub_ip" ]; then
    pub_ip=$(detect_public_ip)
  fi

  echo ""
  echo -e "${GREEN}${BOLD}[OK] SSH SETUP COMPLETE ON PORT 24!${NC}"
  echo -e "${CYAN}================================================================================${NC}"
  echo -e "  ${BOLD}Connect to your server via SSH:${NC}"
  echo ""
  echo -e "    ${GREEN}${BOLD}ssh root@${pub_ip} -p 24${NC}"
  echo ""
  echo -e "  Configured settings:"
  echo -e "    * Port:                   ${CYAN}24${NC}"
  echo -e "    * PermitRootLogin:        ${GREEN}yes${NC}"
  echo -e "    * PasswordAuthentication: ${GREEN}yes${NC}"
  echo -e "    * Tunnel Route:           ${GREEN}Port 24 -> ${pub_ip}:24${NC}"
  echo -e "${CYAN}================================================================================${NC}\n"
}

# ==============================================================================
# ADD PORT / ALL PORTS
# ==============================================================================
add_port() {
  local port="${1:-}" proto="${2:-both}"

  if [ -z "$port" ]; then
    echo -e "${RED}Usage: sudo vampire add <port|all> [tcp|udp|both]${NC}"
    echo "  Examples:"
    echo "    sudo vampire add all"
    echo "    sudo vampire add 7777"
    echo "    sudo vampire add 30120 tcp"
    echo "    sudo vampire add 8211  udp"
    exit 1
  fi

  [ -f "$VAMPIRE_DIR/frpc.toml" ] || { log_error "Vampire Node not installed."; exit 1; }

  # Handle "all" ports forwarding
  if [ "$port" = "all" ]; then
    log_step "Forwarding ALL ports (TCP & UDP 1-65535)..."

    if grep -q "all-ports-tcp" "$VAMPIRE_DIR/frpc.toml" 2>/dev/null; then
      log_warn "All ports proxy already configured. Restarting..."
      systemctl restart vampire-node
      log_info "ALL ports are active!"; return 0
    fi

    cat >> "$VAMPIRE_DIR/frpc.toml" << 'ALLEOF'

# Added: ALL PORTS FORWARDING
{{- range $_, $v := parseNumberRangePair "1-21,23-7499,7501-19999,20001-65535" "1-21,23-7499,7501-19999,20001-65535" }}
[[proxies]]
name = "all-ports-tcp-{{ $v.First }}"
type = "tcp"
localIP = "127.0.0.1"
localPort = {{ $v.First }}
remotePort = {{ $v.Second }}
{{- end }}

{{- range $_, $v := parseNumberRangePair "1-65535" "1-65535" }}
[[proxies]]
name = "all-ports-udp-{{ $v.First }}"
type = "udp"
localIP = "127.0.0.1"
localPort = {{ $v.First }}
remotePort = {{ $v.Second }}
{{- end }}
ALLEOF

    systemctl restart vampire-node
    log_info "ALL ports (TCP & UDP 1-65535) are now forwarded live 24/7!"
    return 0
  fi

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
  [ -n "$port" ] || { echo -e "${RED}Usage: sudo vampire remove <port|all>${NC}"; exit 1; }
  [ -f "$VAMPIRE_DIR/frpc.toml" ] || { log_error "Vampire Node not installed."; exit 1; }

  if [ "$port" = "all" ]; then
    python3 - "$VAMPIRE_DIR/frpc.toml" << 'PYEOF'
import sys, re
f = sys.argv[1]
txt = open(f).read()
txt = re.sub(r'\n*# Added: ALL PORTS FORWARDING[\s\S]*?\{\{- end \}\}', '', txt)
open(f, 'w').write(txt.strip() + '\n')
print("Removed all-ports forwarding range from config.")
PYEOF
    systemctl restart vampire-node
    log_info "All-ports forwarding removed and service restarted."
    return 0
  fi

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
    echo -e "  ${GREEN}[RUNNING]${NC} ${BOLD}Vampire Gateway${NC}"
    [ -f "$VAMPIRE_DIR/gateway.env" ] && { source "$VAMPIRE_DIR/gateway.env" 2>/dev/null || true
      echo -e "    Gateway IP: ${CYAN}${PUBLIC_IP:-?}${NC}"
      echo -e "    Dashboard:  ${CYAN}http://${PUBLIC_IP:-?}:${DASHBOARD_PORT:-7500}${NC}"
    }
    echo ""
  else
    echo -e "  [STOPPED] Vampire Gateway"
  fi

  if systemctl is-active --quiet vampire-node 2>/dev/null; then
    is_node=true
    echo -e "  ${GREEN}[RUNNING]${NC} ${BOLD}Vampire Node${NC}"
    [ -f "$VAMPIRE_DIR/node.env" ] && { source "$VAMPIRE_DIR/node.env" 2>/dev/null || true
      echo -e "    Connected Gateway IP: ${CYAN}${GATEWAY_IP:-?}${NC}"
      echo -e "    Success Page:         ${CYAN}http://${GATEWAY_IP:-?}:9090${NC}"
    }
    echo ""
    if [ -f "$VAMPIRE_DIR/frpc.toml" ]; then
      echo -e "  ${BOLD}Active Routes:${NC}"
      grep -E '^name = |^remotePort = ' "$VAMPIRE_DIR/frpc.toml" 2>/dev/null | \
        paste - - | awk '{gsub(/"/, ""); print "    * " $3 "  ->  Port " $6}' || true
      if grep -q "all-ports-tcp" "$VAMPIRE_DIR/frpc.toml" 2>/dev/null; then
        echo -e "    * ${GREEN}ALL PORTS (1-65535 TCP & UDP) ACTIVE${NC}"
      fi
      echo ""
    fi
  else
    echo -e "  [STOPPED] Vampire Node"
  fi

  systemctl is-active --quiet vampire-watchdog 2>/dev/null && \
    echo -e "  ${GREEN}[RUNNING]${NC} Vampire Watchdog (Auto Self-Heal)" || true
  systemctl is-active --quiet vampire-web 2>/dev/null && \
    echo -e "  ${GREEN}[RUNNING]${NC} Vampire Success Page (Port 9090)" || true

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
  new_ver=$(curl -sSL "https://raw.githubusercontent.com/akashdevme/vampire-ip-routing/main/vampire.sh" 2>/dev/null | grep 'VAMPIRE_VERSION=' | head -1 | cut -d'"' -f2 || curl -sSL "$INSTALL_URL" 2>/dev/null | grep 'VAMPIRE_VERSION=' | head -1 | cut -d'"' -f2 || echo "unknown")
  log_step "Downloading latest Vampire script..."
  if curl -sSL "https://raw.githubusercontent.com/akashdevme/vampire-ip-routing/main/vampire.sh" -o "$BIN_DIR/vampire" 2>/dev/null || curl -sSL "$INSTALL_URL" -o "$BIN_DIR/vampire" 2>/dev/null; then
    chmod +x "$BIN_DIR/vampire"
    log_info "Updated to latest Vampire (v${new_ver:-$VAMPIRE_VERSION}) successfully!"
  else
    log_error "Failed to download update."
  fi
}

# ==============================================================================
# ==============================================================================
# SUCCESS PAGE (Port 9090)
# ==============================================================================
start_test_page_silent() {
  mkdir -p /var/www/vampire
  cat > /var/www/vampire/index.html << 'FBHTML'
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><title>Vampire Routing Active</title>
<style>body{background:#09090e;color:#e5e5f0;font-family:sans-serif;display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0}
.c{background:rgba(18,18,28,.85);border:1px solid rgba(168,85,247,.35);border-radius:24px;padding:40px;text-align:center;max-width:520px;box-shadow:0 20px 50px rgba(0,0,0,0.8)}
h1{background:linear-gradient(135deg,#fff 30%,#c084fc 70%,#f43f5e 100%);-webkit-background-clip:text;-webkit-text-fill-color:transparent;font-size:2.2rem;margin:12px 0}
.b{display:inline-flex;align-items:center;gap:8px;background:rgba(34,197,94,.15);border:1px solid rgba(34,197,94,.4);color:#4ade80;padding:6px 16px;border-radius:999px;font-size:.85rem;font-weight:700}
.d{width:8px;height:8px;background:#22c55e;border-radius:50%;box-shadow:0 0 10px #22c55e;animation:p 2s infinite}
@keyframes p{50%{opacity:.4}}p{color:#94a3b8;margin-top:12px;font-size:.95rem;line-height:1.6}
code{background:rgba(168,85,247,0.18);color:#c084fc;padding:3px 8px;border-radius:6px;font-family:monospace}
.box{background:#07070f;border:1px solid rgba(168,85,247,0.2);border-radius:12px;padding:14px;margin-top:18px;text-align:left;font-family:monospace;font-size:.84rem;color:#cbd5e1;line-height:1.8}
</style></head>
<body><div class="c"><div class="b"><div class="d"></div>Success &mdash; Routing Active 24/7 (Port 9090)</div>
<h1>Vampire Routing</h1>
<p>Your server is now successfully routed through the Gateway.</p>
<div class="box">
&bull; Forward all ports: <code>sudo vampire add all</code><br>
&bull; Setup SSH port 24: <code>sudo vampire setup ssh</code><br>
&bull; Add custom port: <code>sudo vampire add &lt;port&gt;</code><br>
&bull; Check status: <code>sudo vampire status</code>
</div>
<p style="color:#a855f7;margin-top:18px;font-size:.85rem">Powered by vampirenodes.in</p></div></body></html>
FBHTML

  cat > /etc/systemd/system/vampire-web.service << SVCEOF
[Unit]
Description=Vampire Hosting -- Success Page Port 9090
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/var/www/vampire
ExecStart=/usr/bin/python3 -m http.server 9090
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
  log_step "Starting success page on Port 9090..."
  start_test_page_silent
  log_info "Success page LIVE 24/7! Open: http://$(detect_public_ip):9090"
}

# ==============================================================================
# GEMINI AI ASSISTANT
# ==============================================================================
GEMINI_SYSTEM_PROMPT="You are Vampire AI, the official technical support bot for VampireHosting (vampirenodes.in). VampireHosting uses FRP (fast reverse proxy) to route cheap, high-RAM private VPSs (NAT VPS, LXC containers, IPv6-only VPS) through a public IPv4 gateway using persistent TCP tunnels for 24/7 uptime. The key commands are: 'sudo vampire gateway' (on public VPS), 'sudo vampire node --server <IP> --token <TOKEN>' (on private VPS), 'sudo vampire add <port>' (forward extra ports), 'sudo vampire 247' (auto-configure 24/7 uptime & anti-SSH-disconnect), 'sudo vampire ai' (this assistant), 'sudo vampire status' (health check), 'sudo vampire logs' (view logs). Provide concise, accurate, copy-paste-ready Linux bash commands for: server setup, port forwarding, firewall (ufw/iptables), game server hosting (Minecraft 25565, FiveM 30120, Palworld 8211, Rust 28015, Pterodactyl wings), nginx reverse proxy, SSL/TLS (certbot), and debugging tunnels."

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
  gateway|server)               setup_gateway "$@"; setup_watchdog ;;
  node|client)                  setup_node "$@"; setup_watchdog ;;
  setup)
    sub="${1:-}"
    shift || true
    if [ "$sub" = "ssh" ]; then
      setup_ssh "$@"
    else
      echo -e "${RED}Unknown setup option: $sub. Did you mean: sudo vampire setup ssh${NC}"
      exit 1
    fi
    ;;
  ssh)                          setup_ssh "$@" ;;
  247|24-7|always-on|keepalive) setup_247 "$@" ;;
  add|forward)                  add_port "$@" ;;
  remove|del)                   remove_port "$@" ;;
  page|web|landing|success)     start_test_page ;;
  ai|ask|chat|support)          vampire_ai "$@" ;;
  status|health)                show_status ;;
  logs|log)                     show_logs "$@" ;;
  update|upgrade)               do_update ;;
  watchdog)                     setup_watchdog ;;
  uninstall)                    uninstall_vampire ;;
  version|-v)                   echo "Vampire IP Router v${VAMPIRE_VERSION}" ;;
  *)
    banner
    echo -e "${BOLD}  USAGE${NC}"
    echo ""
    echo -e "  ${BOLD}Setup:${NC}"
    echo -e "    ${CYAN}sudo vampire gateway${NC}                         Setup Gateway Server"
    echo -e "    ${CYAN}sudo vampire node --server IP --token TOKEN${NC}  Setup Node Server"
    echo ""
    echo -e "  ${BOLD}Ports & SSH:${NC}"
    echo -e "    ${CYAN}sudo vampire setup ssh${NC}                       Setup SSH on port 24 (root + password auth)"
    echo -e "    ${CYAN}sudo vampire add all${NC}                         Forward ALL 65,535 ports (TCP & UDP)"
    echo -e "    ${CYAN}sudo vampire add <port> [tcp|udp|both]${NC}       Forward custom port"
    echo -e "    ${CYAN}sudo vampire remove <port|all>${NC}               Stop forwarding a port"
    echo ""
    echo -e "  ${BOLD}24/7 & Disconnect Protection:${NC}"
    echo -e "    ${CYAN}sudo vampire 247${NC}                             Auto-config 24/7 uptime & SSH disconnect shield"
    echo -e "    ${CYAN}sudo vampire 247 app${NC}                         Make any game/server app run 24/7 as a service"
    echo ""
    echo -e "  ${BOLD}Monitoring & Web:${NC}"
    echo -e "    ${CYAN}sudo vampire status${NC}                          Health of all services"
    echo -e "    ${CYAN}sudo vampire page${NC}                            Start success page on Port 9090"
    echo -e "    ${CYAN}sudo vampire logs [gateway|node]${NC}             View live logs"
    echo -e "    ${CYAN}sudo vampire update${NC}                          Update vampire script"
    echo ""
    echo -e "  ${BOLD}Other:${NC}"
    echo -e "    ${CYAN}sudo vampire uninstall${NC}                       Remove completely"
    echo -e "    ${CYAN}sudo vampire version${NC}                         Show version"
    echo ""
    echo -e "  ${DIM}1-cmd install: curl -sSL https://iproute.vampirenodes.in | sudo bash -s -- gateway${NC}"
    echo -e "${CYAN}================================================================================${NC}\n"
    ;;
esac
