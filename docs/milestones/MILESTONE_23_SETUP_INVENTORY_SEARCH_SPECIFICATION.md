# Milestone 23 — Setup Inventory, Search & Builder History

Status: Draft specification, written before implementation, per this
milestone's own process requirement. Updated in place as implementation
decisions are finalized; not a historical record of the design process.

## 1. Scope

Five features, all additive to the existing schema and application code:

1. Setup inventory — a flexible, category-grouped product list for the
   `setup` technology (Desk Setups), separate from the existing
   `specifications` jsonb field every technology already has.
2. Link-assisted product entry — paste a URL, optionally fetch
   best-effort metadata via a new Edge Function, always editable, always
   manual-entry-capable.
3. Editable pricing and automatic totals — integer-cents money, live
   category/setup totals, "Setup total" vs "Known total" labeling.
4. Scoped search — `all` / `build` / `creator` / `category` scopes on
   the existing search page and navbar search.
5. Builder join/history dates — `profiles.created_at` (already exists,
   read-only) properly labeled as "Joined", plus a new optional,
   creator-editable `building_since_year`.

## 2. Technology identifier

Confirmed by reading `js/config/technologies/setup.js` directly rather
than assuming: the Setup technology's `id` is `"setup"` (its `slug` is
`"desk-setups"` — the id, not the slug, is what's stored in
`builds.category` / `project_drafts.category` / `build_revisions.category`,
confirmed via `js/config/technologies/index.js`'s
`technology => technology.id === id` lookup). Every category check in
this milestone (editor section visibility, public-page rendering) tests
`draft.category === "setup"` / `build.category === "setup"`.

## 3. Data model

### 3.1 `setup_inventory` jsonb (new column, 3 tables)

Added to `project_drafts`, `builds`, `build_revisions` — mirrors exactly
how `specifications` and `resources` already work on those three tables
(one jsonb column per table, `not null default` to an empty-but-valid
shape, copied verbatim through `publish_draft()` and
`restore_revision_to_draft()`).

Final normalized shape (schemaVersion 1):

```js
{
  schemaVersion: 1,
  currency: "USD",              // ISO 4217, one currency per inventory
  categories: [
    {
      id: "uuid",                // stable, generated client-side once, never regenerated on re-render
      name: "Displays",          // this blueprint's own snapshot of the name — see §3.3
      templateId: "uuid|null",   // saved_setup_categories.id this category originated from, or null
      sortOrder: 0,
      items: [
        {
          id: "uuid",
          title: "27-inch OLED Monitor",
          originalUrl: "https://example.com/product|null",
          retailerName: "Best Buy|null",         // suggested, from metadata
          listedPriceCents: 69999,               // integer minor units, or null
          listedPriceCurrency: "USD|null",
          metadataFetchedAt: "2026-08-11T12:00:00.000Z|null",
          pricePaid: {
            cents: 64999,        // integer minor units, or null if unknown
            isFree: false        // explicit free flag — see §3.4
          },
          sourceType: "retailer", // "retailer" | "thrift_store" | "marketplace" | "gifted" | "other"
          sourceName: "Best Buy|null", // free text, independent of sourceType
          sortOrder: 0
        }
      ]
    }
  ]
}
```

Deliberate departures from the illustrative shape in the milestone
request, decided during implementation and documented here rather than
silently changed:

- `pricePaidCents`/`isFree` are nested under one `pricePaid: { cents,
  isFree }` object instead of two sibling keys. Keeping "the creator's
  final price" as a single cohesive value (an amount that may be
  unknown, and a separate boolean for "this was free") reduces the
  invalid-state space — the original flat shape allows
  `pricePaidCents: 500, isFree: true` (contradictory) with nothing in
  the shape itself preventing it. The normalizer (§4) still accepts and
  corrects the flat shape on read, for compatibility with the
  illustrative contract, but always writes the nested shape.
- `listedPriceCents`/`listedPriceCurrency` stay flat (not nested) —
  they're an inert, non-authoritative suggestion snapshot, never
  user-edited after the fact, so there's no equivalent "conflicting
  state" risk to guard against.

### 3.2 `saved_setup_categories` (new table)

Owner-scoped, reusable category name templates — never referenced
directly by any blueprint at render time (see §3.3).

```sql
create table public.saved_setup_categories (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    name text not null,
    normalized_name text not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint saved_setup_categories_name_length check (char_length(name) between 1 and 60),
    constraint saved_setup_categories_owner_name_unique unique (user_id, normalized_name)
);
```

`normalized_name` = `lower(trim(name))`, maintained by a trigger (not
computed at read time) so the uniqueness constraint is enforced by
Postgres itself, not just application code — prevents "Displays" and
" displays " from coexisting for the same builder.

RLS: `select`/`insert`/`update`/`delete` all scoped to
`auth.uid() = user_id`. No public read policy at all (explicit
requirement) — a saved category is only ever visible to its owner,
including when other builders view a published blueprint that
originated from one (they only ever see the blueprint's own name
snapshot, never a join back to this table).

### 3.3 Snapshot-not-reference

Every category in `setup_inventory.categories[]` carries its **own**
`name` string, copied at the moment the builder adds/selects it — never
a live join to `saved_setup_categories`. `templateId` is stored *only*
for the editor's own convenience (e.g. to visually indicate "this came
from a saved category" while editing), and is explicitly excluded from
public rendering (§7). Renaming or deleting a `saved_setup_categories`
row therefore cannot alter any draft, build, or revision that already
copied its name — satisfying the requirement that existing content
never changes when a template does, with zero extra bookkeeping (no
"snapshot on publish" step needed, because the snapshot already happened
at add-time, in the draft itself).

### 3.4 Money

- All prices are integer minor units (`*Cents`, cents for USD — the
  only currency this milestone ships selectable, see §6).
- Missing price is `null`, never `0`.
- `pricePaid.isFree: true` is a distinct, explicit state — a free item
  contributes `0` to totals, but is never confused with "price unknown"
  (`pricePaid.cents === null && !isFree`).
- `originalUrl` is stored verbatim, unmodified, forever — no affiliate
  parameters are added or stored anywhere in this milestone (explicit
  future-milestone boundary).

### 3.5 `profiles.building_since_year` (new column)

```sql
alter table public.profiles
    add column building_since_year integer;

alter table public.profiles
    add constraint profiles_building_since_year_range_check
    check (
        building_since_year is null
        or (building_since_year between 1980 and extract(year from now())::integer)
    );
```

Nullable, no backfill (existing users get `null`, matching this
session's established precedent for optional profile additions — see
migration `0025`'s deliberate contrast with `0034`'s deliberate
no-backfill). Lower bound `1980` is a sanity floor (personal-computing
era), not a business rule; upper bound is enforced relative to the
current year at write time via the CHECK expression, so "must not be in
the future" holds without needing a trigger.

## 4. `publish_draft()` / `restore_revision_to_draft()`

Both functions are **replaced in place** (`create or replace function`,
same signature) by migration `0035`, based on their *current* bodies —
read directly from the migrations that actually last redefined them,
not from `0005`:

- `publish_draft()`'s current body lives in `0006_unpublish.sql` (not
  `0002` or `0004` — both were superseded).
- `restore_revision_to_draft()`'s current body lives in
  `0005_revision_history_and_restore.sql` (never redefined since).

Changes, additive only:
- `publish_draft()`: the `insert into public.builds` (first publish) and
  `update public.builds` (republish) statements both gain
  `setup_inventory = v_draft.setup_inventory`; the `insert into
  public.build_revisions` statement gains `setup_inventory` in both its
  column list and its `values` list, sourced from `v_draft.setup_inventory`.
- `restore_revision_to_draft()`: both the "no existing draft, insert a
  new one" and "existing draft, update it" branches gain
  `setup_inventory = v_revision.setup_inventory`.

`create or replace function` preserves the function's existing OID and
therefore its existing grants (confirmed: Postgres does not reset
privileges on `CREATE OR REPLACE FUNCTION`) — no new `revoke`/`grant`
statements are needed for these two, only for `saved_setup_categories`'
RLS (a table, not a function — no function-privilege surface at all)
and any genuinely new function this milestone introduces (none — see
§8).

Legacy compatibility: `build_revisions.setup_inventory` defaults to
`'{"schemaVersion":1,"currency":"USD","categories":[]}'::jsonb` (a
valid, empty inventory — not `'{}'::jsonb`, so the normalizer never has
to special-case "old row, no inventory at all" vs "new row, genuinely
empty inventory"). Every pre-milestone revision gets this default
automatically via the `add column ... default ...` clause; nothing is
backfilled with fabricated content.

## 5. Metadata Edge Function (`supabase/functions/product-metadata`)

### 5.1 Request/response contract

`POST` with `{ url: string }`, `Authorization: Bearer <user JWT>`
(required — verified via `supabase.auth.getUser()` inside the function
using the request's own JWT, not the anon key alone). Response on
success:

```json
{
  "title": "27-inch OLED Monitor",
  "retailerName": "bestbuy.com",
  "priceCents": 69999,
  "currency": "USD"
}
```

Any field the function couldn't determine is simply omitted (not
`null` — the client already treats "key absent" and "key null"
identically when merging into unedited fields). On failure, a single
generic message is returned client-side
("We couldn't fill in the details from this link. You can enter them
manually.") — the function's own error responses are deliberately
generic (`{ "error": "unsupported" | "blocked" | "timeout" | "invalid" }`),
never raw upstream error text, headers, or HTML.

### 5.2 SSRF protections (defense in depth, checked in this order)

1. **Scheme** — only `http:`/`https:` accepted; everything else
   (`file:`, `javascript:`, `data:`, etc.) rejected before any network
   call.
2. **Credentials in URL** — `url.username`/`url.password` non-empty
   rejected outright (`https://user:pass@host/...`).
3. **Port** — only the scheme's default port (80/443) or no explicit
   port accepted; any other explicit port rejected.
4. **Hostname resolution + destination check** — the hostname is
   resolved via Deno's DNS lookup and every resolved address is checked
   against: loopback (`127.0.0.0/8`, `::1`), link-local
   (`169.254.0.0/16`, `fe80::/10`), private ranges (`10.0.0.0/8`,
   `172.16.0.0/12`, `192.168.0.0/16`, `fc00::/7`), the cloud-metadata
   address (`169.254.169.254`, also covered by link-local above, listed
   separately as the specific known-dangerous case it is), and
   `0.0.0.0`/unspecified. `localhost` itself is rejected by name before
   resolution even runs. Rejects if **any** resolved address matches —
   never trusts "the first address looked fine." **Known residual gap,
   disclosed not fixed**: this check and the actual `fetch()` call are
   two separate DNS lookups (Deno's `fetch` does not expose a way to
   pin a connection to an already-resolved address while still
   validating the TLS certificate against the original hostname) — a
   malicious authoritative DNS server could in principle answer safely
   on the first lookup and rebind to a private address on the second.
   Closing this fully requires a hand-rolled TCP+TLS HTTP client (manual
   `Deno.connectTls` with SNI/cert-hostname pinned to the original
   domain, IP pinned to the validated address) — a substantial rewrite
   judged out of proportion to a best-effort, beta-scale feature; see
   §9 for the same disclosure in the security summary.
5. **Redirect handling** — redirects are followed manually (not via
   `fetch`'s automatic redirect following), and step 4's full
   hostname/address check re-runs against **every** redirect
   destination, not just the original URL. Capped at 3 redirects total;
   exceeding the cap is treated as a rejection, not "return whatever we
   got."
6. **Timeout** — a single `AbortController` timeout (5s total) covers
   the entire fetch chain, not just the first request.
7. **Response size** — the response body is streamed and aborted the
   moment it exceeds a 2 MB cap, before full buffering.
8. **Content-Type** — only `text/html`/`application/xhtml+xml`
   (optionally with a charset parameter) accepted; anything else
   (including a redirect to a non-HTML resource) is rejected.
9. **No script execution** — the response is parsed as inert text via
   `DOMParser`/regex-based extraction only; no JS from the page ever
   runs (there is no headless browser, no `eval`, no dynamic `import()`
   of remote content anywhere in this function).
10. **Retailer allowlist** — the resolved hostname's registrable domain
    must match a small, explicit, hardcoded allowlist shipped in the
    function's own source (see §5.4 for why this isn't backed by the
    `retailers` table yet). A domain not on the allowlist is rejected
    with the same generic "unsupported" response the client already
    treats as "fall back to manual entry" — this is not an error state,
    it's expected, routine behavior for the majority of real-world
    URLs.
11. **Logging** — only the hostname and outcome are logged (e.g.
    `"bestbuy.com: ok"` / `"unknown-host.example: rejected(private-ip)"`);
    the full URL (which may carry tracking/session query parameters) is
    never logged.
12. **Rate limiting** — a simple fixed-window counter keyed by
    `auth.uid()` (in-memory per Edge Function instance, acceptable for
    beta scale; documented as a known scale limitation, not a
    production-hardened distributed limiter).

### 5.3 Parse priority

1. `<script type="application/ld+json">` containing a `Product` (or
   `@type` array including `Product`) — reads `name`, `offers.price`
   (or first entry of `offers` if an array), `offers.priceCurrency`.
   Rejected (falls through to the next tier) if the JSON doesn't parse,
   or lacks a usable `name`/`price`.
2. Open Graph — `og:title`, plus best-effort price meta tags
   (`product:price:amount` / `product:price:currency`, or their
   `og:price:*` equivalents some retailers use).
3. `<title>` — used only for `title`, HTML-escaped, whitespace-collapsed,
   truncated to a sane length; never a source for price.

All extracted text is escaped/sanitized before being placed in the JSON
response (defense in depth beyond the client also escaping on render —
see §9's XSS section).

### 5.4 Why a hardcoded allowlist, not `retailers.domain`

Inspected `public.retailers` (migration `0023`): it has `name`, `slug`,
`homepage_url`, `logo_url` — no `domain` column suited to an exact-match
allowlist lookup (`homepage_url` is a full URL, not a bare registrable
domain, and parsing it per-request adds a DB round-trip to every
metadata call for no real benefit at this scale). Decision: ship a
small constant array of known retailer domains directly in the Edge
Function for this milestone; a later milestone can add a `domain`
column to `retailers` and have the function read it once at cold start,
once the affiliate-link work (explicitly out of scope here) gives that
table a second real consumer. Documented as a deliberate simplification,
not an oversight.

## 6. Currency

One inventory = one ISO currency, defaulting `"USD"`. `currency` lives
once at the inventory root, not per-item. If fetched metadata's
`currency` differs from the inventory's own `currency`, the suggested
price is discarded (not converted, not silently accepted) and only
`title`/`retailerName` populate — the client never performs currency
conversion anywhere.

## 7. Public rendering

Never exposed publicly: `templateId`, any fetch-failure detail,
`metadataFetchedAt` (internal-only timestamp — the public page shows
creator-entered price paid and source, never "when this suggestion was
fetched"), any `saved_setup_categories` row, and no internally-added
tracking parameters exist to leak (none are added — see §3.4).

Legacy compatibility: a Setup blueprint with only `specifications` (no
inventory yet, or `categories: []`) renders exactly as before — the new
inventory section simply doesn't render (checked via
`categories.length > 0`, not `setup_inventory` presence, since every
row now always has a valid-but-possibly-empty inventory object per §4).
A blueprint with both `specifications` and a non-empty inventory renders
both sections, unlabeled as "old"/"new" — just two distinct, honestly
separate sections in their existing visual language.

## 8. Function/RLS/grants

New `security definer` functions introduced by this milestone: **none**.
`publish_draft()`/`restore_revision_to_draft()` are replaced in place
(§4, grants preserved automatically). `saved_setup_categories` CRUD and
`profiles.building_since_year` reads/writes are both plain
`supabase-js` `.from(...).select()/.insert()/.update()/.delete()` calls
governed entirely by RLS — the same "no RPC needed, RLS is the boundary"
pattern already established for `markOnboardingWelcomed()`/
`acceptGuidelines()`/`saved_setup_categories` itself. Migration `0033`'s
default-privilege hardening therefore has nothing new to close here:
no new function means no new function-grant surface. `saved_setup_categories`
gets ordinary owner-scoped table RLS (§3.2) plus standard
`grant select, insert, update, delete on saved_setup_categories to
authenticated` (RLS is still the real gate; the grant only permits the
role to attempt the statement at all, same layering already established
for every other owner-scoped table in this schema).

## 9. Security summary (expanded on in the final report)

- **SSRF**: §5.2, twelve independent checks, defense in depth. One
  disclosed residual gap: a DNS-rebinding attacker could in principle
  pass the destination check and then have `fetch()`'s own, separate
  DNS lookup resolve to a private address — closing this fully needs a
  hand-rolled TCP+TLS client, judged out of proportion here; every
  other check (scheme/credentials/port/redirect-revalidation/timeout/
  size/content-type/allowlist) still applies regardless.
- **XSS**: every metadata field is escaped both server-side (defensive)
  and client-side (`escapeHtml`/`escapeAttribute`, the existing
  established pattern) before ever reaching the DOM; public rendering
  uses the same escaping helpers already used for every other
  user-supplied string in this app (build titles, specifications, etc.).
- **RLS**: `saved_setup_categories` owner-scoped on all four operations,
  no public read; `setup_inventory` columns inherit the existing RLS on
  their parent tables (owner-write via `project_drafts`'
  pre-existing policy, public-read via `builds`'/`build_revisions`'
  pre-existing `visibility = 'public'` policies) — no new RLS policy
  objects needed on those three tables, since RLS is row-scoped, not
  column-scoped, and a jsonb column carries no privilege surface of its
  own.
- **Money**: integer cents throughout, no floating-point arithmetic
  anywhere in the totals pipeline (JS `Number` addition of integers is
  exact within `Number.MAX_SAFE_INTEGER`, unlike decimal arithmetic).
- **Private-profile leakage**: search's `creator` scope and the Edge
  Function's response are both built from explicit field allowlists,
  never `select("*")`.

## 10. Compatibility/failure matrix

| Failure | Behavior |
|---|---|
| Edge Function unavailable/down | Manual entry (title/price/source) still fully functional — the fetch button's failure path is identical to "not on the allowlist." |
| Pre-milestone blueprint, no inventory | Renders as before; editor shows an empty inventory ready to fill in. |
| Pre-milestone revision restored | `build_revisions.setup_inventory` defaults to an empty-but-valid shape (§4); restore copies it in as-is. |
| Saved-category load fails | Editor still allows blueprint-local (`Use in this blueprint only`) categories; the "Save to My Categories" option is disabled with an inline reason, not a silent no-op. |
| Metadata extraction fails mid-flow | The pasted URL and any manually-typed fields are left exactly as the builder entered them — only the fetch's own suggested fields are affected. |
| Autosave failure | Existing recovery-buffer pipeline (`draftRecovery.js`) already covers this generically — `setup_inventory` is just one more key in the same buffered-fields object, no separate recovery path needed. |
| Partial category/template failure | Never partially writes `setup_inventory` — every editor mutation replaces the *entire* validated/normalized object in one autosave field, so a failure leaves the last-known-good in-memory state untouched (mirrors how `specifications` already behaves). |

## 11. Deployment order (documented, not executed by this milestone)

1. Apply database migration `0035` (and its rollback file exists,
   reviewed, not run).
2. Verify migration applied cleanly and RLS behaves as tested locally
   (read-only production checks only, per this repo's established
   process).
3. Deploy the `product-metadata` Edge Function.
4. Verify authenticated invocation works end-to-end against one
   allowlisted retailer and one non-allowlisted domain (expect the
   generic fallback for the latter).
5. Deploy the website (Cloudflare Pages).
6. Run production smoke tests: create a Setup draft, add a category and
   a manual-entry product, attempt a metadata fetch, verify totals,
   publish, verify the public page, search each of the four scopes,
   set/clear `building_since_year` in Settings and confirm it appears/
   disappears on the public portfolio.

Metadata extraction is explicitly **best effort** — retailer pages are
dynamic, region-locked, bot-protected, or simply absent of structured
data often enough that this must never be treated as a dependency for
adding or publishing a product. Manual entry is always the fallback,
never a degraded second-class path.
