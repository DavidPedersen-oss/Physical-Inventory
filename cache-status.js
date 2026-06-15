// netlify/functions/cache-status.js
//
// GET endpoint to check when the item cache was last refreshed and how
// many items it contains. Useful for a small status indicator or for
// debugging ("is the cache stale?").

const { getStore } = require("@netlify/blobs");

const CACHE_KEY = "item-cache";

exports.handler = async function handler(event) {
  if (event.httpMethod !== "GET") {
    return json(405, { error: "Method not allowed" });
  }

  try {
    const store = getStore({ name: "lostfound-cache", consistency: "strong" });
    const cache = await store.get(CACHE_KEY, { type: "json" });

    if (!cache) {
      return json(200, { exists: false, message: "Cache has not been populated yet." });
    }

    return json(200, {
      exists: true,
      updatedAt: cache.updatedAt,
      count: cache.count
    });
  } catch (error) {
    return json(500, { error: `Failed to read cache: ${error.message}` });
  }
};

function json(statusCode, body) {
  return {
    statusCode,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
    body: JSON.stringify(body)
  };
}
