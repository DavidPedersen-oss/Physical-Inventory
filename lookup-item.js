// netlify/functions/lookup-item.js
//
// Reads from the Netlify Blobs cache (populated by refresh-cache.js) for
// instant lookups. Falls back to the live Power Automate flow only if
// the cache is missing/empty, so the form never fully breaks.

const { getStore } = require("@netlify/blobs");

const CACHE_KEY = "item-cache";
const FALLBACK_FLOW_URL = process.env.POWER_AUTOMATE_LOOKUP_URL; // optional fallback

exports.handler = async function handler(event) {
  if (event.httpMethod !== "POST") {
    return json(405, { error: "Method not allowed" });
  }

  let payload;
  try {
    payload = JSON.parse(event.body || "{}");
  } catch {
    return json(400, { error: "Invalid JSON body." });
  }

  const itemCode = String(payload.itemCode || "").trim();
  if (!itemCode) {
    return json(400, { error: "itemCode is required." });
  }

  const normalizedCode = itemCode.toLowerCase();

  // ── Try the cache first ──────────────────────────────────────────────
  try {
    const store = getStore({ name: "lostfound-cache", consistency: "strong" });
    const cache = await store.get(CACHE_KEY, { type: "json" });

    if (cache && cache.items && cache.items[normalizedCode]) {
      const item = cache.items[normalizedCode];
      return json(200, {
        success: true,
        itemCode:      item.itemCode,
        description:   item.description,
        category:      item.category,
        foundLocation: item.foundLocation,
        source: "cache",
        cacheUpdatedAt: cache.updatedAt
      });
    }

    // Cache exists but item not found in it
    if (cache && cache.items) {
      return json(200, {
        success: false,
        message: `No item found for code "${itemCode}".`,
        source: "cache",
        cacheUpdatedAt: cache.updatedAt
      });
    }
    // else: cache is empty/missing — fall through to live lookup below
  } catch (error) {
    console.error("Cache read failed:", error.message);
    // fall through to live lookup
  }

  // ── Fallback: live Power Automate lookup (only if cache unavailable) ──
  if (!FALLBACK_FLOW_URL) {
    return json(200, {
      success: false,
      message: "Item cache is empty and no fallback lookup is configured. Please refresh the item cache."
    });
  }

  try {
    const response = await fetch(FALLBACK_FLOW_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ itemCode })
    });

    const text = await response.text();
    const data = parseResponse(text);

    if (!response.ok) {
      return json(response.status, { error: data.error || data.message || "Lookup flow failed." });
    }

    return json(200, { ...data, source: "live" });
  } catch (error) {
    return json(502, { error: `Lookup request failed: ${error.message}` });
  }
};

function parseResponse(text) {
  if (!text) return {};
  try { return JSON.parse(text); } catch { return { message: text }; }
}

function json(statusCode, body) {
  return {
    statusCode,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
    body: JSON.stringify(body)
  };
}
