# Milestone 19: Development-Environment Application & Verification Procedure

Status: **Ready to execute.** 2026-07-31. Written for a human operator with real Supabase dashboard/SQL-editor access — this implementation environment has none (anon-key only, confirmed throughout this milestone), so nothing in this document has been run. It's the exact sequence to follow, not a report of having followed it.

Covers: applying migrations `0020`–`0023`, running `supabase/tests/milestone_19_parts_catalog.test.sql`, verifying rollback, and a browser smoke test with one ordinary user and one catalog moderator. See `MILESTONE_19_PARTS_CATALOG_ARCHITECTURE.md` for the design and `MILESTONE_19_SQL_SECURITY_AUDIT.md` for why the migrations look the way they do.

---

## 0. Prerequisites

- **A Supabase project with migrations `0001`–`0019` already applied.** This app's own convention (`supabase/migrations.md`) is manual application via the Supabase SQL editor — there's no CLI/CI pipeline. Confirm by checking that `public.components` does **not** yet exist (`select to_regclass('public.components');` should return `NULL`) and that, say, `public.builds` does.
- **Dashboard/SQL-editor access to that project** (the project owner or someone with SQL editor access), not just the anon key `js/core/config.js` ships with. Running the migrations, running the test file, and granting moderator status all require this.
- **Know which project you're pointing at.** `js/core/config.js` currently points to `xpxjqyraizntbtijzoyp.supabase.co`. Live-verified in this session, that project already has real user-generated content (real accounts, real builds). The migrations themselves are purely additive (new tables only — nothing here alters or drops an existing table), and the test file is written to roll back everything it does, but neither of those is the same as "verified safe in practice" in this environment. **If a disposable/staging Supabase project is available, prefer it for the test-file run and the rollback drill (§3, §5); use the real project only for the final forward-apply once those have passed elsewhere.** If a separate project isn't practical, the procedure below is still safe to run against the shared one — just be deliberate about the two test accounts in §6 (clearly-labeled, disposable, easy to tell apart from real users in Explore/search afterward).
- **A way to run raw SQL and see `NOTICE`/`WARNING` output** — the Supabase SQL editor shows these inline; `psql` shows them on stderr by default. Either works for every step below.
- **Two throwaway accounts you're prepared to create** through the app's normal signup flow for §6 — this procedure doesn't touch `auth.users` directly for the browser portion (only the SQL test file does, and only inside a rolled-back transaction).

---

## 1. Migration commands — exact order

Migrations are **not interchangeable in order** — each depends on objects the previous one creates (see each file's own header comment, and `MILESTONE_19_SQL_SECURITY_AUDIT.md` §6 for the dependency reasoning).

Run each file's full contents, in this order, each as its own SQL-editor execution (each file is already wrapped in its own `begin;`/`commit;`, so paste one file at a time rather than concatenating them):

```sql
-- 1. supabase/migrations/0020_components_catalog.sql
-- 2. supabase/migrations/0021_component_aliases.sql
-- 3. supabase/migrations/0022_component_submissions.sql
-- 4. supabase/migrations/0023_retailers_and_retail_variants.sql
```

If any file errors, **stop** — do not proceed to the next one. A failure partway through a file rolls back that file's own transaction automatically (each is one `begin;`/`commit;` block), so the schema is left exactly as it was before that attempt; nothing needs manual cleanup at that point. Diagnose and fix before retrying that same file.

### 1.1 Expected result after each file

Run these checks after each migration (SQL editor or `psql`) before moving to the next:

**After `0020`:**
```sql
select to_regclass('public.catalog_moderators'), to_regclass('public.components');
-- both non-null

select proname from pg_proc where proname = 'is_catalog_moderator';
-- 1 row

select has_function_privilege('authenticated', 'public.is_catalog_moderator(uuid)', 'execute');
-- true
select has_function_privilege('anon', 'public.is_catalog_moderator(uuid)', 'execute');
-- false — this is the fix from the audit; confirm it actually took

select polname, cmd from pg_policies where tablename = 'components';
-- "Components catalog is readable by everyone" | SELECT
-- "Catalog moderators can add catalog components" | INSERT
```

**After `0021`:**
```sql
select to_regclass('public.component_aliases');
-- non-null

select indexname from pg_indexes where tablename = 'component_aliases';
-- component_aliases_pkey, component_aliases_technology_field_normalized_idx, component_aliases_component_id_idx
```

**After `0022`:**
```sql
select to_regclass('public.component_submissions');
-- non-null

select proname from pg_proc
where proname in ('approve_component_submission', 'reject_component_submission', 'enforce_component_submission_pending_cap')
order by proname;
-- all three present

select conname from pg_constraint where conname = 'component_submissions_status_consistency';
-- 1 row

select has_function_privilege('anon', 'public.approve_component_submission(uuid, uuid)', 'execute');
-- false
```

**After `0023`:**
```sql
select to_regclass('public.retailers'), to_regclass('public.component_retail_variants'), to_regclass('public.component_retailer_links');
-- all three non-null

select conname from pg_constraint
where conname in ('component_retail_variants_component_variant_name_key', 'component_retailer_links_variant_url_key');
-- both present — these two were missing entirely before the audit pass, worth confirming specifically
```

---

## 2. Running the SQL test suite

File: `supabase/tests/milestone_19_parts_catalog.test.sql`. Its own header repeats the essentials, but concretely:

```sql
-- Paste the entire file's contents into the SQL editor and run it as one execution.
```

The file manages its own transaction (`begin;` ... `rollback;` at the very end) — run it exactly as-is, don't wrap it in anything else, and don't manually `commit` partway through.

### 2.1 Expected output

8 tests, each printing exactly one `PASS` or `FAIL` line via `RAISE NOTICE`/`RAISE WARNING` (test 4 and test 6 each print two — a/b — so 10 lines total: 1, 2a, 2b, 2c, 3, 4a, 4b, 5a, 5b, 5c, 6a, 6b — that's actually 12 lines; count what you see against this list, not against a round number):

```
PASS (test 1): duplicate normalization correctly rejected
PASS (test 2a): duplicate alias text correctly rejected
PASS (test 2b): cross-table alias/canonical collision correctly rejected
PASS (test 2c): new-component-vs-existing-alias collision correctly rejected
PASS (test 3): unauthorized approval correctly rejected
PASS (test 4a): first approval left the submission in a fully consistent approved state
PASS (test 4b): repeated approval correctly rejected
PASS (test 5a): submitter successfully withdrew their own pending submission
PASS (test 5b): a different user could not withdraw someone else's pending submission
PASS (test 5c): submitter could not withdraw their own already-resolved submission
PASS (test 6a): rejection left a fully consistent rejected state
PASS (test 6b): repeated rejection correctly rejected
```

**Any `WARNING` line is a real finding** — read its message (each one states exactly what was expected vs. what happened) and treat it as a genuine defect in the migrations, not a test-file problem, unless investigation shows otherwise. Per this task's own instruction: do not make further architecture changes speculatively — only in direct response to a concrete `FAIL` this run surfaces.

### 2.2 If the run errors before printing all 12 lines

The most likely cause is environment-specific, not a migration bug: `auth.users`' exact required columns vary by Supabase/GoTrue version, and the file's fixture insert (`insert into auth.users (id, email) values (...)`) uses the minimal commonly-documented shape. If it errors there, check the actual error against your project's `auth.users` schema (`\d auth.users` in `psql`, or the Table Editor) and adjust the insert's column list — this is a test-fixture adjustment, not a schema defect in `0020`–`0023`.

### 2.3 After the test file finishes

Confirm nothing persisted:
```sql
select count(*) from public.components where canonical_name like '%Test%' or canonical_name in ('RTX 4080', 'RTX 4080 Super');
select count(*) from auth.users where email like 'm19-%@example.invalid';
-- both 0 — the file's fixtures (including the two seed RTX components) and every test user must be gone
```

If either is non-zero, the file's trailing `rollback;` didn't run — most likely because something outside this procedure issued a `commit` or the connection dropped mid-script. Investigate before proceeding; do not manually delete the leftover rows as a substitute for finding out why the rollback didn't fire.

---

## 3. Rollback verification

Run this as its own drill — ideally on the staging project, or scheduled for a moment you're prepared to immediately re-apply forward (§1) afterward, since rolling back removes real schema other verification steps depend on.

Apply in **exact reverse order**:
```sql
-- 1. supabase/migrations/0023_retailers_and_retail_variants_rollback.sql
-- 2. supabase/migrations/0022_component_submissions_rollback.sql
-- 3. supabase/migrations/0021_component_aliases_rollback.sql
-- 4. supabase/migrations/0020_components_catalog_rollback.sql
```

### 3.1 Expected result after each rollback

```sql
-- after 0023's rollback:
select to_regclass('public.retailers'), to_regclass('public.component_retail_variants'), to_regclass('public.component_retailer_links');
-- all three NULL; public.components still non-null (0023's rollback must not touch it)

-- after 0022's rollback:
select to_regclass('public.component_submissions');
select proname from pg_proc where proname in ('approve_component_submission', 'reject_component_submission', 'enforce_component_submission_pending_cap');
-- table NULL, zero function rows

-- after 0021's rollback:
select to_regclass('public.component_aliases');
select proname from pg_proc where proname = 'set_component_alias_technology_and_field';
-- table NULL, zero function rows

-- after 0020's rollback:
select to_regclass('public.catalog_moderators'), to_regclass('public.components');
select proname from pg_proc where proname = 'is_catalog_moderator';
-- both tables NULL, zero function rows
```

### 3.2 Re-apply forward

Immediately re-run §1 in full (`0020` → `0021` → `0022` → `0023`) so the environment is left in the applied state for §6's browser smoke test. Re-run §1.1's checks once more after — a rollback/re-apply cycle is exactly the kind of operation that can leave something subtly different (e.g. an index that failed to recreate) if a file has a real bug, so this second pass through §1.1 is not redundant.

---

## 4. Granting the test moderator

No self-service admin UI ships this milestone (documented, tracked risk — see the architecture doc §6). After creating the moderator account in §6.1, grant it directly:

```sql
insert into public.catalog_moderators (user_id, granted_by)
values ('<moderator-account-uuid>', '<moderator-account-uuid>');
```

Find the uuid via `select id from auth.users where email = '<the test moderator's email>';` or the Auth section of the dashboard.

---

## 5. Application-code sanity check (pre-browser)

Before the browser pass, confirm the app is actually pointed at the project you just migrated — `js/core/config.js`'s `SUPABASE_URL` should match. If you used a separate staging project for §2/§3, either swap this file's values temporarily for the browser pass, or re-run §1 against the real project first (uncommitted, purely additive — safe to do either way per §0).

---

## 6. Browser smoke-test checklist

Two accounts, created through the app's normal signup flow (`pages/signup.html`) — not inserted directly:

- **Ordinary user** — no special setup.
- **Catalog moderator** — same signup flow, then granted via §4.

Use obviously-disposable emails/usernames (e.g. `m19-tester+ordinary@...`, `m19-tester+moderator@...`) so they're easy to distinguish from real users in Explore/search afterward, and consider whether to delete them once done.

### 6.1 Setup
- [ ] Sign up the ordinary-user account.
- [ ] Sign up the moderator account.
- [ ] Grant the moderator account `catalog_moderators` status (§4).

### 6.2 Ordinary user — free text always works, no catalog required
- [ ] Signed in as the ordinary user, create a new project (any technology).
- [ ] In the editor's Specifications tab, type a value into any field that's very unlikely to exist in the catalog yet (e.g. a made-up model name).
- [ ] Confirm the value saves normally (autosave indicator, and it's still there after a page reload) — this must work with zero dependency on anything below.

### 6.3 Ordinary user — submitting a new component for review
- [ ] With that same unmatched value still typed, confirm the autocomplete's empty state shows "Suggest '\<value>' as a new component."
- [ ] Click it. Confirm: a "Submitting..." state briefly appears, then a success message, and a toast ("Submitted for catalog review...").
- [ ] Confirm the typed value is still saved on the build (submitting doesn't change what's on your own project either way).
- [ ] As the SQL editor (or the moderator's own "view all" access — see 6.5), confirm a new `pending` row exists in `component_submissions` with `submitted_by` = the ordinary user's id.

### 6.4 Ordinary user — paste-list import review states
- [ ] In the same or a new project's Specifications tab, open "Import from a parts list."
- [ ] Paste a list mixing three kinds of lines: (a) a field label + a value you know is an exact match to something already in the catalog (use a value approved in 6.6 first, or a value you've pre-approved via SQL for this purpose), (b) a field label + a plausible-but-not-exact value (to trigger a fuzzy "Possible match" suggestion, if any catalog data exists close enough — otherwise this line will land in "Needs review" as plain unmatched text, which is also correct behavior), (c) a line whose label doesn't match any field for the chosen technology at all.
- [ ] Click "Review matches." Confirm three sections appear as applicable: **Matched**, **Needs review**, **Unrecognized** — confirm the type-(c) line appears under Unrecognized with a field-assignment dropdown, not silently missing.
- [ ] For the Unrecognized line, pick a field from its dropdown. Confirm it moves into Matched or Needs review (not stuck, not duplicated).
- [ ] If a "Possible match" suggestion appeared, confirm it is **not** pre-attached (no componentId) until you click "Use this match" — then confirm clicking it moves that row into the Matched-equivalent confirmed state.
- [ ] Click "Import reviewed values." Confirm the specifications fields update accordingly and autosave.

### 6.5 Moderator — review queue access
- [ ] As the moderator, via the SQL editor (no UI ships this milestone — expected): `select * from component_submissions where status = 'pending' order by created_at;` — confirm the ordinary user's submission(s) from 6.3 are visible.
- [ ] Confirm the moderator can see submissions from users other than themselves (tests the "Moderators can view all submissions" policy, distinct from the "Users can view their own" policy the ordinary user relies on).

### 6.6 Moderator — approve as new component
- [ ] Pick the pending submission from 6.3. As the moderator: `select approve_component_submission('<submission-id>');` (no `alias_of_component_id` — creates a new component).
- [ ] Confirm it returns a uuid (the new `components.id`), and re-querying `component_submissions` shows `status = 'approved'`, `resolved_component_id` set to that same id, `moderator_id` = the moderator's own id, `reviewed_at` set.
- [ ] Back in the browser as the ordinary user (or a fresh session), type the now-approved value into the same field's autocomplete. Confirm it now appears as a real catalog match (selecting it attaches a real `componentId`).

### 6.7 Moderator — approve as alias
- [ ] Submit a second, differently-worded value for the *same real part* as 6.6 (e.g. a shorthand or alternate spelling) — either via the app as the ordinary user (6.3's flow again) or directly via SQL as a submission row.
- [ ] As the moderator: `select approve_component_submission('<new-submission-id>', '<the-6.6-component-id>');` — this time providing the alias target.
- [ ] Confirm a new row exists in `component_aliases` pointing at the 6.6 component, and the submission resolved to that same existing component id (not a new one).
- [ ] In the browser, type the alias text into the same field. Confirm it now resolves to the 6.6 component (exact-match "Catalog match" state, not a fuzzy suggestion) — this exercises `findExactComponentMatch()`'s alias-lookup path specifically.

### 6.8 Moderator — reject
- [ ] Submit a clearly-junk value as the ordinary user.
- [ ] As the moderator: `select reject_component_submission('<submission-id>', 'not a real component');`
- [ ] Confirm `status = 'rejected'`, `resolved_component_id IS NULL`, `moderator_note = 'not a real component'`.

### 6.9 Repeated approval / unauthorized approval (optional — already covered by §2's automated test)
- [ ] Optional manual spot-check: as the ordinary user (not a moderator), attempt `select approve_component_submission('<any-submission-id>');` via the SQL editor using that user's own session — confirm it's rejected. This duplicates automated test 3; only worth doing by hand if you want to see the real RLS/role behavior once, not as a substitute for §2.

### 6.10 Regression pass — unaffected areas still work
- [ ] A category page (e.g. `pages/categories/pc-builds.html`) still loads and shows featured builds.
- [ ] Explore's `?category=` param still pre-filters correctly.
- [ ] A build with old-shape (plain-string) `specifications` still renders correctly on its public build page and in `BlueprintCard` — confirms the new schema didn't regress the already-shipped normalizer compatibility work.

---

## 7. Commit structure for this work

Per explicit instruction: keep the migration implementation, the SQL tests, the documentation, and the application-code changes in logically separate commits rather than one large one. See the accompanying commit sequence for this milestone — each commit's message states which of the four categories it belongs to.
