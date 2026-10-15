// ==============================================================================
// Cloudflare Worker for: iproute.vampirenodes.in
// Allows running: curl -sSL https://iproute.vampirenodes.in | bash
// ==============================================================================

// Option A: Pull latest script from your GitHub repo automatically
const GITHUB_RAW_URL = "https://raw.githubusercontent.com/akashdevme/vampire-ip-routing/main/vampire.sh";

export default {
  async fetch(request, env, ctx) {
    // Fetch raw bash script
    const res = await fetch(GITHUB_RAW_URL);
    if (!res.ok) {
      return new Response("# Error: Unable to fetch vampire script from GitHub.", {
        status: 500,
        headers: { "Content-Type": "text/plain; charset=utf-8" },
      });
    }

    const script = await res.text();

    return new Response(script, {
      status: 200,
      headers: {
        "Content-Type": "text/plain; charset=utf-8",
        "Cache-Control": "public, max-age=300", // cache for 5 minutes
      },
    });
  },
};
