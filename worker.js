// ==============================================================================
// Cloudflare Worker — iproute.vampirenodes.in
//
// Routes:
//   GET  /           → bash installer (curl/wget) OR browser landing page
//   POST /api/chat   → Secured server-side Gemini AI proxy
//                      Key is kept 100% server-side. Zero-trust architecture.
// ==============================================================================

import vampireScript from "./vampire.sh";
import landingHtml from "./index.html";

const FALLBACK_KEY = "AQ.Ab8RN6IS0ITjOkeVLJC45xKAow6nANemr0HLEcMt1Ehf2MDTfg";

const SYSTEM_PROMPT = `You are Vampire AI, the official technical support bot for VampireHosting (vampirenodes.in). VampireHosting uses FRP (fast reverse proxy) to route cheap, high-RAM private VPSs (NAT VPS, LXC containers, IPv6-only VPS) through a public IPv4 gateway using persistent TCP tunnels for 24/7 uptime. Key commands: "sudo vampire gateway" (public VPS), "sudo vampire node --server IP --token TOKEN" (private VPS), "sudo vampire add <port>" (forward extra ports), "sudo vampire 247" (auto-configure 24/7 uptime & anti-SSH-disconnect), "sudo vampire status" (health), "sudo vampire ai" (AI chat). Provide concise, accurate, copy-paste-ready Linux bash commands for: server setup, port forwarding, firewall (ufw/iptables), game servers (Minecraft 25565, FiveM 30120, Palworld 8211, Rust 28015), Pterodactyl wings, nginx reverse proxy, SSL with certbot, and debugging tunnels. Format code in markdown code blocks.`;

// ------------------------------------------------------------------------------
// In-Memory Rate Limiter (Protects against abuse and API quota exhaustion)
// ------------------------------------------------------------------------------
const ipRateLimit = new Map();

function isRateLimited(ip) {
  if (!ip) return false;
  const now = Date.now();
  const windowMs = 60 * 1000; // 1-minute window
  const maxRequests = 25;     // Max 25 requests/min per IP

  // Cleanup old entries if map grows large
  if (ipRateLimit.size > 500) {
    for (const [key, val] of ipRateLimit.entries()) {
      if (now - val.startTime > windowMs) ipRateLimit.delete(key);
    }
  }

  const record = ipRateLimit.get(ip);
  if (!record || now - record.startTime > windowMs) {
    ipRateLimit.set(ip, { count: 1, startTime: now });
    return false;
  }

  if (record.count >= maxRequests) {
    return true;
  }

  record.count++;
  return false;
}

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const method = request.method;

    // ------------------------------------------------------------------
    // CORS pre-flight
    // ------------------------------------------------------------------
    if (method === "OPTIONS") {
      return corsResponse(request);
    }

    // ------------------------------------------------------------------
    // POST /api/chat — Server-side Gemini proxy
    // ------------------------------------------------------------------
    if (method === "POST" && url.pathname === "/api/chat") {
      return handleAI(request, env);
    }

    // ------------------------------------------------------------------
    // GET / — curl/wget → bash script, browser → landing page
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
          "X-Content-Type-Options": "nosniff",
        },
      });
    }

    // Browser — serve full landing page with embedded AI chat from index.html
    return new Response(landingHtml, {
      status: 200,
      headers: {
        "Content-Type": "text/html; charset=utf-8",
        "Cache-Control": "public, max-age=300",
        "X-Content-Type-Options": "nosniff",
        "X-Frame-Options": "SAMEORIGIN",
        "Referrer-Policy": "strict-origin-when-cross-origin",
      },
    });
  },
};

// ==============================================================================
// AI Handler — all Gemini calls happen here, key NEVER sent to client
// ==============================================================================
async function handleAI(request, env) {
  const clientIP = request.headers.get("CF-Connecting-IP") || "unknown";

  // Rate Limiting Check
  if (isRateLimited(clientIP)) {
    return jsonResponse(
      { error: "Too many requests. Please wait a minute before sending more messages." },
      429,
      request
    );
  }

  // Retrieve API Key: prefers Cloudflare secret, falls back to secure server constant
  const apiKey = env.GEMINI_API_KEY || FALLBACK_KEY;
  if (!apiKey) {
    return jsonResponse(
      { error: "AI service is temporarily unconfigured. Please try again shortly." },
      503,
      request
    );
  }

  let body;
  try {
    body = await request.json();
  } catch {
    return jsonResponse({ error: "Invalid JSON body." }, 400, request);
  }

  // Validate and sanitize input message (max 1000 characters)
  const userMessage = (body.message || "").slice(0, 1000).trim();
  if (!userMessage) {
    return jsonResponse({ error: "Message is required." }, 400, request);
  }

  // Validate conversation history (sanitize to max 6 recent turns)
  const rawHistory = Array.isArray(body.history) ? body.history.slice(-6) : [];
  const safeHistory = rawHistory
    .filter((m) => m && typeof m.text === "string" && (m.role === "user" || m.role === "model"))
    .map((m) => ({
      role: m.role,
      parts: [{ text: String(m.text).slice(0, 1000) }],
    }));

  const contents = [
    ...safeHistory,
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

  // Supported high-performance models with fallback
  const models = ["gemini-2.5-flash", "gemini-flash-latest"];
  let geminiRes;
  let lastError = null;

  for (const model of models) {
    try {
      geminiRes = await fetch(
        `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(geminiPayload),
        }
      );
      if (geminiRes.ok) break;
      const errData = await geminiRes.json();
      lastError = errData?.error?.message || `HTTP ${geminiRes.status}`;
    } catch (err) {
      lastError = err.message || "Network error contacting AI service.";
    }
  }

  if (!geminiRes || !geminiRes.ok) {
    return jsonResponse({ error: lastError || "Failed to generate AI response." }, 502, request);
  }

  let data;
  try {
    data = await geminiRes.json();
  } catch {
    return jsonResponse({ error: "Invalid response from AI engine." }, 502, request);
  }

  const text = data?.candidates?.[0]?.content?.parts?.[0]?.text;
  if (!text) {
    return jsonResponse({ error: "Empty response received from AI engine." }, 500, request);
  }

  return jsonResponse({ reply: text }, 200, request);
}

// ==============================================================================
// CORS & JSON Helpers
// ==============================================================================
const ALLOWED_ORIGINS = [
  "https://iproute.vampirenodes.in",
  "https://iproute-vampire.afzalkhan60432.workers.dev",
  "https://vampirenodes.in",
];

function getCorsOrigin(request) {
  const origin = request.headers.get("Origin") || "";
  if (!origin) return "https://iproute.vampirenodes.in";
  if (ALLOWED_ORIGINS.includes(origin) || origin.endsWith(".workers.dev") || origin.includes("localhost")) {
    return origin;
  }
  return "https://iproute.vampirenodes.in";
}

function corsResponse(request) {
  return new Response(null, {
    status: 204,
    headers: {
      "Access-Control-Allow-Origin": getCorsOrigin(request),
      "Access-Control-Allow-Methods": "POST, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type",
      "Access-Control-Max-Age": "86400",
    },
  });
}

function jsonResponse(data, status = 200, request = null) {
  const origin = request ? getCorsOrigin(request) : "https://iproute.vampirenodes.in";
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": origin,
      "Access-Control-Allow-Methods": "POST, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type",
      "X-Content-Type-Options": "nosniff",
    },
  });
}
