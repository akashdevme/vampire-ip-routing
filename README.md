# 🦇 Vampire — 1-Command IP Routing & Port Forwarding Tool

> **1-Command 24/7 IP Routing, All-Ports Forwarding, SSH on Port 24, and Disconnect Protection.**

Route and port forward traffic across your servers with persistent TCP/UDP tunnels and zero downtime.

---

## ⚡ How It Works

```
                        [ Internet / Public Users ]
                                    │
                                    │ (Traffic: Port 24, 80, 443, 25565, 9090, 1-65535...)
                                    ▼
                 ┌──────────────────────────────────────┐
                 │            Gateway Server            │
                 │    (Receives traffic on Public IP)   │
                 └──────────────────┬───────────────────┘
                                    │
                                    │ 24/7 High-Performance Tunnel
                                    ▼
                 ┌──────────────────────────────────────┐
                 │             Node Server              │
                 │    (Runs your Games, Web, Apps, SSH) │
                 └──────────────────────────────────────┘
```

---

## 🚀 1-Command Installation

### Step 1: On your Gateway Server

Run:
```bash
curl -sSL https://iproute.vampirenodes.in | sudo bash -s -- gateway
```
*(Or if cloned locally: `sudo bash vampire.sh gateway`)*

**What it does automatically:**
- Auto-detects public IPv4.
- Generates a secure authorization token.
- Sets up and enables the 24/7 routing gateway service.
- **Outputs the ready-to-use 1-line command for your Node server.**

---

### Step 2: On your Node Server

Copy and run the command printed by Step 1:
```bash
curl -sSL https://iproute.vampirenodes.in | sudo bash -s -- node --server <GATEWAY_IP> --token <SECRET_TOKEN>
```

**Once connected:**
- Ports `80` (HTTP), `443` (HTTPS), `25565` (Minecraft), and `9090` (Success Page) are live immediately.
- Verification page is accessible at `http://<GATEWAY_IP>:9090`.

---

## 🔑 SSH Setup on Port 24

To access your server via SSH on port 24 with root login and password authentication:

```bash
sudo vampire setup ssh
```

**What it does automatically:**
- Configures SSH daemon to listen on **Port 24**.
- Enables `PermitRootLogin yes`.
- Enables `PasswordAuthentication yes`.
- Prompts you to set/update the root password.
- Restarts the SSH service cleanly.
- Forwards port 24 through the tunnel to your Gateway.
- Prints the exact connection command:
  ```bash
  ssh root@<GATEWAY_IP> -p 24
  ```

---

## 🌐 Port Forwarding

### Forward ALL Ports (1-65535)

To forward all TCP and UDP ports:
```bash
sudo vampire add all
```

### Forward Custom Ports

To forward any specific single port:
```bash
sudo vampire add <port> [tcp|udp|both]
```

**Examples:**
```bash
sudo vampire add 25565        # Minecraft (TCP + UDP)
sudo vampire add 30120 tcp    # FiveM TCP
sudo vampire add 8211 udp     # Palworld / Rust UDP
```

To stop forwarding a port:
```bash
sudo vampire remove <port>
sudo vampire remove all       # Remove all-ports range
```

---

## 🛡️ 24/7 Disconnect Protection & App Daemonizer

Prevent SSH disconnects from closing your processes, tunnels, and servers:

```bash
sudo vampire 247
```
- Enables user lingering so processes survive SSH logout.
- Configures systemd-logind (`KillUserProcesses=no`).
- Tunes TCP keepalive (60s probe cycles).
- Enables 30-second auto-healing watchdog service.

### Run Any Server / Game 24/7

Daemonize any app or game into an auto-restarting background systemd service:
```bash
sudo vampire 247 run "java -Xmx4G -jar server.jar nogui"
```

---

## 📋 Commands Reference

| Command | Description |
| :--- | :--- |
| `sudo vampire gateway` | Setup Gateway Server |
| `sudo vampire node --server <IP> --token <TOKEN>` | Connect Node Server |
| `sudo vampire setup ssh` | Configure SSH on port 24 (root + password) |
| `sudo vampire add all` | Forward all 65,535 TCP & UDP ports |
| `sudo vampire add <port> [proto]` | Forward a specific port (`tcp`, `udp`, or `both`) |
| `sudo vampire remove <port\|all>` | Stop forwarding a port |
| `sudo vampire 247` | Enable 24/7 uptime & anti-SSH-disconnect shield |
| `sudo vampire 247 app` | Interactive 24/7 service daemonizer wizard |
| `sudo vampire status` | Check service health & active forwarded routes |
| `sudo vampire logs` | View real-time tunnel logs |
| `sudo vampire page` | Start success test page on Port 9090 |
| `sudo vampire update` | Update vampire script to latest release |
| `sudo vampire uninstall` | Completely uninstall vampire services |

---

## 🌐 Success Verification Page

When the Node connects, the success test page is served on port 9090:
```
http://<GATEWAY_IP>:9090
```
