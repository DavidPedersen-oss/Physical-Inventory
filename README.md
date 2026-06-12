# Beach Asset Management — CSULB Property Management Office

An all-encompassing asset management tool for the Property Management Office: campus-wide asset lookup, the FY 2025–26 **physical inventory** (CSU Policy 1401.00) as a dedicated section, plus **disposed/retired assets** and matched **survey records** as reference data. Runs on **GitHub Pages**, stores shared data in **SharePoint Lists**, and syncs through two **Power Automate** flows. Works offline in the field; changes queue locally and push when you have signal. A change shows "pending" until SharePoint actually accepts it.

Branding follows the CSULB brand guidance: white-first open layout, the yellow/black palette with gray body copy, and no protected university marks (the wordmark here is plain text, so nothing needs clearance from Strategic Communications).

**Sign in:** the bundled starter account is **`david` / `csulb123`** (admin). It works on every device out of the box. **Change this password before sharing the URL**: Users → Add a user → re-enter `david` with a new password, then put the generated row in the SharePoint Users list (it overrides the bundled one after a sync). Login is universal — accounts come from the Users list, not per-device.

**Contents of this package**

| Path | What it is |
|---|---|
| `index.html` | The entire app (works the moment Pages is live) |
| `sw.js`, `manifest.json`, `icon-*.png`, `.nojekyll` | PWA: offline cache + Add to Home Screen |
| `seed/assets.json` | 3,674 active assets (multi-cost rows merged, values summed; survey matches attached) |
| `seed/disposed.json` | 8,311 disposed/retired assets from the disposal summary, 73% with matched survey records |
| `seed/users.json` | Bundled starter login (david) |
| `seed/departments.json` | 151 departments with Div/Org grouping + tracker completion |
| `sharepoint-import/Assets.csv` | Ready to import into the SharePoint **Assets** list |
| `sharepoint-import/Departments.csv` | Ready to import into **Departments** |
| `sharepoint-import/Users.csv` | Column template for **Users** |

**Pre-loaded state:** 78 departments marked complete in the FY25-26 tracker → their **783 assets are seeded as "Verified OK"** with `UpdatedBy = Tracker Import`, so they're distinguishable from field verifications. 5 departments have no name in the tracker (710, 727, 741, 796, 823) and appear under UNASSIGNED — fix them in the Departments list anytime.

**Disposals & surveys:** every screen with asset lists has an **Active / All / Disposed** toggle. Disposed records are read-only reference data kept on each device (loaded from the seed, refreshable by importing a new `LB_AM_DISPOSAL` file) — they are *not* pushed to SharePoint, so the Assets list stays lean and the flows untouched. The Master Survey workbook (all 10 sheets, ~116k rows) was matched against assets by **Asset ID → Tag # → Serial**: 6,089 disposed assets and 473 active assets carry a ⚑ survey badge with survey #, disposal action/condition, dates and notes. New disposal imports won't gain survey matches automatically (the survey index is built at seed time) — re-run the data build if you ever need to refresh that.

---

## 1 · Deploy the app (5 minutes)

1. Create a GitHub repo (e.g. `beach-property`) and upload everything in this folder (keep the `seed/` folder structure).
2. Repo → **Settings → Pages** → Source: *Deploy from a branch* → `main` / root → Save.
3. Open `https://<your-username>.github.io/beach-property/` — the app seeds 3,674 active + 8,311 disposed assets into the device. Sign in as `david` / `csulb123`.

The app is fully usable at this point (search, audit, import, export) — sync just isn't shared yet. On phones: open the URL in Chrome/Safari → **Add to Home Screen** for a full-screen app that works offline.

> Sign-in uses the browser's WebCrypto, which requires HTTPS — always use the `github.io` URL, not a local `file://` copy.

---

## 2 · Create the SharePoint lists (once)

In your CSULB SharePoint site: **New → List**. Column names must match **exactly** and be created **without spaces** (SharePoint freezes the *internal* name at creation — `TagNumber`, never `Tag Number`). Use **Single line of text** for everything except where noted; set EditHistory/Notes/Summary to **Multiple lines of text (plain text)**.

**Assets** — rename the default *Title* column's label to "AssetID" if you like (internal name stays `Title`, which is what the flow uses):

```
Title (= Asset ID)   TagNumber   Dept        DeptName     DivArea
Description (multi)  SerialID    Location    Custodian    Category
AcqDate              InServiceDt PONo        SumAmount (Number)
Status               Notes (multi)           UpdatedBy    LastUpdated
EditHistory (multi)
```

**Departments**: `Title (= dept ID)`, `DeptName`, `DivArea`, `SortOrder (Number)`, `Completed`, `Phase`

**Users**: `Title (= username)`, `DisplayName`, `Role`, `Salt`, `PasswordHash`, `Active` — `sharepoint-import/Users.csv` already contains david's row (with the *current* hash; regenerate from the Users screen after changing the password)

**AuditUpdates** (append-only log): `Title (= AssetID)`, `Field`, `OldValue (multi)`, `NewValue (multi)`, `Status`, `Timestamp`, `User`

**ImportHistory**: `Title (= timestamp)`, `User`, `Filename`, `RowsMatched (Number)`, `RowsAdded (Number)`, `RowsConflicted (Number)`, `Summary (multi)`

**Load the data:** easiest path is *New → List → From CSV* using `sharepoint-import/Assets.csv` and `Departments.csv` (check column types after), or create the lists first and use *Edit in grid view* → paste. 3,674 rows pastes fine in grid view in a few chunks.

---

## 3 · Build the two Power Automate flows

Both use the premium **"When an HTTP request is received"** trigger (you confirmed this is available). Pick a long random **shared key** now (e.g. 30 random characters) — it goes inside both flows and into the app's Settings.

> **CORS rule (important):** every **Response** action in both flows must include a header `Access-Control-Allow-Origin` = `*`. The app sends its POST as `text/plain` specifically so browsers skip the preflight that Power Automate can't answer. Don't change that contract.

### Flow 1 — `BeachProperty-GetData` (read)

1. **Trigger:** When an HTTP request is received → Method: **GET**. Leave schema empty.
2. **Condition:** expression `triggerOutputs()?['queries']?['k']` **is equal to** your shared key.
   - **If no:** Response → Status 401, header `Access-Control-Allow-Origin: *`, body `{"ok":false,"error":"bad key"}`.
3. **If yes:**
   a. **Get items** (SharePoint, Assets list). In the action's *Settings* (⋯ menu): turn **Pagination ON, threshold 5000** — without this you get 100 rows.
   b. **Select** (Data Operations) — From: `value` of Get items. Map (left = key typed exactly, right = dynamic content / expression):

      | Key | Value |
      |---|---|
      | id | Title |
      | tag | TagNumber |
      | dept | Dept |
      | deptName | DeptName |
      | div | DivArea |
      | desc | Description |
      | serial | SerialID |
      | location | Location |
      | custodian | Custodian |
      | category | Category |
      | acqDate | AcqDate |
      | inServiceDt | InServiceDt |
      | po | PONo |
      | value | SumAmount |
      | status | Status |
      | notes | Notes |
      | updatedBy | UpdatedBy |
      | updatedAt | LastUpdated |
      | history | EditHistory |

   c. **Get items** (Departments) + **Select**: `deptId←Title, name←DeptName, div←DivArea, sortOrder←SortOrder, completed←Completed`.
   d. **Get items** (Users) + **Select**: `username←Title, display←DisplayName, role←Role, salt←Salt, hash←PasswordHash, active←Active`.
   e. **Response** → Status 200, headers `Access-Control-Allow-Origin: *` and `Content-Type: application/json`, body:
      ```json
      {
        "ok": true,
        "assets": @{body('Select')},
        "departments": @{body('Select_2')},
        "users": @{body('Select_3')}
      }
      ```
      (Insert the three Select outputs as dynamic content; action names may differ.)
4. Save, copy the **HTTP GET URL** → this is the app's **Read flow URL**.

### Flow 2 — `BeachProperty-Update` (write)

1. **Trigger:** When an HTTP request is received → Method: **POST**, schema empty.
2. **Parse JSON** (Data Operations) — Content expression: `json(string(triggerBody()))` *(the app posts JSON as text/plain; this parses it either way)*. Schema → *Generate from sample*:
   ```json
   {
     "key": "x", "user": "x",
     "assetUpserts": [ { "id":"1","tag":"","dept":"","deptName":"","div":"","desc":"","serial":"","location":"","custodian":"","category":"","acqDate":"","inServiceDt":"","po":"","value":0,"status":"","notes":"","updatedBy":"","updatedAt":"","history":"" } ],
     "auditLog":  [ { "AssetID":"","Field":"","OldValue":"","NewValue":"","Status":"","Timestamp":"","User":"" } ],
     "importLog": [ { "Timestamp":"","User":"","Filename":"","RowsMatched":0,"RowsAdded":0,"RowsConflicted":0,"Summary":"" } ]
   }
   ```
3. **Condition:** Parse JSON `key` equals your shared key. **If no:** Response 401 with the ACAO header (as above).
4. **If yes — Apply to each** on `assetUpserts`:
   a. **Get items** (Assets) → Filter Query: `Title eq '@{items('Apply_to_each')?['id']}'` → Top Count 1.
   b. **Condition:** expression `length(outputs('Get_items')?['body/value'])` is greater than 0.
      - **Yes → Update item** (Assets). Id: expression `first(outputs('Get_items')?['body/value'])?['ID']`. Title: the upsert's `id`. Map every other column to the matching upsert field (`TagNumber←tag`, `SumAmount←value`, `EditHistory←history`, `LastUpdated←updatedAt`, etc.).
      - **No → Create item** (Assets) with the same field mapping.
5. **Apply to each** on `auditLog` → **Create item** (AuditUpdates): `Title←AssetID`, then Field/OldValue/NewValue/Status/Timestamp/User one-to-one.
6. **Apply to each** on `importLog` → **Create item** (ImportHistory): `Title←Timestamp`, rest one-to-one.
7. **Response** → Status 200, header `Access-Control-Allow-Origin: *`, body:
   ```json
   { "ok": true, "processed": @{length(body('Parse_JSON')?['assetUpserts'])} }
   ```
8. Save, copy the **HTTP POST URL** → the app's **Write flow URL**.

*Tip: in step 4's Apply to each, turn on Concurrency (Settings → degree 10) so big bulk pushes finish faster.*

---

## 4 · Connect the app

On any device: sign in → **Settings** → paste the Read URL, Write URL, and shared key → **Save** → **Test connection** (should toast "Connection OK") → **Sync now**. These live only in the device's storage — never in the GitHub repo, which stays secret-free.

To set up the next auditor's phone in one step: **Copy config code** on your device, send it to them, they tap **Paste config code**.

**Accounts:** add auditors from **Users → Add a user** (admin only): it generates the `Salt` + `PasswordHash` values — paste that row into the **Users** list. After the next sync, that person can sign in on any device with the same credentials. Passwords are hashed with PBKDF2 (200,000 iterations, per-user salt); SharePoint never sees a plaintext password. Note that anything in a public repo is public — the bundled hash can't be reversed to the password, but changing the starter password promptly is still the right move.

---

## 5 · Daily use

- **Search** is the home screen — tokenized, ranked, searches every field; scope chips narrow to Tag / Serial / Location / Custodian / Dept; the Active/All/Disposed toggle widens it to retired assets.
- **Physical Inventory** groups departments by Div/Org with live progress meters (active assets only). Inside a department: card view with one-tap ✓ Verified OK, or table view; **Mark unreviewed OK** (touches only Unreviewed) vs **Complete department** (sets *everything* to Verified OK — asks for confirmation since it overwrites Not Found/Damaged marks).
- **All Assets**: 16-column sortable virtual table with status/division/department/no-location filters, select-all, and a bulk bar for status changes.
- Every field edit is written to the asset's **edit history** (old → new, who, when) and to the **AuditUpdates** list.
- **Sync chip** (top right): *N pending* = changes safely queued on-device; *Synced* = SharePoint confirmed them. Auto-pushes ~4s after a change and whenever you come back online; tap it to force a sync.
- **Editing** location or custodian suggests existing values as you type — this department's values first, then campus-wide, ranked by how often they occur.
- **Import** auto-detects the format: PeopleSoft extracts, **PMO inventory worksheets** (like the Music dept "Physical Inventory Listing" — header row found automatically, `PMO COMMENTS` mapped to statuses: OK / Photo of Tag → Verified OK, LOST/MISSING → Not Found, Not Verified → untouched, anything else → Other, with the comment kept as a note), **disposal summaries** (refreshes the retired-asset reference data locally), and this app's own exports. Always matched by Asset ID (leading zeros handled), multi-cost rows merged, quoted commas safe, and a preview separates *updates / new / conflicts* (conflict = the file wants to change a field an auditor already edited; overwriting is opt-in).
- **Export** offers four scopes — audit results, all active, disposed, everything — as CSV/XLSX with original + updated values, status, retire dates, matched survey records, notes, Updated By, Last Updated and full edit history; every field quoted.

## Troubleshooting

| Symptom | Fix |
|---|---|
| "Test connection" fails | Re-copy the full flow URL (it's long and includes `sig=`); confirm the ACAO header exists on every Response action; check the key matches. |
| Sync pushes but pull returns 100 assets | Pagination wasn't enabled on Get items (Settings → Pagination → 5000). |
| POST flow fails at Parse JSON | Content must be the expression `json(string(triggerBody()))`, not raw Body. |
| Someone can't sign in on a new phone | Their row must be in the Users list *and* the phone must sync once (open Settings → Pull latest). |
| Need a clean slate on a device | Settings → Reset this device (SharePoint untouched). |

**Upgrade path:** when CSULB IT can register an Entra ID app, the flows can be replaced with direct Microsoft Graph calls + real SSO (MSAL.js) without changing the UI.
