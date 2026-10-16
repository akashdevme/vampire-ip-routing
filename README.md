# 🦇 Vampire Hosting — 1-Command ALL-PORTS Public IP Router

> **Route ALL 65,535 TCP & UDP Ports from a Public IPv4 VPS to any Private/NAT/Non-Public High-RAM VPS in ONE command!**

No more specifying ports one by one (no manual 80, 443, 25565...). Once connected, **any port you open on your high-RAM private VPS is immediately live and accessible on your Public IPv4.**

---

## ⚡ How It Works

```
                        [ Internet / Public Users ]
                                    │
                                    │ (Any Port: 80, 443, 25565, 7777, 8080...)
                                    ▼
                 ┌──────────────────────────────────────┐
                 │          Public IPv4 VPS             │
                 │   (Port 22 SSH kept for management)  │
                 │  ALL other ports → Forwarded to Node │
                 └──────────────────┬───────────────────┘
                                    │
                                    │ WireGuard Fast Tunnel
                                    ▼
                 ┌──────────────────────────────────────┐
                 │    Private / NAT VPS (Large RAM)     │
                 │   (Runs your Games, Web, Apps, DB)   │
                 └──────────────────────────────────────┘
```

---

## 🚀 1-Command Setup

### Step 1: On your Public IPv4 VPS (Gateway)

Run:
```bash
sudo bash vampire.sh gateway
```

**What it does automatically:**
- Auto-detects public IPv4 and network interface.
- Automatically detects and protects your active SSH port (e.g. `22`) so you never get locked out.
- Generates encryption keys for both the server and client.
- Configures kernel routing and `iptables` to forward **ALL 65,535 TCP & UDP ports** to the private node.
- **Prints a ready-to-use 1-line command for your private VPS!**

---

### Step 2: On your Private / Non-Public VPS (Worker Node)

Copy and run the exact command printed by Step 1:
```bash
sudo bash vampire.sh node --server <PUBLIC_IP> --server-key "<SERVER_KEY>" --client-key "<CLIENT_KEY>"
```

*(Or via your branded 1-liner):*
```bash
curl -sSL https://iproute.vampirenodes.in | sudo bash -s -- node --server <PUBLIC_IP> --server-key "<SERVER_KEY>" --client-key "<CLIENT_KEY>"
```

---

## 🎉 Done! Everything is Routed

Now your private high-RAM VPS has the power of the public IPv4:
- Run a web server on port `80`/`443`? Accessible at `http://<PUBLIC_IP>` / `https://<PUBLIC_IP>`.
- Run Minecraft on port `25565`? Players connect to `<PUBLIC_IP>:25565`.
- Run FiveM on port `30120`? Players connect to `<PUBLIC_IP>:30120`.
- Run Palworld / Rust / CS2 on any UDP port? Works automatically.
- Run Docker, databases, or custom apps? All ports work out of the box with **ZERO extra configuration**!

---

## 🛠️ Management Commands

You can run `vampire` from anywhere on either server:
- Ensure 24/7 online uptime & prevent SSH logout from killing services:
  ```bash
  sudo vampire 247
  ```
- Turn any game server or application (Minecraft, Node, Python, FiveM) into a 24/7 background service:
  ```bash
  sudo vampire 247 app
  ```
- Check live tunnel status:
  ```bash
  sudo vampire status
  ```
- Remove and restore original firewall settings:
  ```bash
  sudo vampire uninstall
  ```

---

## 🛡️ Firewall Note
Ensure port `51820` (UDP) is open in your Public VPS cloud provider's firewall / security group (e.g., AWS Security Group, Oracle Cloud VCN ingress rule, DigitalOcean firewall, or UFW):
```bash
sudo ufw allow 51820/udp
```
