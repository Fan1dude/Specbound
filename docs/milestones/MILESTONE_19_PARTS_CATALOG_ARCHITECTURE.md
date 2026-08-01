# Milestone 19: Structured Parts Catalog, Import & Affiliate-Link Architecture

Status: **Approved.** 2026-07-31. Schema not yet applied — see Migration Plan below. Supersedes the first-draft version of this design (components-only, open authenticated-insert) that shipped as uncommitted `0020`/`0021` migration files earlier in this same working session; those files are being rewritten to match this document before anything is applied.

A follow-up SQL/security audit pass (2026-07-31) reviewed the four migration files against this design and made several corrections — a real race-condition fix, two collision guards, explicit privilege grants, additional constraints, and a minimal anti-spam safeguard. None of it changes the design described below; see `MILESTONE_19_SQL_SECURITY_AUDIT.md` for the full audit and exactly what changed.

This document is the single source of truth for the approved design. It exists so the schema doesn't keep re-litigating itself — see "Explicitly Out of Scope" below for the line drawn around what this milestone does and does not decide.

---

## 1. Problem

Specbound's build specifications (CPU, GPU, hardware fields generally) are a flat, unstructured `jsonb` object of plain strings — `{cpu: "Ryzen 7800X3D"}` — with no stable identifier per part. This blocks three things already on the roadmap: affiliate links per component, a real "import from PCPartPicker/BuildCore" feature, and reliable compatibility/search/analytics. A partial component catalog already existed before this milestone (`ComponentAutocomplete.js` + a `search_components()` RPC used only for PC-build CPU/GPU) but its matched id was silently discarded before save, and the RPC itself has no migration file anywhere in the repo — its live schema can't be verified from this environment (anon-key only, no DB/CLI access).

## 2. Approach, at a glance

- Every specification value becomes a structured `{componentId, name}` pair instead of a plain string. Old flat-string data is never backfilled — both shapes coexist forever behind one shared normalizer (`js/utils/specifications.js`, already shipped).
- A new `components` table is the canonical parts catalog. **Ordinary users never write to it directly.** They save free text to their own builds (always allowed, unchanged), or submit a candidate for moderator review via `component_submissions`.
- Punctuation/spacing-insensitive normalization plus an explicit `component_aliases` table prevent obvious duplicates without risking false-positive merges.
- A paste-list import flow parses pasted parts lists, but never silently discards a line — every parsed line surfaces in review as **matched**, **needs review**, or **unrecognized**, and only exact catalog matches attach automatically; fuzzy matches require explicit confirmation.
- `technology_id`/`field_key` stay free text (config-driven, no FK), but gain a declared-rename mechanism so a future config change can't silently orphan catalog rows.
- Affiliate links attach to a **retail variant** (a specific buyable SKU), not directly to a generic `components` row — because "the part" and "a specific thing you can click buy on" are different granularities.

## 3. Schema

```mermaid
erDiagram
    COMPONENTS ||--o{ COMPONENT_ALIASES : "has"
    COMPONENTS ||--o{ COMPONENT_RETAIL_VARIANTS : "has"
    COMPONENTS ||--o{ COMPONENT_SUBMISSIONS : "resolved_component_id (nullable)"
    COMPONENT_RETAIL_VARIANTS ||--o{ COMPONENT_RETAILER_LINKS : "has"
    RETAILERS ||--o{ COMPONENT_RETAILER_LINKS : "provides"
    CATALOG_MODERATORS }o--|| AUTH_USERS : "grants moderator status to"
    COMPONENT_SUBMISSIONS }o--|| AUTH_USERS : "submitted_by"
    COMPONENTS }o--|| AUTH_USERS : "created_by (moderator who approved)"

    COMPONENTS {
        uuid id PK
        text technology_id
        text field_key
        text canonical_name
        text normalized_name "generated, stored"
        text manufacturer
        jsonb metadata
        uuid created_by FK
        timestamptz created_at
        timestamptz updated_at
    }

    COMPONENT_SUBMISSIONS {
        uuid id PK
        text technology_id
        text field_key
        text submitted_name
        text normalized_name "generated, stored"
        text manufacturer
        uuid submitted_by FK
        text status "pending / approved / rejected"
        uuid resolved_component_id FK "null until resolved"
        uuid moderator_id FK
        text moderator_note
        timestamptz created_at
        timestamptz reviewed_at
    }

    COMPONENT_ALIASES {
        uuid id PK
        uuid component_id FK
        text alias
        text normalized_alias "generated, stored"
        text technology_id "denormalized via trigger"
        text field_key "denormalized via trigger"
        timestamptz created_at
    }

    CATALOG_MODERATORS {
        uuid user_id PK_FK
        uuid granted_by FK
        timestamptz granted_at
    }

    RETAILERS {
        uuid id PK
        text name
        text slug
        text homepage_url
        text logo_url
        timestamptz created_at
        timestamptz updated_at
    }

    COMPONENT_RETAIL_VARIANTS {
        uuid id PK
        uuid component_id FK
        text variant_name
        text retailer_sku
        timestamptz created_at
        timestamptz updated_at
    }

    COMPONENT_RETAILER_LINKS {
        uuid id PK
        uuid variant_id FK
        uuid retailer_id FK
        text url
        text label
        int display_order
        timestamptz created_at
    }
```

`AUTH_USERS` is Supabase's built-in `auth.users`, not a table this migration owns — shown only to make the FK edges legible.

---

## 4. Design decisions, by requirement

### 4.1 Free text stays open; canonical creation is moderated

A build's specification value can always be `{componentId: null, name: "whatever the user typed"}` — this never touches `components` and requires no special permission; it's the same jsonb write path that already exists.

What changes: `components` drops its open authenticated-insert policy entirely. The **only** way a new canonical row gets created is:

1. A user with no catalog match submits a candidate → inserted into `component_submissions` (`status = 'pending'`), which they can read/see-status-of/withdraw-while-pending, but cannot approve.
2. A `catalog_moderators`-flagged user reviews it and calls `approve_component_submission(submission_id, alias_of_component_id default null)` — a `SECURITY DEFINER` RPC that either creates a new `components` row (`alias_of_component_id` omitted) or attaches the submission as a `component_aliases` row on an existing component (`alias_of_component_id` provided), atomically updating the submission's `status`/`resolved_component_id` either way. A separate `reject_component_submission(submission_id, note)` handles the third disposition.

`catalog_moderators` is the first admin-role concept in this app. It's deliberately scoped to this one subsystem (not a general "is_admin" flag) — a `SECURITY DEFINER` helper `is_catalog_moderator(uid)` is what other tables' RLS policies reference, so the moderator list itself never needs a public SELECT policy.

### 4.2 Conservative normalization + aliases

`normalized_name` is a generated, stored column: `regexp_replace(lower(canonical_name), '[^a-z0-9]', '', 'g')` — the same alphanumeric-only normalization already established client-side in `js/utils/fuzzySearch.js`'s `normalizeCompact`, reused rather than reinvented. The catalog's uniqueness constraint moves from `lower(canonical_name)` to `(technology_id, field_key, normalized_name)`.

This is conservative by construction: it strips punctuation and whitespace only, never reorders tokens or does phonetic matching. "RTX 4080" / "RTX-4080" / "rtx4080" collapse to one row; "RTX 4080" and "RTX 4080 Ti" stay distinct because "Ti" is a real token, not punctuation.

`component_aliases` covers what normalization alone can't — abbreviations, common misspellings, shorthand ("4080" for the full name). Each alias is scoped to `(technology_id, field_key, normalized_alias)` uniquely (denormalized onto the alias row via trigger, since Postgres can't put a unique index across a join), so within one technology/field slot an alias string resolves to exactly one canonical component.

### 4.3 Import review never silently drops a line

Every parsed line from a pasted parts list produces a review row, categorized as:

- **Matched** — field identified with confidence, value exact-matched the catalog (see 4.4).
- **Needs review** — field identified, but the value only fuzzy-matched (or didn't match at all — still importable as free text).
- **Unrecognized** — the line's label didn't confidently match any technology field. Shown in its own section with a manual field-assignment control. A line is only excluded from import by explicit user action, never by the parser silently discarding it.

### 4.4 Auto-attach only on exact match; fuzzy requires confirmation

Each review row carries a `matchState`:

- `confirmed` — exact normalized/alias match → `componentId` pre-attached, shown with a solid "Catalog match" badge.
- `suggested` — fuzzy candidate(s) exist (via the existing `fuzzySearch.js` scoring) → shown as "Did you mean: {name} ({score}%)?" with an explicit accept control; `componentId` stays `null` until the user confirms.
- `unmatched` — no catalog signal at all → plain text, no suggestion UI.

### 4.5 `technology_id` / `field_key` governance

Both stay free text — the source of truth remains `js/config/technologies/*.js`, and making that DB-driven is still out of scope (too large a change for what it buys). What's new:

1. Each technology config file may declare `deprecatedFieldKeys: { oldKey: newKey }` — a rename must be declared, not silent.
2. A CI check (`tools/ci/check-catalog-field-keys.js`, matching the existing `tools/ci/check-*.js` pattern) fails the build if a declared rename is malformed. It cannot check live DB rows from this environment (no DB access), but it enforces the declaration exists and is well-formed.
3. Renaming a field key ships as an explicit, reviewable migration: `UPDATE components SET field_key = 'new' WHERE technology_id = '...' AND field_key = 'old'`. Documented as a required step alongside any config rename — unlike the specifications-jsonb backfill (deliberately never done, because it would touch unverifiable user free text), this is a fully-scriptable operation against a table this app owns entirely.
4. `resolveFieldKey(technologyId, key)` in `technologies/index.js` transparently maps an old key to its current one via `deprecatedFieldKeys`, so lookups keep working even if the DB-side migration hasn't landed yet.
5. A documented manual audit query in `docs/OPERATIONS.md` (`SELECT DISTINCT technology_id, field_key FROM components`) for periodic drift-checking — this app has no scheduled-job infrastructure to automate it.

### 4.6 Generic component families vs. exact retail variants

`components` stays at the granularity builders actually type/search — "NVIDIA GeForce RTX 4080," not a specific AIB partner card. `component_retail_variants` sits between a component and its links, representing one specific buyable SKU ("ASUS TUF Gaming RTX 4080 OC 16GB"). `component_retailer_links` attaches to a variant, not a component directly.

A build's spec value resolves to the generic component; a future buy-links UI would show every variant under it, each with its own retailer links — matching how affiliate programs actually work (one part, many purchasable SKUs) without forcing specifications to be more granular than what users type. A component with zero variants (the default — this milestone ships no real affiliate population) simply shows no buy links.

---

## 5. Explicitly out of scope this milestone

- Any real PCPartPicker/BuildCore scraping or API integration (paste-list import only — no public API exists for either, and scraping is against PCPartPicker's ToS).
- Any real affiliate provider/network integration (Amazon Associates etc.) — `retailers`, `component_retail_variants`, and `component_retailer_links` all ship with **no write policy for anyone**, intentionally inert until a future milestone defines who populates them.
- Making `technology_id`/`field_key` a DB-driven/FK-enforced vocabulary.
- Backfilling existing published builds' `specifications` to the structured shape.
- A moderator-facing review UI. The schema and RPCs support moderation; building the actual review screen is separate, follow-on work.
- Design system, color palette, typography, button/badge systems — frozen, untouched.

## 6. Risks / judgment calls surfaced

1. ~~`component_submissions` has no rate limit or spam throttle~~ — **partially addressed** by the SQL/security audit pass: a per-account pending-submission cap (20) now exists at the DB level. Multi-account abuse and slow-drip low-quality submissions are still open — tracked as a launch blocker for public beta in `docs/ROADMAP.md`'s Backlog, not silently left unscoped. See `MILESTONE_19_SQL_SECURITY_AUDIT.md` §5.
2. **No moderator-facing UI ships this milestone.** Until one exists, approving/rejecting submissions requires direct RPC calls (e.g. via the Supabase SQL editor or a script) — real friction, accepted for this pass.
3. **Alias review is a judgment call per submission** — a moderator deciding "is this really the same part, or a different one" has no tooling beyond the normalized/fuzzy match shown to them. Mismatches are possible and would need manual cleanup. The audit pass added DB-level guards that block the specific case of an approval creating an outright naming collision with existing catalog data (`MILESTONE_19_SQL_SECURITY_AUDIT.md` §1.3) — that catches a real class of mistake, but doesn't replace moderator judgment about whether two differently-worded submissions genuinely describe the same part.
4. **`catalog_moderators` grants are a manual operation** (`INSERT`/`DELETE` on the table directly) — no self-service admin UI. Acceptable for the expected initial moderator count (small, trusted).

## 7. Migration plan

Four additive migrations, each with a paired rollback file, following existing convention (`docs/DATABASE.md`). Application order is strict (each depends on objects the previous one creates); rollback order is the exact reverse — see `MILESTONE_19_SQL_SECURITY_AUDIT.md` §6 for the dependency reasoning behind the order.

- `0020_components_catalog.sql` — `catalog_moderators`, `is_catalog_moderator()`, then `components` (moderator-gated insert policy, `normalized_name`, non-empty checks). Moderator infra ships in the same file as `components` — its insert policy references `is_catalog_moderator()`, which must exist first, so this couldn't split cleanly across two files the way the first draft of this plan assumed.
- `0021_component_aliases.sql` — `component_aliases`, denormalization trigger, non-empty checks. Moved ahead of submissions (a still-earlier draft had this after) because `approve_component_submission()`'s alias-approval path has to write to it, and a migration can't forward-reference a table defined later.
- `0022_component_submissions.sql` — `component_submissions` (status-consistency constraint, non-empty checks, anti-spam pending-cap trigger), `approve_component_submission()` (row-locked, cross-table collision guards), `reject_component_submission()`.
- `0023_retailers_and_retail_variants.sql` — `retailers`, `component_retail_variants`, `component_retailer_links` (non-empty/nonnegative checks, two uniqueness constraints).

None of these touch `project_drafts`/`builds`/`build_revisions` DDL — `specifications`/`resources` stay opaque `jsonb`, absorbing the new value shape with no SQL function changes.

## 8. Verification plan

- Each migration gets a manual read-through against `docs/DATABASE.md`'s conventions (RLS enabled, explicit policies, rollback pairs) — cannot be applied or tested against a live DB from this environment (anon-key only). **Superseded by a dedicated follow-up audit** — see `MILESTONE_19_SQL_SECURITY_AUDIT.md` for the full pass (SECURITY DEFINER review, constraints, uniqueness, a written SQL test suite, anti-spam safeguard) that went well beyond this original read-through-only plan.
- Application code: live-verify in the browser where reachable without real auth credentials (category pages, Explore, public build pages); editor/import-flow changes get a static module-parse check plus manual code review, since they're auth-gated and this environment has no test account.
- Re-run the existing static checks (`tools/ci/check-syntax.js`, `check-references.js`, `check-a11y-regressions.js`) after implementation.

## 9. Related documents

- `docs/DATABASE.md` — schema conventions this migration set follows
- `docs/ARCHITECTURE.md` — where this fits in the overall system
- `js/utils/specifications.js` — the structured-value normalizer this milestone depends on (shipped prior to this document)
- `MILESTONE_19_SQL_SECURITY_AUDIT.md` — the follow-up SQL/security audit of the four migrations described here; read this alongside this document for the final, corrected state of the schema
- `supabase/tests/milestone_19_parts_catalog.test.sql` — the SQL test suite the audit added
