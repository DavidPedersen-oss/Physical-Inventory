// netlify/functions/refresh-cache.js
//
// Receives the FULL item list from a Power Automate flow and stores it
// in Netlify Blobs so lookup-item.js can answer instantly without
// hitting Excel/Power Automate on every claim form lookup.
//
// Power Automate flow (separate from the submit/lookup flows):
//   1. Trigger: Recurrence (e.g. every 15-30 min) OR manual button
//   2. List rows present in a table (with pagination ON, threshold high
//      enough to cover the whole table — this can take its time since
//      it's not blocking a user request)
//   3. Select action -> map each row to:
//        { "itemCode": item()?['ItemCode'],
//          "description": item()?['ItemDescription'],
//          "category": item()?['Category'],
//          "foundLocation": item()?['Drop-Off / Found Location'] }
//   4. HTTP POST to https://yoursite.netlify.app/.netlify/functions/refresh-cache
//      Body: { "items": <output of Select>, "sharedSecret": "<same secret>" }

const { getStore } = require("@netlify/blobs");

const SHARED_SECRET = process.env.POWER_AUTOMATE_SHARED_SECRET || "";
const CACHE_KEY = "item-cache";

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

  // Simple shared-secret check so randoms can't overwrite the cache
  if (SHARED_SECRET && payload.sharedSecret !== SHARED_SECRET) {
    return json(401, { error: "Unauthorized." });
  }

  const items = payload.items;
  if (!Array.isArray(items)) {
    return json(400, { error: "Body must include an 'items' array." });
  }

  // Build a lookup map keyed by normalized item code for O(1) lookups
  const itemMap = {};
  for (const row of items) {
    const code = String(row.itemCode || "").trim().toLowerCase();
    if (!code) continue;
    itemMap[code] = {
      itemCode:      String(row.itemCode || "").trim(),
      description:   String(row.description || "").trim(),
      category:      String(row.category || "").trim(),
      foundLocation: String(row.foundLocation || "").trim()
    };
  }

  try {
    const store = getStore({ name: "lostfound-cache", consistency: "strong" });
    await store.setJSON(CACHE_KEY, {
      updatedAt: new Date().toISOString(),
      count: Object.keys(itemMap).length,
      items: itemMap
    });

    return json(200, {
      success: true,
      message: `Cache refreshed with ${Object.keys(itemMap).length} items.`,
      count: Object.keys(itemMap).length
    });
  } catch (error) {
    return json(500, { error: `Failed to write cache: ${error.message}` });
  }
};

function json(statusCode, body) {
  return {
    statusCode,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
    body: JSON.stringify(body)
  };
}
