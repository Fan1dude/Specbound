# Operations

**Status: current and accurate as of Milestone 27A PR4 (documentation-only), 2026-08-15.** Companion to `docs/DEPLOYMENT.md` (initial setup) — this document covers the ongoing day-to-day of running Specbound in production: redeploying, rolling back, releasing changes, rotating credentials, updating dependencies, and what to do when something breaks. §10 onward (added by Milestone 27A PR4) cover manual account deletion, staff bootstrap, an incident runbook, and adult-owner-gated checklists for backups/monitoring and Storage configuration.

**A note on scope for §10-§14**: Specbound's owner is a minor. Legal publication, age-policy decisions, external-account ownership, production moderator bootstrap, and handling of account-deletion requests all require an adult owner/guardian's direct action or explicit authorization — every section below states exactly where that gate applies. Nothing in §10-§14 has been executed; these sections document procedures only.

---

## 1. Redeployment

Nothing special — push to the production branch. Cloudflare Pages auto-builds and auto-deploys on every push (see `docs/DEPLOYMENT.md` §4). There is no separate "trigger a redeploy" step for a normal code change; the deploy *is* the push.

To force a redeploy with no code change (e.g. after a Cloudflare-side issue, or to pick up a dashboard setting change that needs a fresh build): Cloudflare dashboard → Pages project → **Deployments** → **Retry deployment** on the latest one, or push an empty commit (`git commit --allow-empty -m "Trigger redeploy"`).

## 2. Rollback

Full procedure in `docs/DEPLOYMENT.md` §13. Summary: Cloudflare dashboard → Deployments → pick the last known-good one → promote it to production. Immediate, no rebuild, no git operation needed. Use this the moment a deploy is suspected bad — don't wait to diagnose the root cause first; roll back, then investigate calmly with the site already stable.

## 3. Releasing updates

This is a solo/small-scale project today (single `master` branch, no staging environment — see `docs/milestones/MILESTONE_9_PHASE_9D_ARCHITECTURE.md` §1.5 for why a dedicated staging branch isn't recommended). The release flow:

1. Make the change locally, verify it against the local dev server (`.claude/nocache_server.py` on port 8431) as this project has done throughout Milestones 1-9.
2. Commit with a clear message describing *why*, not just *what* (matches this project's established commit convention — see recent commits for examples).
3. Push to the production branch. This *is* the release — no separate "deploy step" or "release cut" process exists or is needed for a project this size.
4. Run the relevant subset of the smoke-test checklist (`docs/DEPLOYMENT.md` §12) against the live production URL after the deploy completes.
5. For anything touching Storage, RLS, or auth specifically: don't skip the smoke test. This app's history (Migrations A/B/C) shows exactly how subtle and high-consequence a mistake in that area can be — see `docs/STORAGE_ARCHITECTURE.md` and `docs/AUTH_ARCHITECTURE.md`.

**Database migrations are a separate, manual process**, unrelated to Cloudflare Pages deploys: this project has no automated migration runner. New migrations go in `supabase/migrations/` (sequential, zero-padded, with a matching rollback file in `supabase/rollbacks/` — kept in a separate folder so a real Supabase project's tooling doesn't mistake a rollback for a forward migration, logged in `supabase/migrations.md`) and are run manually in the Supabase SQL editor — the implementation environment has never had direct database execution access, by design. A Cloudflare Pages deploy never touches the database; a migration never touches the deployed site. Keep these two release paths mentally separate.

## 4. Cache invalidation

Automatic on every Cloudflare Pages deploy — see `docs/DEPLOYMENT.md` §10 for the full reasoning (and why this app deliberately does *not* set custom long-lived cache headers). Nothing to do here in normal operation. If a stale-asset issue is ever suspected: Cloudflare dashboard → Caching → **Purge Cache**, as a manual fallback.

## 5. Rotating credentials

The only credential this app's client code holds is `SUPABASE_KEY` in `js/core/config.js` — the publishable (`sb_publishable_...`) key, safe for public exposure by design (it's meant to be shipped to every browser; see `docs/STORAGE_ARCHITECTURE.md` §1 for why this doesn't grant broad access — RLS is the real security boundary, not key secrecy).

To rotate it (e.g. as a periodic hygiene practice, or if ever suspected compromised in a way that matters — unlikely given it's meant to be public, but Supabase does allow regenerating it):

1. Supabase dashboard → Project Settings → API → regenerate the publishable key.
2. Update `SUPABASE_KEY` in `js/core/config.js` to the new value.
3. Commit and push — this deploys like any other code change (§3).
4. **Old key behavior**: confirm with Supabase's current documentation whether the old key is invalidated immediately or has a grace period — plan the rollout window accordingly so there's no gap where neither key works for in-flight users.

There is no service-role key, database password, or other server-side secret anywhere in this codebase to rotate — this architecture has no server component beyond Supabase itself. If that ever changes (e.g. a future serverless function is added), this section will need real secret-management guidance (Cloudflare Pages environment variables, marked as "encrypted" in the dashboard) that doesn't exist today because nothing requires it yet.

## 6. Dependency updates

This app has exactly **one** external runtime dependency: the Supabase JS client, loaded from a **pinned** jsDelivr CDN URL (`js/core/supabase.js` — pinned to an exact version as of Phase 9C, closing out the original audit's B4 finding). There is no `package.json`, no lockfile, no `npm install` — dependency management here means periodically checking whether a newer Supabase client version exists and deliberately deciding whether to move to it.

To update:

1. Check the current pinned version in `js/core/supabase.js`.
2. Check the latest available version (`https://data.jsdelivr.com/v1/packages/npm/@supabase/supabase-js/resolved?specifier=latest`, or the [Supabase JS changelog](https://github.com/supabase/supabase-js/releases)) — review the changelog for breaking changes between the pinned version and the target, since this is a manual, deliberate upgrade, not an automatic one.
3. Update the version number in the pinned URL.
4. Test locally against the dev server — sign in, sign up, upload an image, publish a build, check comments/likes/follows — the full surface that touches the Supabase client.
5. Push. Verify against production after deploy (§3, §9 smoke tests).

Google Fonts and the Supabase project's own API/Storage/Auth endpoints are the only other external dependencies — neither is a "package" to version/update; they're services consumed via URL, unaffected by this process.

## 7. Error monitoring

This app has no error-tracking/monitoring service today — production errors are only visible to whichever single user hits them, in their own browser console, with no automatic notification. Tracked as **L10** in the original Milestone 9 audit. This section documents the recommended fix; it hasn't been implemented yet (no new table, no new client code shipped as part of this entry — a deliberate, separate follow-up).

**Recommended approach: log to a Supabase table, not a new vendor.** This app already has exactly one backend dependency (Supabase) and an explicit preference for not adding new external services where an existing one covers the need (§6). The lightest path that actually closes the L10 gap:

1. **A new `client_errors` table**, migration-tracked like everything else in `supabase/migrations/`: `id`, `created_at`, `message`, `stack` (truncated), `url`, `user_id` (nullable — anonymous visitors hit errors too), `user_agent`. RLS: **INSERT-only for `anon`/`authenticated`, no SELECT policy for either** — the same "write-only from the client, read only via the dashboard" shape already used correctly elsewhere in this schema. Only the project owner (via the Supabase dashboard's table editor or SQL editor) can read it.
2. **A single global handler**, added once to `js/core/layout.js` (already loaded on every page via `loadNavbar()`/`loadFooter()`) or as its own small `js/core/errorMonitoring.js` module:
   ```js
   window.addEventListener("error", (e) => reportError(e.error ?? e.message));
   window.addEventListener("unhandledrejection", (e) => reportError(e.reason));
   ```
   `reportError()` writes one row via the existing `supabase` client — the same publishable key already used for everything else, no new credential. Debounce/dedupe identical messages within a short window (e.g. per page load) so a loop-shaped bug can't flood the table.
3. **Deliberately excluded from this table**: request/response bodies, form field values, anything that could contain user-entered content beyond an error message — this is a debugging aid, not a session replay tool. Keep it to what a developer needs to reproduce the bug (message, stack, URL, rough "was this user signed in" context), nothing more.
4. **Checking it**: no dashboard needed at first — an occasional `select * from client_errors order by created_at desc limit 50` in the Supabase SQL editor (§9's periodic-checks table already includes this cadence). If error volume ever justifies it, this table is also a normal Supabase data source a lightweight internal dashboard (or a scheduled digest email via Supabase's own cron/Edge Functions) could read from later — not needed at launch.

**Why not a third-party service (Sentry, etc.) instead**: not ruled out permanently — if error volume or team size grows, a dedicated tool's stack-trace grouping and alerting genuinely earns its keep. At today's scale (solo/small-scale, per §3), it's an extra account, an extra script tag to add to the CSP `script-src` (§9's "CSP footprint" item), and a dependency this app doesn't otherwise have, for a problem the existing backend already solves adequately.

## 8. Incident response basics

Until the above is implemented, the same manual constraint applies: there is no way to be automatically notified of a client-side error today.

Given that constraint, incident response for this app is necessarily more manual:

1. **If a user reports something broken**: reproduce it yourself against production first (not the dev server) — open the browser console, check `read_network_requests`-equivalent (or your browser's Network tab) for failed requests, check for CSP violations if the symptom looks resource-related.
2. **If a deploy is the suspected cause**: roll back immediately (§2) before diagnosing — don't leave production broken while investigating.
3. **If Supabase itself is down or degraded**: check [Supabase's status page](https://status.supabase.com) — this app has no fallback/offline mode, since every real feature (auth, data, storage) depends on Supabase being reachable. Nothing to do on the Specbound side except wait and communicate, unless the outage reveals a specific bug in this app's own error handling (e.g. an unhandled rejection instead of a graceful toast) — that would become a normal bug fix + release (§3).
4. **If a security issue is discovered** (e.g. an RLS gap like the ones found and fixed in Migrations A/B/C): treat with the same rigor this project already established — audit live via the anon key first, design a scoped migration with a rollback file, verify anonymous/owner/cross-user behavior explicitly before and after, document in `supabase/migrations.md`. Do not patch RLS live in the Supabase dashboard without a corresponding tracked migration file — that's exactly the untracked-policy problem Migration A (`0017_storage_rls_hardening.sql`) had to clean up.
5. **If credentials need emergency rotation**: see §5. Given the only client-side credential is a publishable key with no meaningful "compromise" blast radius (RLS is the real boundary), this is a low-urgency scenario in this app's current architecture.

## 9. Production maintenance

Recurring things worth checking periodically, not because anything is currently wrong, but because they're easy to forget on a project with no automated reminders:

| Item | Frequency | What to check |
|---|---|---|
| `client_errors` table (§7, once implemented) | Weekly, or after any deploy touching a high-traffic page | New rows since the last check — anything recurring or new since the last deploy? |
| Supabase CDN pin (§6) | Occasionally | Is a newer Supabase JS client version available? Worth the upgrade? |
| Supabase backup/PITR tier | Once, then rarely | Confirm the project's plan tier still matches actual data-loss tolerance (tracked as **L4** in the original audit, part of Phase 9E) |
| SMTP/email provider | Once, before real signup volume | Supabase's default email service has strict rate limits — confirm custom SMTP is configured before relying on password-reset/signup emails at any scale (tracked as **L9**) |
| Domain/SSL | Rarely (Cloudflare auto-renews) | Spot-check the site is still serving over valid HTTPS |
| `robots.txt`/`sitemap.xml` accuracy | When new public pages are added | New static pages (e.g. a new category) should be added to `sitemap.xml`; new private/account pages should be added to `robots.txt`'s disallow list, matching the pattern in `docs/DEPLOYMENT.md` §11 |
| Dead code / duplication | Periodically | Phase 9C found real recurrence of "imported but fully dead" CSS and duplicated utilities even after an earlier (8D) cleanup pass — worth an occasional fresh audit rather than assuming one cleanup pass is permanent |
| CSP footprint | Whenever a new external resource is added | Any new external script/font/API host must be added to `_headers`' CSP *before* the code that uses it ships, or it will be silently blocked in production (verify via the same meta-tag/temporary-header technique used during Phase 9D implementation — see `docs/DEPLOYMENT.md` §10) |
| Deployment surface | Whenever a new top-level directory is added to the repo | `tools/ci/check-deployment-surface.js` (CI-enforced) only knows about the internal directories that existed when it was written (`docs/`, `supabase/`, `tests/`, `tools/`, `.github/`, `.claude/`, blocked via `functions/docs/[[path]].js` / `functions/supabase/[[path]].js` plus the pre-existing Dashboard build-command/WAF layer — see `docs/DEPLOYMENT.md` §5). A genuinely new internal-only top-level directory (e.g. a future `scripts/` or `reports/`) needs its own Function and its own entry in that check's `EXCLUDED_PREFIXES` list, or it will be served publicly by default — Cloudflare Pages has no allowlist-by-default behavior for a Git-integrated project at this repo's current Dashboard settings. |

## 10. Account deletion (manual, staff-run)

> **Production-use disclaimer**: this procedure has been rehearsed only against disposable local fixtures, inside a Postgres transaction that was rolled back — it has **never been executed against production**. Using it against real production data requires, every time: separate adult-owner authorization for that specific case (§10.2), independent identity verification (§10.1), a current backup/PITR confirmation (§10.5), and a fresh re-read of this entire section against the live schema immediately before use. Schemas drift; a stale reading of this document is not a substitute for re-checking it.

**Specbound has no self-service account-deletion flow today.** This procedure is the only path by which a user's account and published builds are removed, and it is manual, staff-run, and gated on adult-operator approval at every irreversible step. It reflects the approved decision to hard-delete a departing user's published builds along with their account — not a soft-delete or anonymization.

Every schema fact cited below (column nullability, constraint definitions, `ON DELETE` behavior) was confirmed by direct, read-only queries (`information_schema.columns`, `pg_constraint`) against the linked production project on 2026-08-15, not assumed from memory.

### 10.1 Intake and identity verification

A deletion request arrives through the future contact method 27B will define (no in-app request flow exists yet — this is a known gap, not an oversight). Whatever channel it arrives on:

1. Verify the requester's identity is genuinely tied to the account in question before doing anything else — this procedure never acts on an unverified claim of ownership.
2. Record the request and verification outcome wherever 27B's process specifies (not in this repository, and never with the account's real identifiers committed anywhere in git history). See §10.13 for exactly how the verified identifier itself must be handled from this point forward.

### 10.2 Adult-operator approval

No step past this point runs without a specific adult operator's explicit go-ahead for *this* request. Approval of the procedure existing is not approval to run it — each real deletion is its own authorization event.

### 10.3 Read-only dry-run inventory

Run every query below before touching anything. `<TARGET_USER_ID>` is a placeholder — substitute the real id only at execution time; see §10.13 for how long it may be retained afterward. The goal of this section is that the operator can see the **complete blast radius** — every table this deletion touches, and exactly how — before authorizing anything irreversible; the categorized reference table at the end of this section summarizes it.

**Identity and role holdings:**

```sql
-- 1. Confirm the account exists (operator's own verification only — see §10.13)
select id, created_at from auth.users where id = '<TARGET_USER_ID>';

-- 2. Role holdings
select role, granted_at, granted_by from public.profile_roles where user_id = '<TARGET_USER_ID>';
```

**Staff-safety check — two separate facts on purpose, never conflate them:**

```sql
-- 3a. Does the target itself currently hold 'staff'? This MUST be checked before query 3b means
--     anything. If this is false, query 3b's result is not relevant to this deletion at all.
select exists (
  select 1 from public.profile_roles where user_id = '<TARGET_USER_ID>' and role = 'staff'
) as target_is_staff;

-- 3b. Count of OTHER verified staff accounts (target already excluded either way). Only apply the
--     "would leave zero staff" abort criterion (§10.4) when 3a is true. A low or zero count here
--     when 3a is FALSE — e.g. because no bootstrap (§11) has happened yet — is not itself a reason
--     to block deleting an account that was never staff.
select count(*) as other_staff_accounts
from public.profile_roles
where role = 'staff' and user_id <> '<TARGET_USER_ID>';

-- 4. Moderation-action audit-trail-loss check — non-zero means deleting this account will
--    CASCADE-delete these audit rows (moderation_actions.actor_id is NOT NULL, FK ON DELETE CASCADE
--    to auth.users — there is no way to null it out and keep the row). See §10.4's footnote on
--    audit-record durability.
select count(*) as moderation_actions_authored
from public.moderation_actions
where actor_id = '<TARGET_USER_ID>';
```

**Content this account owns or authored directly:**

```sql
-- 5. Published/private builds owned by this account (builds.user_id has NO foreign key at all —
--    nothing cascades here automatically; this list is exactly what step 10.6 must delete explicitly)
select id, title, slug, visibility, created_at
from public.builds
where user_id = '<TARGET_USER_ID>';

-- 6. Build revisions authored by this account, independent of builds.user_id — build_revisions.user_id
--    carries no required relationship to builds.user_id, so this can in principle diverge from query 5
select id, build_id, version, created_at
from public.build_revisions
where user_id = '<TARGET_USER_ID>';

-- 7. Drafts — informational only; project_drafts.user_id cascades automatically once the Auth user
--    is deleted (step 10.7), listed here only so the operator knows what that cascade will remove
select id, title, updated_at from public.project_drafts where user_id = '<TARGET_USER_ID>';
```

**Community activity — all CASCADE-deleted automatically by the Auth admin call (§10.7). Nothing here needs a manual delete step; these queries exist purely so the operator sees the full blast radius before authorizing:**

```sql
-- 8. Comments authored by this account
select count(*) from public.comments where user_id = '<TARGET_USER_ID>';

-- 9. Likes given by this account
select count(*) from public.likes where user_id = '<TARGET_USER_ID>';

-- 10. Saved builds (private bookmarks) belonging to this account
select count(*) from public.saved_builds where user_id = '<TARGET_USER_ID>';

-- 11. Follows in both directions
select count(*) as accounts_this_user_follows from public.follows where follower_id = '<TARGET_USER_ID>';
select count(*) as accounts_following_this_user from public.follows where following_id = '<TARGET_USER_ID>';

-- 12. Connected social accounts (e.g. Discord)
select count(*) from public.social_connections where user_id = '<TARGET_USER_ID>';

-- 13. Saved Setup-technology categories
select count(*) from public.saved_setup_categories where user_id = '<TARGET_USER_ID>';

-- 14. Notifications in both directions. The actor-direction count is the one that silently removes
--     entries from OTHER users' notification history, not just this account's own.
select count(*) as notifications_received from public.notifications where recipient_id = '<TARGET_USER_ID>';
select count(*) as notifications_sent_to_others_that_will_be_deleted
from public.notifications
where actor_id = '<TARGET_USER_ID>' and recipient_id <> '<TARGET_USER_ID>';

-- 15. Catalog-moderator membership, and any grants this account made to others as a catalog moderator
select count(*) as catalog_moderator_membership from public.catalog_moderators where user_id = '<TARGET_USER_ID>';
select count(*) as catalog_moderator_grants_made from public.catalog_moderators where granted_by = '<TARGET_USER_ID>';

-- 16. Component submissions — as the submitter, and separately as the reviewing moderator
select count(*) as component_submissions_made from public.component_submissions where submitted_by = '<TARGET_USER_ID>';
select count(*) as component_submissions_reviewed from public.component_submissions where moderator_id = '<TARGET_USER_ID>';
```

**Open moderation/legal context and anonymized-retention content:**

```sql
-- 17. Open reports filed by this account, and reports this account reviewed as a moderator
select id, status, created_at from public.content_reports where reporter_id = '<TARGET_USER_ID>';
select id, status, reviewed_at from public.content_reports where reviewed_by = '<TARGET_USER_ID>';

-- 18. Feedback submissions — survive deletion with user_id set to null (existing, intentional
--     privacy design from Milestone 26 — no action needed, informational only)
select count(*) from public.feedback_submissions where user_id = '<TARGET_USER_ID>';
```

**Storage-object inventory** (also read-only, run before any deletion — these rows will be gone after step 10.6/10.7, so the paths must be captured now or they become unrecoverable for cleanup):

```sql
select revision_media.storage_path
from public.revision_media
join public.build_revisions on build_revisions.id = revision_media.revision_id
join public.builds on builds.id = build_revisions.build_id
where builds.user_id = '<TARGET_USER_ID>';

select project_media.storage_path
from public.project_media
join public.project_drafts on project_drafts.id = project_media.draft_id
where project_drafts.user_id = '<TARGET_USER_ID>';

select avatar_path from public.profiles where id = '<TARGET_USER_ID>';

-- Legacy avatar check — accounts that predate the signed-URL delivery migration (0003) may have
-- avatar_url set with avatar_path still null. This value is NEVER auto-deleted from this query
-- result alone — see §10.8's mandatory manual-verification gate before treating it as a Storage
-- object to remove.
select avatar_url
from public.profiles
where id = '<TARGET_USER_ID>' and avatar_path is null and avatar_url is not null;
```

**Complete blast-radius reference** — every table this deletion touches, grouped by exactly how:

| Table / column (scoped to the target) | Behavior | Notes |
|---|---|---|
| `builds.user_id` | Manual hard-delete | No FK at all; explicit `DELETE` in §10.6 — cascades further on its own |
| `build_revisions.user_id` | Manual, cleared (not deleted) | Blocking FK, `NO ACTION`; explicit `UPDATE ... SET NULL` in §10.6 |
| `profiles.id` | Manual hard-delete | No FK to `auth.users` at all; explicit `DELETE` in §10.6 — prevents recreating the known orphan condition (§10.12) |
| `project_drafts.user_id` (→ `project_media`) | Cascade | Removed automatically by §10.7 |
| `comments.user_id` | Cascade | " |
| `likes.user_id` | Cascade | " |
| `saved_builds.user_id` | Cascade | " |
| `follows.follower_id` / `.following_id` | Cascade | Both directions |
| `social_connections.user_id` | Cascade | " |
| `profile_roles.user_id` | Cascade | " |
| `content_reports.reporter_id` | Cascade | Reports they filed are deleted, not retained |
| `catalog_moderators.user_id` | Cascade | " |
| `component_submissions.submitted_by` | Cascade | " |
| `saved_setup_categories.user_id` | Cascade | " |
| `notifications.recipient_id` / `.actor_id` | Cascade | Both directions; actor-direction rows removed from OTHER users' history too |
| `content_reports.reviewed_by` | `SET NULL` (anonymized) | Reports they reviewed survive, attribution removed |
| `feedback_submissions.user_id` | `SET NULL` (anonymized) | Existing Milestone 26 privacy design |
| `beta_invites.created_by` / `.used_by` | `SET NULL` | |
| `components.created_by` | `SET NULL` | |
| `catalog_moderators.granted_by` | `SET NULL` | |
| `component_submissions.moderator_id` | `SET NULL` | |
| `profile_roles.granted_by` | `SET NULL` | |
| `moderation_actions.actor_id` | Cascade — **audit/history, requires retention review** | The one CASCADE that destroys audit history; §10.4's second abort criterion exists specifically for this |
| `profiles.avatar_url` (legacy, no `avatar_path`) | Manual, verify-then-decide | Never auto-deleted — see §10.8 |

### 10.4 Abort / escalation criteria

Stop and do not proceed past this point if any of the following are true:

- **Staff-safety**: query 3a shows the target holds `'staff'`, **and** query 3b shows zero other verified staff accounts — escalate to §11.6 (grant a second staff account through the normal RPC first) rather than proceeding. If query 3a shows the target does **not** hold `'staff'`, this criterion does not apply at all, regardless of what 3b shows. Never bootstrap a replacement staff account or grant any role as part of resolving this criterion inline — §11's bootstrap procedure is separate, independently authorized, and run on its own, never folded into a deletion.
- Query 4 above is non-zero — get explicit adult-owner acknowledgment that this specific audit history will be destroyed (the schema offers no way to preserve it; `actor_id` cannot be null). Silent proceeding is never acceptable here.
- Any open `content_reports` or unresolved moderation/legal retention need touches this account (query 17) — resolve or explicitly document the retention decision first.
- Identity was not independently verified (§10.1), or approval did not come from an adult operator (§10.2).

**Audit-record durability**: the `account_deleted` row §10.6 inserts is attributed to the verified adult operator (`actor_id`), never the departing target — this holds by construction, since §10.6 always uses `<OPERATOR_USER_ID>`, never `<TARGET_USER_ID>`, for `actor_id`. If that operator's own account is ever later deleted through this same procedure, `moderation_actions.actor_id`'s existing `ON DELETE CASCADE` means every moderation action they ever authored — including this one — would be removed too. Query 4 above already exists to catch exactly this for that *future* deletion (an operator who has ever authored a moderation action is precisely what query 4 finds); this note only makes the connection explicit. No schema change is proposed or made here — this is a documentation-only observation.

### 10.5 Backup/PITR confirmation

Confirm a same-day backup/PITR recovery point exists (§13.1) before proceeding. This procedure is irreversible past commit (§10.11) — never run it without a fresh restore point on record.

### 10.6 Transaction boundaries and ordering

The SQL below is a single transaction. Everything in it either all commits or all rolls back — nothing here is meant to be run statement-by-statement outside a transaction.

```sql
begin;

-- Audit row first, inside this same transaction — rolls back with everything else if any later
-- step fails, so a rolled-back attempt never leaves a false "this happened" audit trail.
insert into public.moderation_actions (actor_id, action_type, target_type, target_id, note)
values (
  '<OPERATOR_USER_ID>',
  'account_deleted',
  'profile',
  '<TARGET_USER_ID>',
  'Manual account deletion per docs/OPERATIONS.md §10. Requested via <27B intake channel — placeholder>. Approved by <adult operator, placeholder>.'
);

-- Deletes builds owned by the account. Cascades automatically to build_revisions
-- (build_updates_project_id_fkey, ON DELETE CASCADE) and from there to revision_media
-- (revision_media_revision_id_fkey, ON DELETE CASCADE) — no separate delete needed for either.
delete from public.builds where user_id = '<TARGET_USER_ID>';

-- Safety net for query 6's possible divergence: build_revisions.user_id has its own foreign key
-- to auth.users (build_updates_user_id_fkey) with NO ON DELETE action specified — this is "the
-- blocking build_revisions.user_id relationship." Left non-null, it would raise a
-- foreign_key_violation and block step 10.8 outright for any revision not already removed above.
-- The column is nullable, so clearing it (not deleting the revision, which may belong to a build
-- this account doesn't own) is the correct, minimal action here.
update public.build_revisions set user_id = null where user_id = '<TARGET_USER_ID>';

-- profiles.id has NO foreign key to auth.users at all — nothing else in this schema deletes this
-- row automatically. This is the exact gap responsible for the one known historical orphan profile
-- documented in §10.12; skipping this step recreates that same condition for a new account.
delete from public.profiles where id = '<TARGET_USER_ID>';

-- Verification, inside the same transaction, before commit — abort criteria for step 10.6 itself.
select count(*) from public.builds where user_id = '<TARGET_USER_ID>';          -- expect 0
select count(*) from public.build_revisions where user_id = '<TARGET_USER_ID>'; -- expect 0
select count(*) from public.profiles where id = '<TARGET_USER_ID>';             -- expect 0

commit;
```

**If any verification query above returns non-zero: `rollback;`, not `commit;`.** Investigate before retrying — never re-run blind. If this step is interrupted before you know whether it committed, see §10.14 before doing anything else.

### 10.7 Supabase Auth admin deletion (requires Auth admin access, cannot run from SQL alone)

Only after 10.6 commits successfully. This step requires the Supabase Admin API (service-role authenticated) — never the publishable key this app ships to browsers, and not achievable through a plain SQL `delete from auth.users` in a way that correctly cleans up Auth's own internal state. The simplest correct path is the Supabase dashboard's own user-management "Delete user" action, which calls the same Admin API internally:

```
supabase.auth.admin.deleteUser('<TARGET_USER_ID>')
```

This cascades automatically (all confirmed via live `pg_constraint`, `ON DELETE CASCADE`): `project_drafts` (and from there `project_media`), `comments`, `likes`, `saved_builds`, `notifications` (both as recipient and — per query 14 above — as actor), `follows`, `social_connections`, `profile_roles`, `content_reports.reporter_id`, `catalog_moderators`, `component_submissions.submitted_by`, `saved_setup_categories`, plus Supabase Auth's own internal tables (`identities`, `sessions`, `mfa_factors`, etc.).

It sets to null rather than deleting: `content_reports.reviewed_by`, `feedback_submissions.user_id`, `beta_invites.created_by`/`used_by`, `components.created_by`, `catalog_moderators.granted_by`, `component_submissions.moderator_id`, `profile_roles.granted_by`. These are accepted, pre-existing schema behaviors — not something this procedure changes.

By the time this step runs, `build_revisions.user_id` no longer references the target (cleared in 10.6), so the one blocking foreign key is already resolved and this call should succeed without a `foreign_key_violation`. If this step fails, see §10.14 before doing anything else — do not re-run §10.6.

### 10.8 Storage cleanup (cannot be part of the PostgreSQL transaction)

Storage is not transactional with Postgres — this is necessarily a separate step, using the `storage_path` values captured in §10.3's read-only inventory (the underlying rows no longer exist to re-query by this point):

```
for each storage_path captured in §10.3:
  supabase.storage.from('project-images').remove([storage_path])
```

This is irreversible: no undelete, no trash/recycle bin. If interrupted partway, the result is orphaned Storage objects with no referencing row — low-severity, the same accepted-limitation category already documented for the `0005`/`0018` migrations, not a new gap introduced here. See §10.14 for what's safe to retry.

**Legacy avatar handling — never delete from a URL blindly.** For any `avatar_url` captured in §10.3's legacy-avatar query, only treat it as a Storage object to remove once **all three** of the following are positively verified:

1. The URL's origin/host matches this project's own Supabase Storage endpoint — not a Discord CDN URL, not any other unrelated external host.
2. The decoded path clearly and unambiguously falls under the `project-images` bucket — not another bucket, not a bucket-root path, not a `..`-containing or otherwise ambiguous path.
3. The resulting object key, once decoded and verified, corresponds to this specific target's own historical avatar location.

If any of the three can't be positively confirmed, **flag the row for manual review and take no automated action on it.** Never issue a broad prefix or wildcard delete against the bucket to "catch" an unverifiable legacy avatar — an unresolved legacy avatar is a low-severity, disclosed limitation (the same category as the accepted `0005`/`0018` orphaned-Storage-object gap), not a reason to risk deleting an object that may not belong to this account at all.

### 10.9 Post-operation verification

Re-run the applicable §10.3 queries; every count must be zero. This includes the legacy `avatar_url` query — if it still returns a row, confirm whether that row was positively verified and removed per §10.8, or was correctly flagged for manual review and deliberately left untouched; a flagged-but-unremoved legacy avatar is not a verification failure. Confirm the Auth user is gone via the Admin API (`getUserById` should return not-found) — a raw SQL read against `auth.users` for the same id should also return zero rows.

### 10.10 Requester notification

Notify the requester through whichever channel their request arrived on (§10.1), using language equivalent to the checklist below — never a blanket "everything was erased" claim, since this procedure intentionally retains some data:

- [ ] Your account and all published builds have been removed.
- [ ] Uploaded images and other Storage objects: removed — or, if any step is still pending, name what remains and give an expected completion window (§10.8).
- [ ] Feedback you submitted remains on record with your identity removed (anonymized), not deleted — this is an existing Milestone 26 design, not specific to your request.
- [ ] Reports you filed were deleted along with your account. If you ever reviewed reports as a moderator, those records remain on file with your identity removed.
- [ ] An internal audit record of this deletion exists for accountability and is retained under platform policy; it references your account but carries no other personal data.
- [ ] If anything above is not yet complete, state exactly what remains and when to expect it.

Never promise total erasure — several items above are retained by design, either anonymized or as an internal audit record, and this notification must say so accurately rather than overclaiming.

### 10.11 What's reversible, what's irreversible

- **Reversible up to `commit;`**: the entire §10.6 transaction — `rollback;` undoes it cleanly, and nothing outside Postgres has happened yet.
- **Irreversible once §10.6 commits**: the deleted `builds`/`build_revisions`/`profiles` rows. Recovery past this point means a PITR restore to disposable infrastructure (§13.2) and manual data recovery — not a rollback, and not something to attempt against the live project.
- **Irreversible and immediate**: §10.7's Auth admin `deleteUser()` call. Supabase has no "undelete" for an Auth user.
- **Irreversible and immediate**: §10.8's Storage object removal.

### 10.12 Known condition: one historical orphan profile (not caused by this milestone)

A read-only investigation performed before this PR found exactly one `profiles` row with no corresponding `auth.users` row. This is possible precisely because `profiles.id` has no foreign-key constraint to `auth.users(id)` — confirmed via `pg_constraint`: `profiles`' only constraints are its primary key and three `CHECK` constraints (`featured_build_id`, `headline`, `guidelines_accepted_version`, `building_since_year`); none reference `auth.users`. At the time of that investigation this row had zero references from any other table in the schema, and no identifying information about it appears anywhere in this document or this repository. It predates the changes released in PR #24 (27A PR2) and was not caused by it. **It is not touched, altered, or deleted by this PR.**

Recommended handling, not performed here: a separate, adult-approved cleanup under the same approval posture as §10.1-10.2 (re-confirm zero references at cleanup time, since state can drift, then delete the single row in its own transaction), plus a future migration adding the missing foreign key (`profiles.id references auth.users(id) on delete cascade`) so this class of drift becomes structurally impossible rather than requiring §10.6's manual `delete from public.profiles` step to be remembered every time.

### 10.13 UUID handling across this procedure

This resolves the tension between §10.3's "do not log or copy this output anywhere" and the fact that this procedure needs the same target identifier across §10.3 through §10.9.

- The verified target UUID (and the operator's own UUID used as `<OPERATOR_USER_ID>`) may be held only in the active operator's own session — memory, a local shell variable, or a single scratch file deleted the moment the case closes — for the duration of exactly one deletion case, and nowhere else.
- Never in this repository, in a commit, in chat or ticket text, in a screenshot, in analytics, in general application logs, or in persistent shell history.
- If an adult owner later establishes an approved, secure case-management system for handling deletion requests, follow that system's own retention rules instead of this note — this procedure does not invent record-keeping infrastructure and takes no position on what that future system should look like.
- Clear any temporary variable or scratch file holding the UUID as soon as §10.9 and §10.10 are complete.
- If access or the operator's session is lost mid-procedure and no securely retained copy exists, **do not** reconstruct the UUID from an untrusted source (a chat log, a screenshot, memory of it) — re-verify identity from scratch per §10.1 before resuming, exactly as if this were a new request. See §10.14 first, to determine what already happened before you re-verify.

`<TARGET_USER_ID>` and `<OPERATOR_USER_ID>` remain placeholders throughout this document; no real UUID appears anywhere in this repository.

### 10.14 Interrupted runs: determining state and safe retry

Never rerun this procedure from §10.1 blindly after an interruption. Determine exactly what already happened using the read-only checks below, then resume only at the first step that hasn't completed — never repeat a step that already has.

**How to tell what already happened (read-only, in this order):**

1. `select count(*) from public.moderation_actions where target_id = '<TARGET_USER_ID>' and action_type = 'account_deleted';` — `1` means §10.6 already committed. Because the audit insert is the first statement inside §10.6's single transaction, this being `1` is proof the builds/build_revisions/profiles deletes committed too — they cannot have succeeded without it, or vice versa. `0` means §10.6 has not committed, whether or not it was attempted (a failed attempt leaves nothing behind — see below).
2. If step 1 is `1`: check the Auth user via the Admin API (`getUserById('<TARGET_USER_ID>')`). Found → §10.7 hasn't succeeded yet. Not found → §10.7 already succeeded.
3. If step 2 shows §10.7 already succeeded: spot-check one of the `storage_path` values captured in §10.3 against the Storage API. Still present → §10.8 hasn't completed. Not found → check the rest of the captured list the same way before assuming §10.8 is fully done.

**Boundary-by-boundary guidance:**

- **§10.6 fails before `commit;`** — safe, no special handling needed. A failed statement aborts the whole transaction automatically; nothing was written, including no audit row (it's the first statement, so it can't survive a later failure). Re-run §10.3's dry-run fresh before retrying §10.6 — whatever caused the failure may need investigating, and production state can drift between reads.
- **§10.6 commits but §10.7 fails** — confirm via steps 1–2 above that §10.6 truly committed and the Auth user still exists. If so, retrying `deleteUser()` is safe and idempotent for a still-existing id. **Do not re-run any part of §10.6** — the audit row already exists, and inserting it again would create a duplicate `account_deleted` record for the same target.
- **§10.7 succeeds but §10.8 hasn't started** — use the `storage_path` list captured during §10.3, while it's still held in the active session (§10.13). If that list was lost after §10.6/§10.7 already ran, it cannot be re-derived from Postgres — the referencing rows are gone. Do not attempt a blind bucket-wide or prefix-wildcard cleanup in that case; escalate to an adult owner to decide whether a targeted, manually-verified Storage listing is worth attempting, accepting that some objects may remain as low-severity orphans (§10.8).
- **§10.8 partially succeeds** — safe to retry. Removing an already-removed Storage object is a harmless no-op/not-found response, not an error requiring special handling. Re-run `remove()` against the remaining paths from the captured list.
- **Operator access or session lost between any of the above** — use the three-step check above to determine exactly what already happened before doing anything else. Resume only at the first not-yet-completed step. Never restart from §10.1's intake, and never re-run §10.6 once its audit row is confirmed present.

**When to stop and escalate rather than retry**: if the read-only checks above produce a result that doesn't fit any of the boundary cases described — for example, the audit row exists but the Auth admin API keeps erroring in a way that isn't explained by a still-existing user id — stop, do not keep retrying, and escalate to an adult owner rather than improvising a workaround.

## 11. Moderator/staff bootstrap (first-staff account, one-time — not yet authorized)

**No bootstrap has occurred.** This section documents the procedure only. It requires separate, explicit authorization from an adult owner before any SQL below is run against production. No account identifier, real UUID, username, or email appears anywhere in this section or elsewhere in this repository.

### 11.1 Why `grant_profile_role()` cannot create the first staff account

Confirmed by direct read of `pg_get_functiondef('public.grant_profile_role')` against production (2026-08-15). The live function body enforces two independent guards:

1. Granting `'moderator'` or `'staff'` requires `is_platform_staff(auth.uid())` to already be true for the calling session. Before any staff account exists, no session can ever satisfy this — the call always raises `'Only staff can grant the % role.'`.
2. Independent of the above, the function unconditionally rejects `p_user_id = auth.uid()` (`'You cannot grant yourself a role.'`) — so even a hypothetical account that somehow passed check 1 still could not grant the role to itself.

Both checks are inside the function body, not just RLS — there is no calling sequence through this RPC that produces a first staff account. That is why this is a manual, SQL-level, one-time exception rather than a code change.

### 11.2 Prerequisite: adult-owner self-verification

An adult owner must identify and verify their own existing Specbound account before this procedure runs — the bootstrap target is that verified account, not a new one created for the purpose. No account identifier belongs in this repository, in commit messages, or in this document; the operator holds it privately while substituting `<TARGET_USER_ID>` at execution time.

### 11.3 Pre-flight checks (read-only)

```sql
-- confirm the target account exists
select id, created_at from auth.users where id = '<TARGET_USER_ID>';

-- confirm the target has no existing role rows for 'staff'
select role from public.profile_roles where user_id = '<TARGET_USER_ID>';

-- abort condition: confirm no staff account already exists unexpectedly
select count(*) as existing_staff from public.profile_roles where role = 'staff';
```

**Abort if**: the target account doesn't exist; the operator isn't fully certain which account is theirs (ambiguous target); the target already holds `'staff'`; or `existing_staff` is non-zero — this procedure is for the *first* staff account only. If a staff account already exists, use the normal `grant_profile_role()` RPC instead, once a real staff session can call it.

### 11.4 The bootstrap transaction

```sql
begin;

insert into public.profile_roles (user_id, role, granted_by, note)
values (
  '<TARGET_USER_ID>',
  'staff',
  null,
  'One-time bootstrap of the first staff account. Not granted via grant_profile_role() — that RPC requires an existing staff caller and separately blocks self-grants (see docs/OPERATIONS.md §11.1), so no session could ever have performed this grant through the app. Performed directly via SQL by the verified adult account owner.'
);

-- moderation_actions.actor_id is NOT NULL (FK to auth.users, ON DELETE CASCADE) — a true null-actor
-- audit row is not schema-compatible. actor_id is set to the target's own id: the granter and the
-- grantee are the same verified adult owner acting directly via SQL, not through the self-grant-
-- blocking RPC, so this is the honest value, not a workaround standing in for something else.
insert into public.moderation_actions (actor_id, action_type, target_type, target_id, note)
values (
  '<TARGET_USER_ID>',
  'role_granted',
  'profile',
  '<TARGET_USER_ID>',
  'Bootstrap grant of the first staff role, performed directly via SQL, not through grant_profile_role(). See docs/OPERATIONS.md §11.'
);

-- verification, inside the same transaction
select role, granted_by, note from public.profile_roles where user_id = '<TARGET_USER_ID>' and role = 'staff'; -- expect exactly 1 row
select count(*) from public.profile_roles where role = 'staff'; -- expect exactly 1

commit;
```

**If either verification query doesn't match exactly: `rollback;`, not `commit;`.**

### 11.5 Rollback

If this needs to be undone before anything else has happened (e.g. the wrong account was targeted):

```sql
delete from public.profile_roles
where user_id = '<TARGET_USER_ID>' and role = 'staff' and granted_by is null;
```

The `granted_by is null` clause is a deliberate safety guard — it ensures this can only ever match the single bootstrap-created row, never a real, RPC-granted staff row (which always has a non-null `granted_by`). The corresponding `moderation_actions` row is left in place regardless — this schema never deletes audit rows (matching every migration's rollback convention in `supabase/migrations.md`); an incorrect grant followed by a correction is itself worth an honest, permanent audit trail, not a deletion.

### 11.6 Recommended next step: a second trusted adult backup

Immediately after a successful bootstrap, the new staff account should grant `'staff'` to a second, independently verified adult through the *normal* path (`grant_profile_role()`, now callable since a real staff session exists) — so no single account is ever a single point of failure for platform moderation again. This is a recommendation, not something this procedure enforces.

### 11.7 Authorization status

No bootstrap has occurred, and none will occur as part of this PR. This section documents the procedure only, pending separate, explicit authorization from an adult owner.

## 12. Deployment and incident runbook

Each entry below follows the same shape: read-only checks first, when to abort/escalate, what requires an adult owner directly, what an authorized Claude session may perform, and what must never be improvised.

### 12.1 Routine deployment verification

- **Read-only first**: after any push to `main`, confirm the Cloudflare Pages dashboard shows the new deployment as current; run the smoke-test subset (`docs/DEPLOYMENT.md` §12) against the live URL — sign-in flow, one public page, `_headers` response headers, `robots.txt`/`sitemap.xml` reachability.
- **Abort/escalate**: any smoke check fails → the release is not complete; proceed to §12.2 rather than leaving production unverified.
- **Adult-owner only**: none — routine, read-only.
- **Claude may perform after authorization**: the checks themselves and reporting results.
- **Never improvise**: don't skip the smoke test because the diff looked small — the header regression this project already shipped once (fixed in PR3's follow-up) is the standing reason this isn't optional.

### 12.2 Frontend-only rollback

- **Read-only first**: identify the last known-good deployment in Cloudflare's Deployments list; check `git log` for what changed since it, so the rollback's scope is understood before acting.
- **Abort/escalate**: if a database change might be the actual cause, don't rely on a frontend rollback alone — see §12.13's decision framework first.
- **Adult-owner only**: authorizing the rollback action.
- **Claude may perform after authorization**: promoting the prior deployment in the Cloudflare dashboard (`docs/DEPLOYMENT.md` §13), then re-running §12.1.
- **Never improvise**: never force-push or rewrite `main`'s history as a substitute for the dashboard rollback — that changes what the next real push deploys from and can reintroduce the exact code just rolled back.

### 12.3 Migrate-first database releases

- **Read-only first**: `supabase migration list --linked` (or `db push --linked --dry-run`) to confirm exactly what's pending; re-read the migration and its paired rollback file in full immediately before running it, even if reviewed earlier — production state can drift (see `0020`'s production-compatibility rewrite, discovered by a real `db push` that stopped safely at exactly that migration).
- **Abort/escalate**: any unexpected dry-run result (a migration showing partially applied, an out-of-order gap) → stop and investigate before pushing.
- **Adult-owner only**: authorizing the production migration apply.
- **Claude may perform after authorization**: `supabase db push --linked --yes` for the confirmed, reviewed, pending migration(s) only — never a broader flag; then the corresponding frontend deploy, migration-first, matching every release so far (PR #24/#25 both applied migrations before merging the frontend change).
- **Never improvise**: never apply a migration that hasn't been rehearsed against local disposable Docker first (apply → verify → rollback → reapply); never skip the paired rollback file.

### 12.4 Migration failure and partial-application response

- **Read-only first**: `supabase migration list --linked` immediately to see which migration(s) the failure left in an unclear state; read the actual Postgres error rather than assuming what failed.
- **Abort/escalate**: any partial-application state → stop, do not attempt an automatic fix. This project's migrations are written to fail atomically where possible; a partial failure means something didn't behave as designed and needs a human read of the real error first.
- **Adult-owner only**: authorizing any corrective SQL against production outside the normal migration-file process.
- **Claude may perform after authorization**: reading the error, proposing a fix as a new, higher-numbered migration file (never editing the failed file in place — this project's absolute convention) — applied only after adult-owner review.
- **Never improvise**: never patch the affected table/function directly in the Supabase dashboard SQL editor as a "quick fix" — that's exactly the untracked-change problem `0017`'s audit had to clean up after the fact.

### 12.5 Authentication incidents

- **Read-only first**: reproduce against production directly; determine whether the failure is Supabase Auth itself (check status.supabase.com), a bug in this app's own code (the exact class the earlier signed-out-redirect hotfix fixed), or a third-party OAuth provider (Discord) outage.
- **Abort/escalate**: if Supabase Auth itself is degraded, there is nothing to fix on the Specbound side — wait and communicate, not a code change.
- **Adult-owner only**: any change to Auth admin settings (email templates, redirect URL allowlist) in the Supabase dashboard.
- **Claude may perform after authorization**: diagnosing and shipping a code fix through the normal release path (§3/§12.1), as done for the earlier login-redirect hotfix.
- **Never improvise**: never disable RLS, widen an Auth redirect allowlist, or grant a broader OAuth scope "to see if that fixes it."

### 12.6 Unusual signup spikes

- **Read-only first**: check `auth.users` growth via the Supabase dashboard's Auth user list/count — organic, bot/abuse pattern, or a bug (e.g. a retry loop double-submitting signups)?
- **Abort/escalate**: public signup is currently **held** pending 27B's Terms of Service/Privacy Policy — any signup spike at all before that gate lifts is itself an anomaly worth immediate escalation, since it shouldn't be possible in normal operation today.
- **Adult-owner only**: any decision to throttle, disable signup, or ban accounts.
- **Claude may perform after authorization**: read-only investigation and reporting; implementing an approved, specific mitigation as a normal code/config change.
- **Never improvise**: never narrow RLS/policies as an improvised anti-abuse measure; never delete suspected-bot accounts without the same adult-operator approval §10 requires for any account deletion.

### 12.7 Upload/Storage abuse

- **Read-only first**: identify the abusive object(s)/account via the Storage dashboard or a read-only query against `storage.objects`/`project_media`/`revision_media`; confirm which bucket/policy is implicated.
- **Abort/escalate**: if the abuse indicates a genuine RLS/policy gap (not just a bad actor using the app as intended), treat as a security issue (§8 item 4) — scoped migration + rollback, not a live dashboard patch.
- **Adult-owner only**: deleting another user's uploaded content; any Storage bucket/policy configuration change (§14).
- **Claude may perform after authorization**: read-only investigation; removing a specific, confirmed-abusive object via the Storage API once authorized; drafting a hardening migration if a policy gap is found.
- **Never improvise**: never flip the `project-images` bucket's public/private flag or alter its MIME/size limits as an improvised response — that's §14's own pre-planned, adult-owner-gated change, not an incident-response shortcut.

### 12.8 Moderation access loss

- **Read-only first**: `select role, user_id from public.profile_roles where role in ('moderator','staff')` (dashboard SQL editor, read-only) to see who currently holds access.
- **Abort/escalate**: if zero staff accounts remain reachable, this is the bootstrap scenario again (§11), not a normal role-grant — the same chicken-and-egg problem applies, since `grant_profile_role()` needs an existing staff caller.
- **Adult-owner only**: any role grant/revoke, and any emergency SQL-level bootstrap.
- **Claude may perform after authorization**: the read-only check; running an authorized role-grant/bootstrap exactly per §11.
- **Never improvise**: never grant a role to an unverified account "to restore access quickly" — §11.2-style identity verification still applies under time pressure.

### 12.9 Account-deletion requests

Fully covered by §10 — this entry is an index pointer, not a duplicate. Read-only checks first (§10.3), abort/escalation criteria (§10.4), adult-owner-only steps (approval, the transaction, Auth admin deletion), UUID handling (§10.13), interrupted-run recovery (§10.14), and the explicit statement that self-service deletion doesn't exist are all defined there.

### 12.10 Cloudflare deployment mismatch

- **Read-only first**: compare response headers/`ETag` between `specboundapp.com` and `specbound.pages.dev` for the same path (matches the custom-domain smoke check already performed after PR #24's release) — a mismatch usually means the custom domain is pointed at a different (often stale) deployment or a caching layer is serving old content.
- **Abort/escalate**: if the two never converge after a cache purge (§4) and a hard refresh, escalate — likely a Cloudflare Pages custom-domain configuration issue, not an application bug.
- **Adult-owner only**: any Cloudflare DNS/Pages custom-domain configuration change.
- **Claude may perform after authorization**: the read-only comparison; a cache purge (§4) if that's the confirmed cause.
- **Never improvise**: never change DNS records or the Pages custom-domain binding without adult-owner authorization.

### 12.11 Security-header regressions

- **Read-only first**: `tools/ci/check-security-headers.js` (already gates every PR since PR3) plus a direct header check against production; compare against `docs/DEPLOYMENT.md` §10.
- **Abort/escalate**: any missing/weakened security header on `main` after a deploy — treat as a shipped bug, not a cosmetic issue, exactly the regression class this check exists to prevent.
- **Adult-owner only**: none beyond the standing deploy-authorization gate — a header fix is a normal `_headers` change.
- **Claude may perform after authorization**: diagnosing and fixing `_headers`, verifying with the CI check plus a live production header check, shipping through the normal release path.
- **Never improvise**: never loosen `check-security-headers.js`'s assertions to make a deploy pass instead of fixing the actual regression.

### 12.12 HSTS staged rollout and rollback limitations

- **Read-only first**: confirm the currently-live `Strict-Transport-Security` value against both production hostnames — as of this PR, Stage 1 (`max-age=300`, no `includeSubDomains`, no `preload`) is the only stage ever deployed (`docs/DEPLOYMENT.md` §6/§14).
- **The core limitation**: HSTS is asymmetric. Browsers that already received a longer `max-age`, `includeSubDomains`, or a `preload`-listed entry cannot be told to stop enforcing HTTPS early by a later, weaker header — a "rollback" can only lower future `max-age` going forward, never retroactively un-pin a browser that already cached a stronger policy. This is why staging (Stage 1 → 2 → 3 → `preload`) is deliberate and effectively one-directional, and why advancing past Stage 1 needs its own dedicated review, not a routine header tweak.
- **Adult-owner only**: advancing to any later HSTS stage, and definitely `preload`-list submission (functionally irreversible for months — removal from Chromium's preload list is itself a slow, manual process).
- **Claude may perform after authorization**: the read-only header check; a `_headers` change only for an explicitly authorized stage transition, never a silent widening.
- **Never improvise**: never add `includeSubDomains`/`preload`, or raise `max-age` past what's explicitly authorized, "since it seems stable now" — the asymmetry above is exactly why every advance requires deliberate, separate sign-off.

### 12.13 Deciding between a frontend revert, a database rollback, or a forward fix

- **Frontend-only bug, database unaffected** → frontend rollback (§12.2). Fastest, fully reversible, no data risk.
- **Database migration is the root cause and nothing has read/written through the new shape yet** → database rollback via the migration's paired rollback file (rehearsed locally first, §12.3), then a frontend rollback if the frontend already assumed the new shape.
- **Database migration is the root cause but real data now depends on the new shape** (a new column has real values, a widened `CHECK` constraint has real rows using the new value) → check the migration's own rollback file first: this project's convention (see `0037`/`0039`/`0041`) is to make such rollbacks deliberately narrow or a no-op *specifically because* reversing them would destroy real data. The only safe path in that case is a **forward fix** — a new migration correcting the behavior — never forcing a destructive rollback for the appeal of "undo."
- **Genuinely unsure which layer is at fault** → reproduce against production first, roll back the frontend immediately if a deploy is the plausible trigger (cheap, reversible, buys time), then investigate the database layer calmly with the site already stable — matches this project's existing "roll back first, diagnose second" posture (§2, §8 item 2).
- In every case: never combine a frontend revert with an ad hoc database patch as one improvised action — pick a path above, execute it, verify (§12.1), then decide on next steps.

## 13. Backups and monitoring (adult-owner checklist)

### 13.1 Backup/PITR confirmation

- Confirm the Supabase project's current plan tier and point-in-time-recovery retention window (Supabase dashboard → Project Settings → Database/Add-ons, or the Backups panel) — tracked as **L4** in the original launch audit, and already listed in §9's maintenance table.
- Record only the confirmation date and retention window (e.g. "Confirmed 2026-MM-DD: PITR available, N-day retention") — never publish the project ref, billing details, or any other account-identifying detail in this repository.
- This confirmation is a prerequisite for §10's account-deletion procedure — do not run that procedure without a current confirmation on record.

### 13.2 Restoration rehearsal

- Periodically (recommended: once per major schema-changing milestone, not a fixed calendar) rehearse an actual PITR restore — **only ever against disposable infrastructure** (a throwaway Supabase project or local Docker), never over the live production project.
- Document the rehearsal outcome (worked / didn't / lessons) without including any real user data recovered during the test.

### 13.3 Error-monitoring provider (not selected in this PR)

- §7 already documents a working, unimplemented design (`client_errors` table, INSERT-only RLS, global error handler) — reused here, not duplicated. A future third-party provider remains an option per §7's own "not ruled out permanently" note, to be selected later.
- **Do not select, sign up for, or configure any provider in this PR.** No DSN, API key, or project identifier — real or placeholder-that-looks-real — belongs in this repository until a provider is actually chosen and authorized.
- **Required approval**: creating an external monitoring account, or adding any DSN/webhook/API key to the codebase or Cloudflare Pages environment variables, requires explicit adult-owner authorization first.

### 13.4 Mandatory redaction

Whichever monitoring approach is eventually live — the `client_errors` table today, or a future provider — the following must never appear unredacted in any error report, log line, or dashboard this project controls: auth tokens, session identifiers, refresh tokens; email addresses or usernames tied to real accounts; feedback submission bodies, moderation report content, comments, build descriptions, or any other user-generated free text. Only an error message, stack trace, URL, and coarse context (signed-in vs signed-out) belong in a report — matching §7's existing "deliberately excluded" list. This constraint applies to any future provider integration, not just the current design — evaluate a candidate's data-scrubbing configuration as part of choosing it, not after.

## 14. Storage configuration checklist (`project-images` bucket — approved, not performed)

**Status: documented, not performed.** Requires adult-owner action in the Supabase Dashboard or Management API — out of scope for this PR, which does not alter the Dashboard or Management API in any way.

Approved change: bucket `project-images`, allowed MIME type `image/jpeg` only, file-size limit 10 MB. Existing RLS policies (`docs/STORAGE_ARCHITECTURE.md`, `0017`) remain unchanged — this is a bucket-level constraint, not a policy change. These limits affect new uploads only; existing objects already in the bucket are unaffected and remain accessible exactly as before.

### 14.1 Pre-change inventory (read-only)

- Note the bucket's current MIME-type/size configuration (or lack thereof) via the Supabase dashboard, for later comparison.
- Spot-check a sample of existing objects' content-types — confirms the "existing objects unaffected" assumption holds for what's actually in the bucket today, not just in theory.

### 14.2 The change itself

Set allowed MIME types to `image/jpeg` and the file-size limit to 10 MB, via Supabase Dashboard → Storage → `project-images` → bucket settings. **Claude must not perform this step or any Supabase Dashboard/Management API action for it** — it is an account/infrastructure settings change, reserved for the adult owner.

### 14.3 Post-change tests

Run all five, in a disposable/test account where practical:

1. A valid `image/jpeg` upload through the normal editor UI succeeds.
2. An invalid MIME type (e.g. `.png`, `.webp`) is rejected with a clear error, not a silent failure.
3. An oversized file (>10 MB) is rejected.
4. Cross-owner access remains rejected exactly as before — confirms the bucket-level limit and RLS are independent layers, neither weakening the other.
5. An existing (pre-change) file already in the bucket is still readable/servable exactly as before.

### 14.4 Rollback

Clear the two bucket settings (MIME-type allowlist, size limit) back to unset/default. No data is destroyed by either direction — this is a validation-layer setting, not a schema or content change.

## Related documentation

- `docs/DEPLOYMENT.md` — initial setup, architecture, and the full rollback/verification procedures §2 and §12.1-12.2 summarize.
- `docs/STORAGE_ARCHITECTURE.md` — the RLS model §14 leaves unchanged.
- `docs/AUTH_ARCHITECTURE.md` — background for §12.5's authentication-incident checks.
- `supabase/migrations.md` — the authoritative migration log referenced throughout §10-§12.
- `docs/ROADMAP.md` — current milestone status, including what remains before public signup (§12.6) can open.
