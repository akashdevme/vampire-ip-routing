// ==============================================================================
// Cloudflare Worker for: iproute.vampirenodes.in
// - When accessed via curl: Returns the raw bash installer script
// - When opened in a browser (HTTP/HTTPS): Shows the VampireHosting Landing Page
// ==============================================================================

const GITHUB_RAW_URL = "https://raw.githubusercontent.com/akashdevme/vampire-ip-routing/main/vampire.sh";

export default {
  async fetch(request, env, ctx) {
    const userAgent = request.headers.get("User-Agent") || "";
    const acceptHeader = request.headers.get("Accept") || "";

    // 1. Detect if request is from curl / wget / terminal
    const isTerminal = userAgent.includes("curl") || userAgent.includes("Wget") || !acceptHeader.includes("text/html");

    if (isTerminal) {
      const res = await fetch(GITHUB_RAW_URL);
      if (!res.ok) {
        return new Response("# Error: Unable to fetch vampire script from GitHub.\n", {
          status: 500,
          headers: { "Content-Type": "text/plain; charset=utf-8" },
        });
      }
      const script = await res.text();
      return new Response(script, {
        status: 200,
        headers: {
          "Content-Type": "text/plain; charset=utf-8",
          "Cache-Control": "public, max-age=180",
        },
      });
    }

    // 2. If opened in a web browser, render the VampireHosting UI page
    const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>VampireHosting — IPv4 Routed & Installed</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Outfit:wght@300;400;600;700;800&family=JetBrains+Mono:wght@400;600&display=swap" rel="stylesheet">
  <style>
    * {
      box-sizing: border-box;
      margin: 0;
      padding: 0;
    }
    body {
      background-color: #09090e;
      color: #e5e5f0;
      font-family: 'Outfit', sans-serif;
      min-height: 100vh;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      position: relative;
      overflow-x: hidden;
      padding: 24px;
    }
    /* Glow Background Accents */
    body::before {
      content: "";
      position: absolute;
      top: -150px;
      left: 50%;
      transform: translateX(-50%);
      width: 600px;
      height: 600px;
      background: radial-gradient(circle, rgba(168, 85, 247, 0.25) 0%, rgba(239, 68, 68, 0.12) 40%, transparent 70%);
      z-index: 0;
      pointer-events: none;
    }
    .card {
      position: relative;
      z-index: 1;
      background: rgba(18, 18, 28, 0.75);
      border: 1px solid rgba(168, 85, 247, 0.3);
      backdrop-filter: blur(20px);
      -webkit-backdrop-filter: blur(20px);
      border-radius: 24px;
      padding: 48px;
      max-width: 680px;
      width: 100%;
      box-shadow: 0 25px 60px -15px rgba(0, 0, 0, 0.8), 0 0 35px -5px rgba(168, 85, 247, 0.2);
      text-align: center;
      animation: fadeIn 0.8s ease-out;
    }
    @keyframes fadeIn {
      from { opacity: 0; transform: translateY(20px); }
      to { opacity: 1; transform: translateY(0); }
    }
    .badge {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      padding: 6px 16px;
      background: rgba(34, 197, 94, 0.15);
      border: 1px solid rgba(34, 197, 94, 0.4);
      color: #4ade80;
      font-size: 0.85rem;
      font-weight: 600;
      border-radius: 999px;
      margin-bottom: 24px;
      letter-spacing: 0.5px;
      text-transform: uppercase;
    }
    .badge-dot {
      width: 8px;
      height: 8px;
      background-color: #22c55e;
      border-radius: 50%;
      box-shadow: 0 0 10px #22c55e;
      animation: pulse 2s infinite;
    }
    @keyframes pulse {
      0%, 100% { opacity: 1; transform: scale(1); }
      50% { opacity: 0.4; transform: scale(0.85); }
    }
    .logo {
      font-size: 2.75rem;
      font-weight: 800;
      letter-spacing: -0.5px;
      margin-bottom: 8px;
      background: linear-gradient(135deg, #ffffff 30%, #c084fc 70%, #f43f5e 100%);
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
    }
    .subtitle {
      font-size: 1.15rem;
      color: #94a3b8;
      margin-bottom: 32px;
      line-height: 1.5;
    }
    .feature-grid {
      display: grid;
      grid-template-columns: repeat(3, 1fr);
      gap: 16px;
      margin-bottom: 36px;
    }
    @media (max-width: 600px) {
      .feature-grid { grid-template-columns: 1fr; }
      .card { padding: 32px 20px; }
    }
    .feature-box {
      background: rgba(25, 25, 38, 0.6);
      border: 1px solid rgba(255, 255, 255, 0.08);
      border-radius: 16px;
      padding: 16px;
      text-align: center;
      transition: all 0.3s ease;
    }
    .feature-box:hover {
      border-color: rgba(168, 85, 247, 0.4);
      transform: translateY(-2px);
    }
    .feature-num {
      font-size: 1.4rem;
      font-weight: 700;
      color: #c084fc;
      margin-bottom: 4px;
    }
    .feature-desc {
      font-size: 0.8rem;
      color: #94a3b8;
      font-weight: 500;
    }
    .cmd-box {
      background: #0d0d15;
      border: 1px solid rgba(168, 85, 247, 0.25);
      border-radius: 14px;
      padding: 14px 18px;
      text-align: left;
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 12px;
      font-family: 'JetBrains Mono', monospace;
      font-size: 0.85rem;
      color: #e2e8f0;
      margin-bottom: 24px;
    }
    .cmd-text {
      overflow-x: auto;
      white-space: nowrap;
      scrollbar-width: none;
    }
    .cmd-text::-webkit-scrollbar { display: none; }
    .copy-btn {
      background: #7e22ce;
      color: #ffffff;
      border: none;
      padding: 8px 14px;
      border-radius: 8px;
      font-size: 0.8rem;
      font-weight: 600;
      cursor: pointer;
      font-family: 'Outfit', sans-serif;
      transition: background 0.2s;
      flex-shrink: 0;
    }
    .copy-btn:hover {
      background: #9333ea;
    }
    .footer {
      font-size: 0.85rem;
      color: #64748b;
    }
    .footer a {
      color: #c084fc;
      text-decoration: none;
    }
  </style>
</head>
<body>
  <div class="card">
    <div class="badge">
      <div class="badge-dot"></div>
      VampireHosting IPv4 Installed & Active
    </div>
    <h1 class="logo">VampireHosting</h1>
    <p class="subtitle">High-RAM Private Node Successfully Connected to Public IPv4.</p>

    <div class="feature-grid">
      <div class="feature-box">
        <div class="feature-num">65,535</div>
        <div class="feature-desc">All Ports Routed</div>
      </div>
      <div class="feature-box">
        <div class="feature-num">TCP + UDP</div>
        <div class="feature-desc">Full Protocol Support</div>
      </div>
      <div class="feature-box">
        <div class="feature-num">&lt; 1 ms</div>
        <div class="feature-desc">Kernel WireGuard Speed</div>
      </div>
    </div>

    <div class="cmd-box">
      <span class="cmd-text">curl -sSL https://iproute.vampirenodes.in | sudo bash</span>
      <button class="copy-btn" onclick="navigator.clipboard.writeText('curl -sSL https://iproute.vampirenodes.in | sudo bash'); this.innerText='Copied!'; setTimeout(()=>this.innerText='Copy', 2000)">Copy</button>
    </div>

    <div class="footer">
      Powered by <a href="https://vampirenodes.in" target="_blank">VampireNodes.in</a> — Instant Public IPv4 Routing for High-RAM VPS
    </div>
  </div>
</body>
</html>`;

    return new Response(html, {
      status: 200,
      headers: {
        "Content-Type": "text/html; charset=utf-8",
        "Cache-Control": "public, max-age=60",
      },
    });
  },
};
