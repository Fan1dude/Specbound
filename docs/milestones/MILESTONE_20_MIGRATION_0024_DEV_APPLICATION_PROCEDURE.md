# Milestone 20: Migration 0024 Development-Environment Application & Verification Procedure

Status: **Ready to execute.** 2026-08-01. Written for a human operator with real Supabase dashboard/SQL-editor access — this implementation environment has none (anon-key only), so nothing in this document has been run. It's the exact sequence to follow, not a report of having followed it.

Covers: applying `0024_profile_headline_and_featured_build.sql`, verifying the ownership trigger and length CHECK behave correctly, verifying rollback, and a browser smoke test of the Builder Portfolio page and Settings' new controls with one ordinary user. See `MILESTONE_20_BUILDER_PORTFOLIO_SPECIFICATION.md` §16 for the schema design and rationale.

---

## 0. Prerequisites

- **A Supabase project with migrations `0000`–`0023` already applied.** Confirm readiness: `select to_regclass('public.profiles'), to_regclass('public.builds');` should return two non-null values, and `select column_name from information_schema.columns where table_name = 'profiles' and column_name in ('headline', 'featured_build_id');` should return **zero rows** — if either already exists, `0024` was already applied (or partially applied) to this project; stop and investigate before re-running it.
- **Dashboard/SQL-editor access to that project**, not just the anon key `js/core/config.js` ships with.
- **Prefer a disposable/staging project** for this pass, same reasoning as Milestone 19's procedure: this migration is additive-only (two new nullable columns, one new CHECK, one new trigger — nothing here alters or drops an existing column or table), but "additive" isn't the same as "verified safe in practice." If a staging project isn't practical, running against the shared real project is still safe per the migration's own design — just be deliberate about the two test builds in §4 (clearly-labeled, disposable).
- **Two throwaway builds owned by the same test account**, or the ability to create them through the app's normal Publish flow — §2's ownership-trigger test needs one build the test account owns and one it doesn't (any existing public build from a different account works for the second).

---

## 1. Applying the migration

```sql
-- supabase/migrations/0024_profile_headline_and_featured_build.sql
```

Paste the full file contents as one SQL-editor execution (it's already wrapped in its own `begin;`/`commit;`). If it errors, that transaction rolls back automatically — nothing to clean up before retrying.

### 1.1 Expected result

```sql
select column_name, is_nullable, data_type
from information_schema.columns
where table_name = 'profiles' and column_name in ('headline', 'featured_build_id')
order by column_name;
-- featured_build_id | YES | uuid
-- headline          | YES | text

select conname, contype from pg_constraint
where conrelid = 'public.profiles'::regclass
  and conname in ('profiles_headline_length_check');
-- profiles_headline_length_check | c   (CHECK)

select conname from pg_constraint
where conrelid = 'public.profiles'::regclass
  and confrelid = 'public.builds'::regclass;
-- one row — the featured_build_id foreign key (name will be
-- auto-generated, e.g. profiles_featured_build_id_fkey)

select proname from pg_proc where proname = 'validate_featured_build';
-- 1 row

select tgname from pg_trigger where tgrelid = 'public.profiles'::regclass and tgname = 'validate_featured_build_before_write';
-- 1 row
```

---

## 2. Verifying the ownership trigger and length CHECK

Run as the test account (or via SQL editor with `set role` / impersonation, whichever this project's access supports) so `auth.uid()` resolves the way the app's own RLS-covered `UPDATE` would:

```sql
-- 2a. Setting featured_build_id to a build the test account OWNS — should succeed.
update public.profiles
set featured_build_id = '<a build id owned by this same account>'
where id = '<test-account-id>';
-- UPDATE 1, no error

-- 2b. Setting featured_build_id to a build owned by a DIFFERENT account — must be rejected.
update public.profiles
set featured_build_id = '<a build id owned by someone else>'
where id = '<test-account-id>';
-- ERROR: featured_build_id must reference a build owned by this profile

-- 2c. Clearing the pin — should always succeed regardless of ownership state.
update public.profiles set featured_build_id = null where id = '<test-account-id>';
-- UPDATE 1

-- 2d. Headline at exactly 120 chars — should succeed.
update public.profiles set headline = repeat('a', 120) where id = '<test-account-id>';
-- UPDATE 1

-- 2e. Headline at 121 chars — must be rejected.
update public.profiles set headline = repeat('a', 121) where id = '<test-account-id>';
-- ERROR: new row for relation "profiles" violates check constraint "profiles_headline_length_check"

-- 2f. Headline back to null — should succeed (both new columns are independently optional).
update public.profiles set headline = null where id = '<test-account-id>';
-- UPDATE 1
```

### 2.1 ON DELETE SET NULL behavior

```sql
-- Pin a build, then delete it, and confirm the pin clears itself rather
-- than erroring or leaving a dangling reference.
update public.profiles set featured_build_id = '<a build id owned by this account>' where id = '<test-account-id>';
delete from public.builds where id = '<that same build id>';
select featured_build_id from public.profiles where id = '<test-account-id>';
-- null
```

**Any result other than what's shown above is a real finding** — treat it as a genuine defect in the migration, not a procedure problem, unless investigation shows otherwise.

---

## 3. Rollback verification

```sql
-- supabase/rollbacks/0024_profile_headline_and_featured_build_rollback.sql
```

### 3.1 Expected result after rollback

```sql
select column_name from information_schema.columns
where table_name = 'profiles' and column_name in ('headline', 'featured_build_id');
-- 0 rows

select tgname from pg_trigger where tgname = 'validate_featured_build_before_write';
select proname from pg_proc where proname = 'validate_featured_build';
-- 0 rows each
```

### 3.2 Re-apply forward

Immediately re-run §1 so the environment is left in the applied state for §4's browser pass. Re-run §1.1's checks once more after — confirms the rollback/re-apply cycle didn't leave anything subtly different.

---

## 4. Application-code sanity check (pre-browser)

Confirm `js/core/config.js`'s `SUPABASE_URL` actually points at the project you just migrated before the browser pass.

---

## 5. Browser smoke-test checklist

One account, created through the app's normal signup flow, with at least two of its own published (public) projects already existing (create them through the normal Publish flow if needed — one can be left `planning`/`in_progress`, the other set to `completed`, to exercise the fallback chain in §5.4).

### 5.1 Settings — headline
- [ ] Sign in, go to Settings. Confirm a "Headline" field is present with a live `0/120` counter below it.
- [ ] Type a headline. Confirm the counter updates as you type and stops accepting input past 120 characters.
- [ ] Save. Reload Settings. Confirm the headline persisted.
- [ ] Clear the headline entirely and save. Confirm it saves as empty (not an error) — the field is optional.

### 5.2 Settings — Featured Build picker
- [ ] Confirm the "Featured Project" select is present, defaulting to "Choose automatically."
- [ ] Confirm its option list contains **only this account's own published projects** — not drafts, not other builders' projects. (This is the primary correctness guard per spec §20.2; the database trigger from §2 above is defense in depth, not what a real user ever encounters.)
- [ ] Pick one of the two test projects, save. Reload Settings. Confirm the same project is still selected.

### 5.3 Profile page — pinned Featured Project
- [ ] Visit this account's own profile page (`pages/profile.html?user=<id>`).
- [ ] Confirm the Featured Project section shows the project picked in §5.2, not an automatically-selected one.

### 5.4 Profile page — fallback chain
- [ ] Back in Settings, set Featured Project back to "Choose automatically," save.
- [ ] Reload the profile page. Confirm Featured Project now shows the **completed** test project (the fallback's first tier), not the other one.
- [ ] If only one public project exists at this point, confirm Featured Project shows it regardless of status (the fallback's second tier).
- [ ] If this account has zero public projects, confirm the Featured Project section is omitted entirely (not shown empty) — see spec §7.

### 5.5 Regression pass — unrelated pages unaffected
This is the specific regression the Milestone 20 polish pass fixed (`getPublicProfile`/`getProfilesByIds` no longer request `headline`/`featured_build_id`, so they don't depend on `0024` being applied at all) — confirm it still works **after** `0024` is applied, not just before:
- [ ] Home page's Featured section loads and shows correct creator attribution for each build.
- [ ] Explore loads and shows correct creator attribution.
- [ ] A build page (`pages/build/build.html?slug=...`) shows the correct creator in its byline.
- [ ] The followers/following list pages load correctly for this account.

---

## 6. Commit reference

All Milestone 20 application-code and CSS changes (repository/data logic, section components, page wiring, Settings UI, the visual polish pass, and the final responsive refinements) are already committed on `milestone-20-builder-portfolio` — see that branch's commit list. This procedure covers only the one remaining step: applying `0024` itself, which per standing instruction has not been run from this implementation environment and requires a human operator with real dashboard/SQL access.
