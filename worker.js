// ==============================================================================
// Cloudflare Worker — iproute.vampirenodes.in
//
// Routes:
//   GET  /           → bash installer (curl/wget) OR browser landing page
//   POST /api/chat   → Proxies Gemini AI using GEMINI_API_KEY secret
//                      Key is NEVER exposed to the browser. Zero-trust design.
// ==============================================================================

import vampireScript from "./vampire.sh";
import landingHtml from "./index.html";

const SYSTEM_PROMPT = `You are Vampire AI, the official technical support bot for VampireHosting (vampirenodes.in). VampireHosting uses FRP (fast reverse proxy) to route cheap, high-RAM private VPSs (NAT VPS, LXC containers, IPv6-only VPS) through a public IPv4 gateway using persistent TCP tunnels for 24/7 uptime. Key commands: "sudo vampire gateway" (public VPS), "sudo vampire node --server IP --token TOKEN" (private VPS), "sudo vampire add <port>" (forward extra ports), "sudo vampire status" (health), "sudo vampire ai" (AI chat). Provide concise, accurate, copy-paste-ready Linux bash commands for: server setup, port forwarding, firewall (ufw/iptables), game servers (Minecraft 25565, FiveM 30120, Palworld 8211, Rust 28015), Pterodactyl wings, nginx reverse proxy, SSL with certbot, and debugging tunnels. Format code in markdown code blocks.`;

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const method = request.method;

    // ------------------------------------------------------------------
    // CORS pre-flight (needed for fetch() from same-origin Worker pages)
    // ------------------------------------------------------------------
    if (method === "OPTIONS") {
      return corsResponse();
    }

    // ------------------------------------------------------------------
    // POST /api/chat — Server-side Gemini proxy (key is a CF secret)
    // ------------------------------------------------------------------
    if (method === "POST" && url.pathname === "/api/chat") {
      return handleAI(request, env);
    }

    // ------------------------------------------------------------------
    // GET / — curl → bash script, browser → landing page
    // ------------------------------------------------------------------
    const userAgent = request.headers.get("User-Agent") || "";
    const accept    = request.headers.get("Accept") || "";
    const isTerminal = userAgent.includes("curl") ||
                       userAgent.includes("Wget") ||
                       userAgent.includes("wget") ||
                       (!accept.includes("text/html") && !accept.includes("*/*"));

    if (isTerminal) {
      // Strip UTF-8 BOM if present and ensure clean LF line endings for bash
      const cleanScript = vampireScript.replace(/^\uFEFF/, "").replace(/\r\n/g, "\n");
      return new Response(cleanScript, {
        status: 200,
        headers: {
          "Content-Type": "text/plain; charset=utf-8",
          "Cache-Control": "no-cache",
        },
      });
    }

    // Browser — serve full landing page with embedded AI chat from index.html
    return new Response(landingHtml, {
      status: 200,
      headers: {
        "Content-Type": "text/html; charset=utf-8",
        "Cache-Control": "public, max-age=300",
      },
    });
  },
};

// ==============================================================================
// AI Handler — all Gemini calls happen here, key NEVER sent to client
// ==============================================================================
async function handleAI(request, env) {
  // Rate-limit guard (basic)
  const apiKey = env.GEMINI_API_KEY;
  if (!apiKey) {
    return jsonResponse({ error: "AI service is not configured. Add GEMINI_API_KEY secret via wrangler." }, 503);
  }

  let body;
  try {
    body = await request.json();
  } catch {
    return jsonResponse({ error: "Invalid JSON body." }, 400);
  }

  const userMessage = (body.message || "").slice(0, 2000).trim();
  if (!userMessage) {
    return jsonResponse({ error: "Message is required." }, 400);
  }

  // Build conversation history for multi-turn (optional, sent from browser)
  const history = Array.isArray(body.history) ? body.history.slice(-8) : [];
  const contents = [
    ...history.map((m) => ({
      role: m.role,
      parts: [{ text: m.text }],
    })),
    { role: "user", parts: [{ text: userMessage }] },
  ];

  const geminiPayload = {
    system_instruction: { parts: [{ text: SYSTEM_PROMPT }] },
    contents,
    generationConfig: {
      temperature: 0.3,
      maxOutputTokens: 1024,
    },
  };

  let geminiRes;
  try {
    geminiRes = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=${apiKey}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(geminiPayload),
      }
    );
  } catch (err) {
    return jsonResponse({ error: "Network error contacting AI service." }, 502);
  }

  const data = await geminiRes.json();

  if (!geminiRes.ok) {
    const msg = data?.error?.message || "Gemini API error";
    return jsonResponse({ error: msg }, geminiRes.status);
  }

  const text = data?.candidates?.[0]?.content?.parts?.[0]?.text;
  if (!text) {
    return jsonResponse({ error: "Empty response from AI." }, 500);
  }

  return jsonResponse({ reply: text });
}
