# Milestone 19: SQL & Security Audit — Migrations 0020–0023

Status: **Audit complete.** 2026-07-31. Migrations updated in place (all were still `Proposed`, none applied — see `docs/DATABASE.md`'s convention that a migration only gets edited in place before it's applied). **Not yet applied. Not yet committed.**

This is a focused audit of `supabase/migrations/0020_components_catalog.sql` through `0023_retailers_and_retail_variants.sql`, requested as a final gate before application. It assumes familiarity with `MILESTONE_19_PARTS_CATALOG_ARCHITECTURE.md` (the design) and documents what changed as a result of this pass, not the design itself.

---

## 1. `SECURITY DEFINER` review

Five functions touch privilege in some way: `is_catalog_moderator()`, `set_component_alias_technology_and_field()` (trigger), `enforce_component_submission_pending_cap()` (trigger), `approve_component_submission()`, `reject_component_submission()`.

| Function | `search_path` | Internal `auth.uid()` check | Execute grant | Pending-status check | Duplicate-execution safe | Tech/field consistency | Atomic |
|---|---|---|---|---|---|---|---|
| `is_catalog_moderator(uid)` | ✅ `set search_path = public` | N/A — takes `uid` as a parameter by design, doesn't assume caller identity | **Fixed** — was ambient PUBLIC default, now `revoke ... from public; grant ... to authenticated` | N/A | N/A | N/A | N/A (single `SELECT EXISTS`) |
| `set_component_alias_technology_and_field()` | ✅ | N/A — copies from the referenced `components` row, not identity-dependent | **Fixed** — defensive revoke from PUBLIC (trigger firing doesn't require it, added for hygiene) | N/A | N/A | ✅ by construction (copies both fields together, same row, same statement) | ✅ single `SELECT ... INTO` |
| `enforce_component_submission_pending_cap()` | ✅ | N/A — reads `new.submitted_by`'s own rows, which they already have SELECT access to (see below) | **Fixed** — defensive revoke from PUBLIC | N/A | See §1.1 | N/A | ✅ single `SELECT COUNT(*)` |
| `approve_component_submission(id, alias_id)` | ✅ | ✅ `is_catalog_moderator(auth.uid())` | **Fixed** | ✅ `where status = 'pending'` + `if not found then raise` | **Fixed** — see §1.2 | ✅ alias-target checked against submission's own `technology_id`/`field_key`; new-component path trivially consistent (copied from the same submission row) | ✅ single statement/transaction — an exception anywhere rolls back everything the call did |
| `reject_component_submission(id, note)` | ✅ | ✅ `is_catalog_moderator(auth.uid())` | **Fixed** | ✅ `where status = 'pending'` + `if not found then raise` | ✅ already safe — see §1.2 | N/A (no catalog write) | ✅ single `UPDATE` |

### 1.1 `enforce_component_submission_pending_cap()` — deliberately not `SECURITY DEFINER`

Worth calling out explicitly since it's the one function in this file *without* `security definer`, unlike the other two. The count inside it only ever reads `new.submitted_by`'s own rows — the inserting user already has legitimate `SELECT` access to exactly those rows via the "Users can view their own submissions" policy. Running it as the caller (the default, `SECURITY INVOKER`) is sufficient and doesn't grant the function more reach than it needs. Marking it `SECURITY DEFINER` would have been over-privileging for no behavioral gain.

### 1.2 Duplicate-execution / race-condition finding (real bug, fixed)

**Finding:** `approve_component_submission()`'s original body used `SELECT ... INTO v_submission FROM component_submissions WHERE ... AND status = 'pending'` with no row lock, followed — several statements later, after an `INSERT` into `components` or `component_aliases` — by an `UPDATE` setting `status = 'approved'`. Under Postgres's default READ COMMITTED isolation, two concurrent calls (two moderators, or one double-click racing a slow network) could both pass the initial `SELECT` before either committed, both proceed to insert a catalog row, and both `UPDATE` the same submission — the second `UPDATE` silently overwriting the first's `resolved_component_id`/`moderator_id`, leaving the *first* call's inserted row orphaned (a real `components` or `component_aliases` row that nothing references, with no error raised anywhere to surface the problem).

**Fix:** added `FOR UPDATE` to the initial `SELECT`. This locks the row for the rest of the transaction; a concurrent second call blocks at that `SELECT` until the first transaction commits, then re-evaluates `WHERE status = 'pending'` against the now-committed row, finds it no longer pending, and correctly falls into the existing `if not found then raise exception` branch.

**`reject_component_submission()` was already safe** — it uses a single `UPDATE ... WHERE status = 'pending'` with no separate read step. Postgres's row-level locking for `UPDATE` already serializes concurrent attempts on the same row: the second call's `UPDATE` blocks until the first commits, then re-evaluates its own `WHERE` clause against the committed row and correctly affects zero rows. No change needed there — flagged as reviewed, not silently assumed safe.

**Not independently verified under real concurrency.** This environment has no database access, so the fix is a code-review-verified correction of a real logic gap, not something a serial test script (§4) can empirically exercise — genuinely testing the race requires two concurrent sessions (e.g. two `psql` connections issuing the same call simultaneously), which is out of reach here. Recommend an empirical concurrency test before this ships to a multi-moderator environment, even though the fix itself is standard, well-understood Postgres practice (`SELECT ... FOR UPDATE` is the canonical pattern for exactly this check-then-act shape).

### 1.3 Symmetric alias/canonical collision guards (found during this pass, both fixed)

Neither table's own unique index can catch a name colliding *across* `components` and `component_aliases` — `components_technology_field_normalized_idx` only guards `components.normalized_name` against itself; `component_aliases_technology_field_normalized_idx` only guards `component_aliases.normalized_alias` against itself. Two gaps, symmetric:

1. Approving a submission **as an alias** of component B, when a *different* existing component A already canonically owns that exact normalized name — added an explicit `PERFORM ... IF FOUND THEN RAISE` check before the `INSERT INTO component_aliases`.
2. Approving a submission **as a new component**, when that exact normalized name already exists as an *alias* of some other existing component — added the mirror-image check before the `INSERT INTO components`.

Both raise a clear exception naming the conflict rather than silently creating ambiguous catalog data. Both are covered by SQL tests (§4, tests 2b/2c).

---

## 2. Constraints added

| Table | Constraint | Why |
|---|---|---|
| `components` | non-empty `technology_id`, `field_key`, `canonical_name` | A not-null but all-whitespace value would pass the existing `not null` and normalize to an empty string — silently colliding with any other empty entry in the same slot. |
| `component_aliases` | non-empty `alias`, `technology_id`, `field_key` | Same reasoning; `technology_id`/`field_key` are trigger-populated but constrained independently rather than trusting the trigger alone. |
| `component_submissions` | non-empty `technology_id`, `field_key`, `submitted_name` | Same reasoning. |
| `component_submissions` | `component_submissions_status_consistency` — a three-way `CHECK` tying `status` to whether `resolved_component_id`/`moderator_id`/`reviewed_at` are set | Makes it structurally impossible for either RPC to leave a row in a state its own logic wouldn't produce — e.g. `'approved'` with no `resolved_component_id`, meaning the catalog write silently didn't happen despite the status saying it did. See §4 tests 4a/6a, which assert this directly. |
| `retailers` | non-empty `name`, `slug`, `homepage_url` | Same reasoning; `slug` was already `unique` but not guarded against being an empty string. |
| `component_retail_variants` | non-empty `variant_name` | Same reasoning. |
| `component_retailer_links` | non-empty `url`; `display_order >= 0` | Same reasoning, plus a negative sort order is meaningless for this column's purpose. |

Nullable/optional columns (`manufacturer`, `logo_url`, `label`, `moderator_note`) were deliberately left unconstrained — over-constraining optional fields adds friction without a real data-integrity benefit.

---

## 3. Uniqueness constraints — verified and documented

| Table | Constraint | Scope | Notes |
|---|---|---|---|
| `components` | `components_technology_field_normalized_idx` (unique) | `(technology_id, field_key, normalized_name)` | Punctuation/spacing-insensitive — the core dedup mechanism. Pre-existing, reviewed. |
| `component_aliases` | `component_aliases_technology_field_normalized_idx` (unique) | `(technology_id, field_key, normalized_alias)` | Prevents the same alias text resolving to two different components in one slot. Pre-existing, reviewed. |
| `components` ↔ `component_aliases` | **No DB-level unique index possible** (unique indexes can't span two tables) | — | Covered instead by the two `RAISE`-based guards in `approve_component_submission()`, §1.3 — the only path that ever writes to `component_aliases`. This is the correct place to enforce it: a `CHECK` constraint can't reference another table, so app-level (function) logic is the only mechanism available. |
| `component_submissions` | *(none, intentionally)* | — | Documented in the file's own comment: near-duplicate submissions from different users are expected before a moderator resolves any of them — the moderator's judgment (backed by the two tables' real constraints, enforced at approval time) is what dedupes, not an insert-time constraint. |
| `retailers` | `slug` (unique, pre-existing) | `slug` | Reviewed — sufficient as the retailer's stable key; `name` deliberately left unconstrained (a display name could legitimately change). |
| `component_retail_variants` | **Added this pass**: `component_retail_variants_component_variant_name_key` (unique) | `(component_id, variant_name)` | Was entirely missing before this audit. Case-sensitive literal match (not punctuation-normalized like `components`/`component_aliases`) — this table is meant to be populated by a curated process, not free-text end users, so the simpler bar is sufficient. |
| `component_retailer_links` | **Added this pass**: `component_retailer_links_variant_url_key` (unique) | `(variant_id, url)` | Was entirely missing before this audit. Deliberately *not* `(variant_id, retailer_id)` — a variant can legitimately have more than one URL at the same retailer (regional storefronts, bundle listings); this only blocks the exact same URL being attached twice. |

---

## 4. SQL test suite

`supabase/tests/milestone_19_parts_catalog.test.sql` — new file, new convention for this repo (no prior SQL test harness existed; mirrors the `tests/*.test.html` naming pattern already used for browser tests).

**Status: written, not executed.** This implementation environment has no database access (anon-key only, consistent with every other constraint noted throughout this milestone) — there is nowhere to run it. It must be run once against a disposable/staging Supabase project (never production) before being trusted, via the SQL editor or `psql`, after migrations 0020–0023 are applied there.

Structure: the whole file runs inside one transaction that ends in `ROLLBACK`; each of the 8 individual tests additionally runs inside its own `SAVEPOINT` and always rolls back to it regardless of outcome, so no test's result — expected or not — can contaminate another's starting state, and the suite always runs to completion printing a full pass/fail report (`RAISE NOTICE` for pass, `RAISE WARNING` for fail — never `RAISE EXCEPTION` for a test outcome, since that would abort the whole script at the first failure). Identity simulation uses Supabase's standard pattern for testing RLS from raw SQL (`set_config('request.jwt.claim.sub', ...)` + `set local role authenticated`).

| Test | Scenario | Asserts |
|---|---|---|
| 1 | Duplicate normalization | Inserting `"RTX-4080"` directly into `components` when `"RTX 4080"` already exists in the same slot raises `unique_violation`. |
| 2a | Alias conflict (same table) | The same alias text attached to two different components in one slot raises `unique_violation` on `component_aliases`' own index. |
| 2b | Alias conflict (cross-table, §1.3 guard #1) | Approving a submission as an alias of component B fails when component A already canonically owns that exact normalized name. |
| 2c | Alias conflict (cross-table, §1.3 guard #2) | Approving a submission as a *new* component fails when that normalized name already exists as an alias of a different component. |
| 3 | Unauthorized approval | A non-moderator, non-submitter calling `approve_component_submission()` gets `'Only a catalog moderator may approve...'`. |
| 4a/4b | Repeated approval | First approval leaves a fully consistent `'approved'` row (§2's status-consistency constraint, asserted directly); a second call on the same id gets `'not found or already resolved'`. |
| 5a/5b/5c | Withdrawal rules | Submitter can delete their own pending submission (1 row); a different user cannot (0 rows); the original submitter cannot once it's resolved (0 rows). |
| 6a/6b | Rejection | Rejecting leaves a fully consistent `'rejected'` row with `resolved_component_id IS NULL` (status-consistency constraint again, from the other branch); a second rejection call gets `'not found or already resolved'`. |

**What this suite does not cover:** real concurrent execution (§1.2's race-condition fix — needs two live sessions, not a serial script), and `auth.users`' exact required columns, which vary by Supabase/GoTrue project version (the minimal `(id, email)` insert in the fixtures is the commonly-documented pattern but may need adjusting).

---

## 5. Anti-spam safeguard

**Implemented:** `enforce_component_submission_pending_cap()`, a `BEFORE INSERT` trigger on `component_submissions`, caps a single account at 20 open (`'pending'`) submissions. Minimal by design — it stops one account from flooding the moderation queue with bulk junk, using no new infrastructure (no cron, no external service, no rate-limiter).

**What it does not cover**, tracked as a real gap rather than an oversight:
- Multi-account abuse (spreading submissions across several accounts to stay under each one's cap).
- Slow-drip low-quality submissions that never individually breach the cap.
- Any HTTP-layer rate limit or CAPTCHA — this is a DB-level safeguard only.

**Tracked as a launch blocker for public beta** — added to `docs/ROADMAP.md`'s Backlog table: *"Component-submission anti-spam beyond the per-account cap... revisit before opening catalog submissions to the general public, not just signed-in testers."* Not blocking the current (invite/testing-scope) work, but explicitly flagged rather than silently left unscoped.

---

## 6. Static checks and application order

**Static checks run:**
- Balanced `begin;`/`commit;` pairs (exactly 1 each) — re-verified on all four migrations after every edit in this pass.
- Balanced `$$` dollar-quote delimiters — re-verified (0020: 2 functions → 2 pairs; 0022: 4 functions → 4 pairs after this pass's additions; 0021/0023: unchanged from prior verification).
- Cross-reference check: grepped all four files for stale references to the earlier (pre-reorder) file numbering — found and fixed two in `0020`'s own header/inline comments that still said `0021_component_submissions.sql` (correct name is `0022_...`, left over from the dependency-ordering fix made before this audit).
- `tools/ci/check-syntax.js` / `check-references.js` / `check-a11y-regressions.js`: **not run** — this pass touched only `.sql` and `.md` files, none of which those Node-based checks scan (`.js`/`.html`/`.css` only), and this environment has no Node runtime available regardless (established earlier this session). Not applicable to this specific change set.
- No non-SQL/non-doc files were touched in this pass — confirmed via `git status` scoped to this work.

**Migration application order:** `0020` → `0021` → `0022` → `0023` (must be strict — each depends on objects the previous one creates; see each file's own header for the specific dependency).

**Rollback order (strict reverse):** `0023` → `0022` → `0021` → `0020`.
- `0023` first: `component_retail_variants`/`component_retailer_links` depend on `components` (0020) but nothing depends on them — safe to drop anytime, cleanest to go first.
- `0022` next: `component_submissions` depends on `components`, `catalog_moderators`, `is_catalog_moderator()` (0020) and `component_aliases` (0021) — must go before either of those.
- `0021` next: `component_aliases` depends on `components` (0020) — must go before it.
- `0020` last: `components`, `catalog_moderators`, `is_catalog_moderator()` — the foundation everything else depends on.

Each rollback file's own header comment states this same ordering constraint independently, so the dependency is documented at the point of use, not only here.

---

## 7. Summary — what changed, at a glance

- **Bug fixed:** race condition in `approve_component_submission()` (§1.2) — the one finding in this audit with real correctness impact if it had shipped as-was.
- **Gap closed:** direct-insert moderation bypass was already closed in the prior pass; this pass closed the *alias/canonical cross-table collision* gap, in both directions (§1.3).
- **Hardened:** explicit execute grants (was ambient PUBLIC default) on all 5 privilege-relevant functions; 12 new non-empty/nonnegative checks; 1 new multi-column consistency constraint; 2 new uniqueness constraints that were missing entirely.
- **New:** minimal anti-spam trigger, tracked follow-up backlog item, SQL test suite (8 tests across 6 named scenarios, unexecuted pending real DB access).
- **Still not applied, not committed.** Ready for review.
