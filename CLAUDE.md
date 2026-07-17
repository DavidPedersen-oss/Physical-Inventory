# CLAUDE.md

Reference for future Claude Code sessions working on this repo. See `README.md` for end-user/deployment docs — this file is about how the code is built.

## What this is

Beach Asset Management — a single-page PWA for CSULB Property Management's asset lookup + physical inventory audit. No build step, no framework, no bundler. **The entire app is `index.html`** (HTML + CSS + JS in one file, ~1750 lines). It's deployed by copying files to GitHub Pages.

Data lives in the browser (IndexedDB) and optionally syncs to SharePoint Lists through two Power Automate HTTP-triggered flows (see README section 3). The app works fully offline; sync is additive, not required.

## File map

| Path | What it is |
|---|---|
| `index.html` | The whole app: `<style>` block, HTML shell, then one big `<script>` |
| `sw.js` | Minimal service worker — offline cache for the app shell |
| `manifest.json`, `icon-*.png` | PWA metadata (Add to Home Screen) |
| `seed/*.json` | Bundled starter data (assets, disposed assets, departments, users) — loaded into IndexedDB on first boot, and by "Nuke & rebuild data" |
| `sharepoint-import/*.csv`, `Create-SharePointLists.ps1` | One-time SharePoint provisioning — CSVs to import, or a PnP PowerShell script that does it in one shot |

There is no `package.json`, no `node_modules`, no test runner. Two CDN scripts (PapaParse, SheetJS/xlsx) are the only external dependencies, loaded via `<script src>` in `<head>`.

## Why single-file

This is deliberate, not legacy debt: it means "download this folder, turn on GitHub Pages, it works" with zero build tooling for a small team that doesn't want to run npm. When adding features, **keep everything in `index.html`** unless the user asks to change that. Do not introduce a bundler, framework, or package.json without discussing it first.

Within that constraint, prefer generating markup from JS template strings (the existing pattern — see any `render*` function) over hand-written static HTML. Nearly all UI in this app is built by JS `innerHTML` assignment, not markup sitting in the `<body>`. The `<body>` only holds the login screen and the app shell (header/nav/main slot) — everything else is rendered per-route.

## Global state: `ST`

One mutable object, `ST`, holds all runtime state (assets, departments, users, session, current filters, sync queue length, theme, etc.) — see its declaration near the top of the `<script>` block. There's no state management library; functions read/write `ST` directly and call `render()` or a specific `render*` function to redraw.

## Storage: IndexedDB (`beachprop` database)

Four object stores (schema version bumped to `2` when `photos` was added):
- `kv` — arbitrary key→value (config, theme, session, depts, users, sync log, last-sync time)
- `assets` — keyed by `id` (the numeric Asset ID with leading zeros stripped); holds both active (`lc:'A'`) and disposed (`lc:'D'`) records in the same store
- `queue` — pending sync operations (`kind: 'upsert' | 'audit' | 'import'`), auto-incrementing `qid`, drained by `syncNow()`
- `photos` — keyed by asset `id` → a downscaled JPEG data URL; **local-only, never synced to SharePoint** (no column for it in the flows/lists)

Helper functions are thin promise wrappers: `kvGet/kvSet`, `dbAllAssets/dbPutAsset/dbPutAssets/dbClearAssets`, `qAdd/qAll/qPut/qDel/qClear`, `phGet/phPut/phDel/phAllKeys/phAll`. Always go through these rather than opening new transactions inline.

## Routing / rendering

Hash-based router, no history API tricks. `location.hash = '#/route/param'` → `parseRoute()` splits it → `ST.route` → `render()` dispatches to the matching `render*(m)` function, where `m` is the `<main>` element. Adding a page:

1. Write `renderFoo(m){ m.innerHTML = `...`; /* wire up listeners */ }`
2. Add a branch in `render()`'s if/else chain
3. Add an entry to `NAV`/`NAV_M` (top-level) or `TOOLS` (under "More"/side nav "Tools" section) near the bottom of the script, with an icon from the `I` object

Every `render*` function fully replaces its container's `innerHTML` and rebinds event listeners each call — there's no diffing, no component tree. This is intentional; keep new pages consistent with that pattern rather than introducing partial updates.

## Sync contract (do not break silently)

- Assets are pushed to SharePoint as `spShape(a)` — a flattened subset of fields, with `history` JSON-stringified. Disposed assets (`lc==='D'`) are **never** pushed (see `saveAsset`) — they're local reference data only.
- The app POSTs as `Content-Type: text/plain` on purpose (`syncNow()`), so browsers skip CORS preflight, which Power Automate's HTTP trigger can't answer. Don't change that content type without re-reading README section 3's CORS note.
- Every flow Response action must send `Access-Control-Allow-Origin: *`, or `fetch()` fails with an opaque CORS error client-side.
- `pullData()` expects the read flow's JSON body shaped exactly `{ok, assets[], departments[], users[]}` with the field names listed in README section 3 — changing the app's field names means updating the Power Automate `Select` actions too, and vice versa.
- User accounts added on-device (`local:true` in `ST.users`) are pushed as a `userUpserts` array on the first POST batch of every `syncNow()` until acknowledged. The `local` flag is cleared **only** when the write flow's response includes `usersProcessed > 0` — a flow without the userUpserts step ignores the field, the app logs a "Write flow ignored N pending user account(s)" sync-log entry, and the Users page keeps showing the row as pending (with a manual paste-row fallback). Don't clear `local` on a plain `{ok:true}` response; that would silently strand accounts. The pull merge also clears pending state naturally: once the username appears in the pulled `users[]`, the shared row replaces the local one.
- Pull merge rule: an incoming asset is skipped if it has a pending local `upsert` queued (`pendingIds` in `pullData`) — local unsynced edits always win over a pull, never the other way around.

## Conventions to follow when editing

- Terse, dense style: `$`/`$$` for `querySelector(All)`, arrow functions, minimal whitespace, no semicolons-as-a-rule (mixed but consistent within a statement). Match the existing density rather than reformatting to a more verbose house style.
- `esc()` every piece of user/data-controlled text interpolated into `innerHTML`. This app has no framework escaping — a missed `esc()` is an XSS hole (e.g. asset descriptions, notes, custodian names all come from imported spreadsheets).
- `toast(msg, isError)` for user feedback, `confirmDlg(title, body, okLabel, danger)` (returns a Promise<boolean>) for anything destructive — see `promptNuke()` for the pattern: warn about pending unsynced changes, require explicit confirm, never silently destroy local data.
- New destructive/local-only actions should go in Settings → Data, alongside "Nuke & rebuild data" and "Reset this device" — and should be exposed as a command-palette entry too (see `CMDS()`).
- Colors/spacing/radii are CSS custom properties (`--gold`, `--ink`, `--radius`, etc.) defined per-theme in `:root`/`[data-theme="light"]`/`[data-theme="dark"]` — never hardcode a hex color in new markup; use the existing variables so dark mode stays correct.

## Notable subsystems (build 4.0 "Horizon")

- **Design system**: Modern-SaaS restyle ("Horizon", replacing "Shoreline") — Inter + JetBrains Mono via Google Fonts, 12px radii, layered `--shadow-*` tokens, `--spring`/`--ease` motion curves, staggered `fadeUp` entrance animations (`main.page-in`, list `nth-child` delays), hover-lift on `.card`/`.srow`/`.dept-row`. All pre-existing class names were kept; only the `<style>` block's look changed.
- **Auctions tab** (`renderAuctions`): view over `ST.surveyGroups` filtered to groups with an item whose `act` matches /auction/i (`isAuctionItem`/`auctionGroups`). Own filter state `ST.aflt`. Nav is now sectioned (`NAV_SECTIONS`): Assets / Field work / Disposals / Tools.
- **Ask AI (DeepSeek)** (`renderAsk`, `askDeepSeek`): optional; needs `ST.cfg.dsKey` (Settings → AI assistant, saved in kv `cfg`, device-local). OpenAI-compatible function calling against `https://api.deepseek.com/chat/completions` with two local tools (`query_surveys`, `query_assets` in `runAiTool`) that run over `ST` and return counts + ≤5 samples — the raw dataset is never sent. Chat state in `ST.ai` (in-memory only). sw.js never caches deepseek.com.
- **Loading quips** (`QUIPS`/`quip()`/`loadingHTML()`): playful randomized loading messages used by nuke, imports, survey-history loads, and the AI thinking bubble.
- **Cross-device settings**: boot() applies a one-time `#setup=BASE64` hash link (Settings → "Copy setup link") and auto-fills blanks from an optional repo-committed `seed/config.json` (see `seed/config.example.json`; committing real flow URLs/keys makes them readable to anyone who can see the repo/site). Existing device settings are never overwritten by the file.
- **Survey type filter + sort** (`ACT_BUCKETS`/`actBucket`): normalizes the messy raw `act` spellings (EWASTE/E-WASTE, REYCLE…) into buckets (ewaste, recycle, auction, donation, transfer, reuse, lost, cancel) exposed as a Type chip row and used by `surveyMeta().bks`; sort dropdown in `ST.sflt.sort` (new/old/no/items).
- **Survey check-in mode** (`SURV_EDITS`/`saveSurvEdit`/`applySurvEdits`, toggle `ST.svChkMode`): per-line-item checked-in flag + description/serial/notes overrides, keyed by the item's globally-unique `k`, stored in kv `survEdits` (device-local; survives Nuke & rebuild; included in the JSON backup). Overrides are applied in `buildSurveyIndex()` before matching, so an edited serial can re-link an item to an asset.

## Notable subsystems (added on `feature/easier-setup-and-tools`)

- **Nuke & rebuild data** (`nukeAndReseed()` / `promptNuke()`): wipes local `assets`+`queue` stores and re-fetches `seed/*.json` fresh, then re-pulls SharePoint if configured. Deliberately *lighter* than "Reset this device" (which also wipes session/config/theme) — it's for "my local data looks wrong" without losing sign-in/sync setup. Local-only by design; does not touch SharePoint. Photos are untouched (they key off asset ID, which is stable across a reseed).
- **Command palette** (`openCmdPalette()`, bound to Ctrl/Cmd+K and the header `⌘K` button): static command list from `CMDS()` plus live asset search results via the existing `searchAssets()`. Add new global actions to `CMDS()`, not as one-off keybinds.
- **Barcode/QR scanner** (`openScanner()`): uses the browser `BarcodeDetector` API (Chromium only — Chrome/Edge desktop and Android; not Safari/iOS) via `getUserMedia`. Always feature-detect (`'BarcodeDetector' in window`) and fail with a clear toast, never a silent no-op.
- **Photo attachments**: local-only, per-asset, stored downscaled (`downscaleImage()`, max 1280px / JPEG q≈0.72) to keep IndexedDB size sane. Included in the "Backup everything (JSON)" export under a `photos` map; intentionally excluded from CSV/XLSX exports and from the SharePoint sync payload.
- **Dashboard charts** (`svgDonut()`, `divCompletion()` in the stats render): hand-rolled inline SVG, no charting library. Follow this pattern (plain SVG generated by a small JS function) for future charts rather than adding a dependency.
- **Auction payments** (`parsePaymentReport`/`previewPaymentImport`/`buildPaymentIndex`/`payFor`): imports the Public Surplus **Payment Collection Report** (`.xls`, BIFF — SheetJS reads it) via the Import page. Detected in `detectWbType` (returns `'payment'`; header sits several rows below a title banner, so it scans the first ~12 rows). Line rows are matched to surveys by **survey #** = report column F "Item Code/Tag" (`payNorm` strips non-alnum, both sides), stored device-local in kv `auctionPayRows` and aggregated per survey # into `ST.auctionPay` (Map keyed by normalized #). Natural dedup/update key is `payKey` = `rcpt|lot|code`, so re-importing a newer report fills in ACH refs for auctions that have since closed (later row wins). Shown on the survey detail page (payments card), auction/survey rows (💵 total pill), and the Auctions "Collected" KPI. Never synced to SharePoint; included in the JSON backup (`auctionPay`); cleared via `clearPayments()` (Settings → Data + command palette). Money strings like `"$ 4,300.00"` are handled by `payNum`.

## Testing

There's no automated test suite. Verify changes by serving the folder statically (e.g. `python -m http.server` or `npx serve`) and exercising the feature in a real browser — sign-in requires WebCrypto, which requires `https:` or `localhost` (see `boot()`'s check). Camera-based features (scanner, photo capture) need a real device or desktop browser with a webcam; `BarcodeDetector` is unavailable in Firefox and Safari, so verify graceful fallback there too.
