# Operations

**Status: current and accurate as of Phase 9D implementation, 2026-07-27.** Companion to `docs/DEPLOYMENT.md` (initial setup) — this document covers the ongoing day-to-day of running Specbound in production: redeploying, rolling back, releasing changes, rotating credentials, updating dependencies, and what to do when something breaks.

---

## 1. Redeployment

Nothing special — push to the production branch. Cloudflare Pages auto-builds and auto-deploys on every push (see `docs/DEPLOYMENT.md` §2). There is no separate "trigger a redeploy" step for a normal code change; the deploy *is* the push.

To force a redeploy with no code change (e.g. after a Cloudflare-side issue, or to pick up a dashboard setting change that needs a fresh build): Cloudflare dashboard → Pages project → **Deployments** → **Retry deployment** on the latest one, or push an empty commit (`git commit --allow-empty -m "Trigger redeploy"`).

## 2. Rollback

Full procedure in `docs/DEPLOYMENT.md` §7. Summary: Cloudflare dashboard → Deployments → pick the last known-good one → promote it to production. Immediate, no rebuild, no git operation needed. Use this the moment a deploy is suspected bad — don't wait to diagnose the root cause first; roll back, then investigate calmly with the site already stable.

## 3. Releasing updates

This is a solo/small-scale project today (single `master` branch, no staging environment — see `docs/MILESTONE_9_PHASE_9D_ARCHITECTURE.md` §1.5 for why a dedicated staging branch isn't recommended). The release flow:

1. Make the change locally, verify it against the local dev server (`.claude/nocache_server.py` on port 8431) as this project has done throughout Milestones 1-9.
2. Commit with a clear message describing *why*, not just *what* (matches this project's established commit convention — see recent commits for examples).
3. Push to the production branch. This *is* the release — no separate "deploy step" or "release cut" process exists or is needed for a project this size.
4. Run the relevant subset of the smoke-test checklist (`docs/DEPLOYMENT.md` §9) against the live production URL after the deploy completes.
5. For anything touching Storage, RLS, or auth specifically: don't skip the smoke test. This app's history (Migrations A/B/C) shows exactly how subtle and high-consequence a mistake in that area can be — see `docs/STORAGE_ARCHITECTURE.md` and `docs/AUTH_ARCHITECTURE.md`.

**Database migrations are a separate, manual process**, unrelated to Cloudflare Pages deploys: this project has no automated migration runner. New migrations go in `supabase/migrations/` (sequential, zero-padded, with a matching `_rollback.sql`, logged in `supabase/migrations.md`) and are run manually in the Supabase SQL editor — the implementation environment has never had direct database execution access, by design. A Cloudflare Pages deploy never touches the database; a migration never touches the deployed site. Keep these two release paths mentally separate.

## 4. Cache invalidation

Automatic on every Cloudflare Pages deploy — see `docs/DEPLOYMENT.md` §8 for the full reasoning (and why this app deliberately does *not* set custom long-lived cache headers). Nothing to do here in normal operation. If a stale-asset issue is ever suspected: Cloudflare dashboard → Caching → **Purge Cache**, as a manual fallback.

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

## 7. Incident response basics

This app has **no error-tracking/monitoring service** configured (Sentry or equivalent) — a real, disclosed gap, tracked as **L10** in the original Milestone 9 audit and deferred to Phase 9E's launch checklist, not fixed here. Until that's addressed, production errors are only visible to whichever single user hits them, in their own browser console — there is no way to be automatically notified of a client-side error today.

Given that constraint, incident response for this app is necessarily more manual:

1. **If a user reports something broken**: reproduce it yourself against production first (not the dev server) — open the browser console, check `read_network_requests`-equivalent (or your browser's Network tab) for failed requests, check for CSP violations if the symptom looks resource-related.
2. **If a deploy is the suspected cause**: roll back immediately (§2) before diagnosing — don't leave production broken while investigating.
3. **If Supabase itself is down or degraded**: check [Supabase's status page](https://status.supabase.com) — this app has no fallback/offline mode, since every real feature (auth, data, storage) depends on Supabase being reachable. Nothing to do on the Specbound side except wait and communicate, unless the outage reveals a specific bug in this app's own error handling (e.g. an unhandled rejection instead of a graceful toast) — that would become a normal bug fix + release (§3).
4. **If a security issue is discovered** (e.g. an RLS gap like the ones found and fixed in Migrations A/B/C): treat with the same rigor this project already established — audit live via the anon key first, design a scoped migration with a rollback file, verify anonymous/owner/cross-user behavior explicitly before and after, document in `supabase/migrations.md`. Do not patch RLS live in the Supabase dashboard without a corresponding tracked migration file — that's exactly the untracked-policy problem Migration A (`0017_storage_rls_hardening.sql`) had to clean up.
5. **If credentials need emergency rotation**: see §5. Given the only client-side credential is a publishable key with no meaningful "compromise" blast radius (RLS is the real boundary), this is a low-urgency scenario in this app's current architecture.

## 8. Production maintenance

Recurring things worth checking periodically, not because anything is currently wrong, but because they're easy to forget on a project with no automated reminders:

| Item | Frequency | What to check |
|---|---|---|
| Supabase CDN pin (§6) | Occasionally | Is a newer Supabase JS client version available? Worth the upgrade? |
| Supabase backup/PITR tier | Once, then rarely | Confirm the project's plan tier still matches actual data-loss tolerance (tracked as **L4** in the original audit, part of Phase 9E) |
| SMTP/email provider | Once, before real signup volume | Supabase's default email service has strict rate limits — confirm custom SMTP is configured before relying on password-reset/signup emails at any scale (tracked as **L9**) |
| Domain/SSL | Rarely (Cloudflare auto-renews) | Spot-check the site is still serving over valid HTTPS |
| `robots.txt`/`sitemap.xml` accuracy | When new public pages are added | New static pages (e.g. a new category) should be added to `sitemap.xml`; new private/account pages should be added to `robots.txt`'s disallow list, matching the pattern in `docs/DEPLOYMENT.md` §3 |
| Dead code / duplication | Periodically | Phase 9C found real recurrence of "imported but fully dead" CSS and duplicated utilities even after an earlier (8D) cleanup pass — worth an occasional fresh audit rather than assuming one cleanup pass is permanent |
| CSP footprint | Whenever a new external resource is added | Any new external script/font/API host must be added to `_headers`' CSP *before* the code that uses it ships, or it will be silently blocked in production (verify via the same meta-tag/temporary-header technique used during Phase 9D implementation — see `docs/DEPLOYMENT.md` §9.8) |
