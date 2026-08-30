# Deployment

This is Specbound's current production deployment and operations guide — how the site is hosted, how a change reaches production, and what to check before and after a deploy. It reflects the live site, not a milestone-in-progress snapshot.

---

## 1. Purpose and current production state

- **Production URL:** https://specboundapp.com
- **Production branch:** `main`
- **Hosting:** Cloudflare Pages, deploying directly from this GitHub repository
- **Architecture:** static HTML/CSS/JavaScript — no framework, no bundler, no transpilation. `build.sh` (§2, §3) assembles the deployment artifact by copying an approved allowlist of files into `dist/`; it is not an application build step.

The site is live, HTTPS is active, and Cloudflare preview deployments on pull requests have been observed working. Supabase Auth's Site URL, Redirect URLs, and Discord provider are configured for this domain, and the Discord account-linking flow has been manually verified end-to-end in production (see §9). This document does not claim every operational item below is finished — §14 lists what's genuinely still open.

---

## 2. Architecture and hosting model

Cloudflare Pages serves the static files from its configured output directory without transforming them. **`dist/` is that output directory** — a generated, gitignored artifact assembled fresh on every build by `build.sh`, a tracked, POSIX-compatible script at the repository root that copies an explicit *allowlist* of public runtime files and directories into `dist/` and nothing else (§3, §5). This is a default-deny model: any repository content not named in `build.sh`'s allowlist — including anything added to the repository later — is structurally absent from every deployment, not merely hidden by a separate exclusion step. A Cloudflare WAF rule (§3) remains as a second, independent layer of defense. `tools/ci/package.json` exists only for CI's own tooling (Playwright, for the browser test suite) and is deliberately kept out of the repository root so Cloudflare Pages' root-directory build detection never sees it; see `docs/CI.md`.

Supabase provides everything server-side: Auth (including Discord's native OAuth identity-linking), the PostgreSQL database, Storage for images, RPC functions, and Row Level Security as the access-control layer on every table. The frontend talks to Supabase directly from the browser using a publishable client key — see §7.

---

## 3. Cloudflare Pages configuration

**As of the deployment-surface hardening change (chore/deployment-surface-hardening), the values below are what must be set in the Cloudflare dashboard once that PR merges — they are not yet live; see the migration sequence at the end of this section.**

| Setting | Value |
|---|---|
| Framework preset | None |
| Build command | `sh build.sh` |
| Build output directory | `dist` |
| Root directory | `/` (repository root — unchanged) |
| Production branch | `main` |

`build.sh` (tracked at the repository root) copies an explicit allowlist of public runtime files and directories into a fresh `dist/` directory on every build — see §5 for the exact list. Nothing outside that allowlist is ever copied, so `tests/`, `tools/`, `.github/`, `.claude/`, `supabase/`, `docs/`, `README.md`, `build.sh` itself, and any future top-level entry are all structurally absent from `dist/` regardless of whether anyone remembers to update an exclusion list. This replaces the previous `rm -rf tests tools .github .claude` build command, which pruned four specific directories from an otherwise-published repository root — an exclusion-list (default-allow) model that this allowlist (default-deny) model supersedes.

A Cloudflare WAF custom rule, **"Block developer and CI paths,"** additionally blocks requests to the `tests/`, `tools/`, `.github/`, and `.claude/` path prefixes at the edge — kept in place as a second, independent layer of defense even though `dist/` can no longer contain those paths at all. This protects against legacy Pages assets that may remain distributed temporarily (for example, cached at a specific edge location from a deployment made before this change), and guards against a future regression in `build.sh` itself.

`tools/ci/check-deploy-artifact.js` (run in CI on every push and pull request, §12) is the automated, version-controlled proof that `dist/` contains exactly the approved allowlist and nothing else — see that section for what it checks.

`design-system.html` remains in the allowlist and is published — it's harmless (an unlinked internal style-guide page) and is already covered by `robots.txt`'s disallow list (§11).

**Migration sequence** (repository change and dashboard change are two parts of one coordinated rollout — see §13 for why they must be rolled back together, not independently):

1. `chore/deployment-surface-hardening` merges to `main` — this alone changes nothing in production yet; Cloudflare continues using its prior dashboard build command/output directory until step 2.
2. A repository owner updates the Cloudflare Pages dashboard: Build command → `sh build.sh`, Build output directory → `dist` (both values above). This triggers a new production deployment.
3. Run the production verification checklist in §12 against the new deployment immediately.
4. If anything breaks, use the dashboard **Rollback to this deployment** action (§13) to restore the last-known-good deployment while `build.sh`'s allowlist is corrected in a follow-up commit — do not revert only the dashboard settings or only the repository change in isolation.

---

## 4. Branch, deployment, and preview flow

- **Production branch:** `main`. A push to `main` triggers an automatic Cloudflare Pages build and deploy — no manual "deploy" step exists or is needed.
- **Preview deployments:** other branches and pull requests receive their own automatically-generated preview URL. This has been observed working in this repository. Use a preview deployment to sanity-check a change — especially anything touching Storage or auth — before it reaches production.
- Both the initial GitHub repository connection and the initial Cloudflare Pages project connection have already been completed; this document doesn't re-describe them as pending setup.

---

## 5. Published and excluded content

**Published (the exact `build.sh` allowlist — top-level entries in `dist/`):** `index.html`, `404.html`, `design-system.html`, `_headers`, `robots.txt`, `sitemap.xml`, `manifest.webmanifest`, `pages/`, `css/`, `js/`, `assets/`. `tools/ci/check-deploy-artifact.js` asserts this is the *exact* top-level set on every CI run — nothing missing, nothing extra.

**Excluded from the deployed artifact, available via the public GitHub repository instead:**

- `supabase/**` — the SQL migration/rollback/test source (schema, `SECURITY DEFINER` function bodies, RLS policies, rollback scripts). Not executable by a static host, and publishing it never granted any database access on its own — the live database is reachable only through Supabase's own API surface, governed by RLS, entirely independent of whether its schema source is readable. It was previously served directly from `specboundapp.com`; a Launch Readiness Audit flagged unrestricted production-domain exposure of full schema/function source as unnecessary attack surface for automated reconnaissance, even though the content itself carries no secrets and duplicates what the (public) GitHub repository already exposes. It remains readable at `github.com/Fan1dude/Specbound/tree/main/supabase` — this change only removes it from `specboundapp.com` specifically.
- `docs/**` — this operations/architecture documentation itself, including internal runbooks. Same reasoning: not secret, not previously addressed one way or the other in this document, removed from the production domain as part of the same hardening pass.
- `tests/` (the browser-based regression suite), `.claude/` (local dev tooling), `tools/` (CI scripts and CI-only `package.json`), `.github/` (the CI workflow definition) — as before, now excluded structurally (§2, §3) rather than by a separate `rm -rf` step, with the WAF rule (§3) retained as a second layer.
- `README.md`, `build.sh` itself, and any package/lockfile — never part of the allowlist.
- **Any future top-level repository entry**, unless explicitly added to `build.sh`'s allowlist and reviewed in that PR's diff — this is the point of the default-deny model in §2.

None of this reflects new confidentiality concerns: the GitHub repository is public, so nothing above becomes newly inaccessible to someone who goes looking — this change only removes the ability to reach it directly from the production apex domain without first finding the GitHub repository.

---

## 6. Production domain, DNS, and HTTPS

The production domain, `specboundapp.com`, is live and already connected to this Cloudflare Pages project — this document doesn't re-describe domain selection or first connection as future work.

A read-only check today confirmed: `http://specboundapp.com/` redirects to `https://specboundapp.com/` (200 after redirect), and a direct HTTPS request to the homepage returns 200. SSL is auto-provisioned and auto-renewed by Cloudflare Pages for both the production domain and the `*.pages.dev` subdomain — no manual certificate management.

**HSTS (`Strict-Transport-Security`) is being rolled out in stages, not shipped at full strength immediately.** As of Milestone 27A PR3, `_headers` sets `Strict-Transport-Security: max-age=300` (5 minutes) on `/*` — Stage 1: long enough to prove the header is actually served correctly and that nothing HTTP-only breaks under it, short enough that any mistake self-heals within minutes rather than being locked in for weeks (a long `max-age` plus `includeSubDomains` is hard to safely undo once real browsers have cached it). `includeSubDomains` and `preload` are deliberately **not** set yet, and `max-age` is deliberately capped at 300 — `tools/ci/check-security-headers.js` fails CI if any of the three drifts. Stage 2 (a longer `max-age`), Stage 3 (`includeSubDomains`), and eventual `preload`-list submission are deferred to a later milestone once Stage 1 has run in production without incident. See §14.

---

## 7. Supabase and authentication configuration

**Public client configuration** (safe to commit, safe for client-side exposure): `js/core/config.js` hardcodes the Supabase project URL and a *publishable* client key (Supabase's `sb_publishable_...` format, not a service-role key). This document intentionally does not reproduce that key's literal value — see `docs/AUTH_ARCHITECTURE.md` and `docs/STORAGE_ARCHITECTURE.md` for the RLS model this configuration relies on. **Never commit a service-role key, a Discord Client Secret, an access token, or any other credential to this repository.**

**Current Supabase Auth configuration** (per the verified starting state for this task — not re-inspected in the live dashboard during this documentation task):

- **Site URL:** `https://specboundapp.com` — this is the single highest-consequence setting in this whole document if it's ever wrong. Password-reset and signup-confirmation emails embed a link back to whatever URL is configured here; the signup confirmation flow in particular has no explicit `redirectTo` in this repo's code, so it relies entirely on this setting.
- **Redirect URLs** includes `https://specboundapp.com/pages/settings.html` — the exact URL `js/pages/settings/app.js` passes as `redirectTo` when a user links Discord (`window.location.href` at the moment "Connect Discord" is clicked). The password-reset flow (`js/pages/forgotPassword/app.js`) builds its own `redirectTo` dynamically from the current origin, so it doesn't require a separate allowlist entry beyond the Site URL itself.
- **Discord provider:** enabled, with manual identity linking enabled (`GOTRUE_SECURITY_MANUAL_LINKING_ENABLED`) — required for `supabase.auth.linkIdentity()` to attach Discord to an already-signed-in account rather than only supporting first-time sign-in.

No RLS, storage policy, or schema change is required as part of deployment — those are managed through this repository's tracked migrations (`supabase/migrations/`) and applied independently via the Supabase CLI, not through Cloudflare Pages. Repository presence of a migration file is not the same fact as production application. As of the Milestone 23 production deployment (2026-08-12), **production's migration history matched local through `0035`** — `supabase migration list --linked` confirmed all 36 migrations present on both sides at that time, and a `supabase db push --linked --dry-run` afterward reported production up to date. `0034` had, in fact, already been applied before that deployment's own preflight even started (this document previously said otherwise — see `supabase/migrations.md`'s `0034` entry for that discrepancy); `0035` was the one genuinely pending migration at that time, applied as part of that deployment. **As of Milestone 27A PR4 (2026-08-15), production's migration history matches local through `0041`** (42 files total) — re-confirmed directly via `supabase migration list --linked`, which reported every migration `0000`–`0041` present on both sides with no pending migrations.

---

## 8. Supabase Edge Functions

Milestone 23 introduced this app's first Supabase Edge Function — `supabase/functions/product-metadata` (best-effort product-page metadata extraction for the Setup-inventory link-assisted entry flow; see `docs/milestones/MILESTONE_23_SETUP_INVENTORY_SEARCH_SPECIFICATION.md` §5 for the full design and SSRF-defense rationale). **Deployed to production on 2026-08-12**, following the order below.

**Deploy command** (from the repository root, once linked to the target project):

```
supabase functions deploy product-metadata --project-ref <project-ref>
```

**Requires no new secrets** — the function reads only `SUPABASE_URL`/`SUPABASE_ANON_KEY` from its own Edge Function runtime environment (both auto-provided by Supabase for every deployed function) and verifies the caller's JWT itself; no service-role key is used anywhere in the function or in any browser code. Confirmed at deployment: `supabase secrets list --project-ref <project-ref>` shows no custom secrets were added for this function, by design — only Supabase's automatically-supplied runtime variables are used.

**Deployment order followed for Milestone 23** (executed 2026-08-12):

1. Applied migration `0035_setup_inventory_and_builder_dates.sql` to the target project (`supabase db push --linked --yes`), after a dry run confirmed it was the one genuinely pending migration.
2. Verified the migration afterward: `supabase migration list --linked` showed 0000-0035 matching local and remote; a second dry run reported production up to date.
3. Deployed the `product-metadata` Edge Function (command above). Confirmed `ACTIVE` and `verify_jwt: true` via `supabase functions list --project-ref <project-ref>`.
4. Verified the function correctly requires authentication — a direct unauthenticated request returned `401 {"code":"UNAUTHORIZED_NO_AUTH_HEADER"}` before the function's own code ran, the platform-level JWT gate working as intended, not a 404/500.
5. Confirmed the website already matched the merged Milestone 23 commit (`4629c34`) — Cloudflare Pages' GitHub integration had already deployed it to `specboundapp.com` ahead of the database/function work, verified via the GitHub Checks API and by fetching live production JS and confirming Milestone-23-specific code was present.
6. Ran production smoke tests against a disposable, since-unpublished test project: manual (no-URL) product entry and totals; a supported-retailer URL (ikea.com) correctly filling in partial metadata without fabricating a price; an unsupported-retailer URL correctly showing the documented fallback message while leaving a hand-typed title untouched; the public build page's Setup Inventory section rendering products, totals, and outbound product links correctly with no horizontal overflow at desktop or mobile width.

Deploying the website **before** the migration is what would have produced the exact `42703` error this section's §7 note describes — every `getBuilderPortfolioProfile()`-backed Builder Portfolio page load, and every setup-inventory read/write, would have failed until the migration landed. That error was confirmed live during the pre-deployment audit (see `supabase/migrations.md`'s `0035` entry), which is exactly why the order above was followed, not skipped.

Metadata extraction is always best-effort — manual product entry (title, price paid, free toggle, source) works with or without the Edge Function deployed, is never blocked by a fetch failure, and never requires a successful metadata fetch to add or publish a product.

### 8.1 `delete-account` — self-service account deletion (implementation-reviewed, NOT yet deployed to production)

**This is a genuine architectural first for this project: `delete-account` is the first Edge Function — and the first anything in this repository — that requires a service-role key.** `docs/OPERATIONS.md` §5 has stated since Milestone 27A "there is no service-role key... anywhere in this codebase to rotate... If that ever changes... this section will need real secret-management guidance that doesn't exist today." That change has now happened; §5's rotation guidance has been updated accordingly — read it before deploying this function.

**Deploy command** (from the repository root, once linked to the target project):

```
supabase functions deploy delete-account --project-ref <project-ref>
```

**Requires one new secret, set once before first deploy:**

```
supabase secrets set SUPABASE_SERVICE_ROLE_KEY=<the project's actual service-role key, from the Supabase dashboard's API settings> --project-ref <project-ref>
```

**Never**: paste the service-role key into this repository, a commit, a terminal transcript that gets saved anywhere, a screenshot, or this document. The command above is written with a placeholder deliberately — the real value is entered directly wherever you run the `supabase secrets set` command, from the Supabase dashboard, not copied through any intermediate file. `SUPABASE_URL`/`SUPABASE_ANON_KEY` continue to be auto-provided by Supabase for every deployed function, same as `product-metadata`.

**Required migrations, in order, before this function is deployed** (see `supabase/migrations/0044`-`0049`'s own headers for the full rationale behind each):

1. `0044_normalize_user_deletion_fks.sql` — converges the `profiles`/`builds`/`build_revisions` foreign-key discrepancy between the reconstructed baseline and production's actual, confirmed shape.
2. `0045_moderation_actions_preserve_audit.sql` — `moderation_actions.actor_id` becomes nullable, `ON DELETE SET NULL` instead of `CASCADE`. **Deploying `delete-account` before this migration is applied would mean every self-deletion's own audit row destroys itself the instant the Auth user is actually removed** — see `0049_account_deletion_challenge.sql`'s own header for why this isn't just a departing-moderator edge case.
3. `0046_legal_holds.sql` — the private hold table and its two staff-gated RPCs.
4. `0047_account_deletion_jobs.sql` — the durable orchestration table.
5. `0049_account_deletion_challenge.sql` — the private, single-use challenge table, `request_account_deletion_challenge()`, and `self_delete_account(uuid)`, the RPC this Edge Function calls. **Supersedes `0048_self_delete_account.sql`** — that migration's zero-argument function is dropped by `0049`, not left callable alongside it; `0048` must still be applied first (`0049` depends on it), but `0049` is what this Edge Function actually targets. See `0049`'s own header for why the zero-argument version was insufficient (it relied on a caller-checked JWT `iat` claim, which Supabase's own routine token-refresh advances without re-verifying the password) and `docs/DEPLOYMENT.md`'s own PR history for the security-review finding that produced this migration.
6. `0050_account_deletion_recovery.sql` — three new `account_deletion_jobs` columns (`claimed_at`/`claimed_by`/`recovery_attempts`) and the three `service_role`-only functions `§8.2` below's Edge Function calls. Also changes what `delete-account`'s own Step 2/3 job bookkeeping calls (`record_account_deletion_auth_result()`/`record_account_deletion_storage_result()` instead of a raw table update) — deploy `delete-account` itself no earlier than this migration, or its first two RPC calls to those functions will fail (function does not exist yet).
7. `0051_account_deletion_jobs_wall_clock_updated_at.sql` — not a hard functional blocker for either Edge Function (nothing fails without it), but should be applied before real production use: fixes `account_deletion_jobs.updated_at` so it genuinely reflects wall-clock time across multiple UPDATEs within one transaction (real local testing found the shared, codebase-wide `updated_at` trigger does not — see that migration's own header for the full root cause and why the fix is deliberately scoped to this one table).

**Running the SQL test suite — corrected.** A previous version of this section documented a single loop over `supabase/tests/*.test.sql` as if every file in that glob could run independently against one full `db reset --local`. **That was wrong**, caught by real local testing: three files are NOT independently runnable that way — each requires its own destructive, version-pinned reset plus a specific legacy fixture loaded BEFORE the remaining migrations run, or every assertion in it fails immediately with errors like `relation public._legacy_upgrade_pre_components does not exist`:

- `migration_0020_0033_legacy_upgrade.test.sql` — reset to version `0019`, then `fixtures/legacy_catalog_fixture.sql`.
- `migration_0042_legacy_upgrade.test.sql` — reset to version `0041`, then `fixtures/legacy_build_status_fixture.sql`.
- `migration_0044_legacy_upgrade.test.sql` — reset to version `0043`, then `fixtures/production_shaped_user_deletion_fks_fixture.sql`.

Each of those three files' own header already documents its exact required sequence (reset → inject fixture → `migration up` → run the test) — this section does not repeat it, only makes explicit that these three must be run **separately from, and never interleaved with,** the main loop below, and that the main loop must **exclude** them. `migration_0020_0033_fresh_install.test.sql` and `migration_0044_fresh_install.test.sql` are NOT in this category — despite the similar naming, both use a normal full `db reset --local` and belong in the main loop.

**PowerShell (Windows — the primary shell for this repository):**

```powershell
# 1. Main loop — every test EXCEPT the three legacy-upgrade files above,
#    against one full db reset (0000-latest).
npx supabase db reset --local
$dbUrl = (npx supabase status -o env --local | Where-Object { $_ -match '^DB_URL=' }) -replace '^DB_URL=', '' -replace '"', ''

$mainTests = Get-ChildItem supabase/tests/*.test.sql | Where-Object { $_.Name -notlike '*_legacy_upgrade.test.sql' }
foreach ($f in $mainTests) {
    Write-Host "=== $($f.Name) ==="
    psql $dbUrl -v ON_ERROR_STOP=1 -f $f.FullName
    if ($LASTEXITCODE -ne 0) {
        Write-Host "FAILED: $($f.Name)"
        break
    }
}
```

```powershell
# 2. The three legacy-upgrade files — run separately, each in its own
#    version-pinned reset + fixture-injection cycle. Requires the local
#    Supabase Postgres container's name (find it once with
#    `docker ps --format "{{.Names}}"` -- the one whose image is
#    supabase/postgres) and psql on PATH (or substitute the equivalent
#    `docker exec -i <container> psql ...` form each file's own header
#    already documents, if psql isn't installed locally).
$container = "<the container name found above>"

$legacyTests = @(
    @{ Version = "0019"; Fixture = "supabase/tests/fixtures/legacy_catalog_fixture.sql"; Test = "supabase/tests/migration_0020_0033_legacy_upgrade.test.sql" },
    @{ Version = "0041"; Fixture = "supabase/tests/fixtures/legacy_build_status_fixture.sql"; Test = "supabase/tests/migration_0042_legacy_upgrade.test.sql" },
    @{ Version = "0043"; Fixture = "supabase/tests/fixtures/production_shaped_user_deletion_fks_fixture.sql"; Test = "supabase/tests/migration_0044_legacy_upgrade.test.sql" }
)

foreach ($t in $legacyTests) {
    Write-Host "=== legacy harness: $($t.Test) (reset to $($t.Version)) ==="
    npx supabase db reset --local --no-seed --version $($t.Version)
    Get-Content $($t.Fixture) -Raw | docker exec -i $container psql -U postgres -d postgres -v ON_ERROR_STOP=1 -f -
    npx supabase migration up --local
    Get-Content $($t.Test) -Raw | docker exec -i $container psql -U postgres -d postgres -v ON_ERROR_STOP=1 -f -
}
```

```powershell
# 3. Restore the local stack to the full, current migration chain
#    afterward -- step 2 above leaves the database pinned to an old
#    version plus fixture data, not representative of a real instance.
npx supabase db reset --local
```

**A fresh `db reset --local` is required**, not optional — three separate times in the sequence above (once before the main loop; implicitly once per legacy-upgrade file, since each pins to a different historical version; once more at the end to restore full-chain state) — and once again right now regardless, before running any of this, since this PR's own `0051` migration (and everything in this PR) did not exist in whatever local database state was used for the previous test run reported.

**Accuracy correction**: the previous version of this section implied every file under `supabase/tests/*.test.sql` could be executed independently by the same simple loop. That is not true for the three legacy-upgrade files above, and is not claimed here. `supabase/tests/superseded/*.superseded.sql` remains excluded by the glob itself (see that directory's own `README.md`) — those files test an earlier, now-replaced design and are expected to fail if run directly against the current migration chain; that is not a regression.

**Production verification checklist, once deployed** (none of this has been performed yet — this function has not been deployed anywhere beyond implementation review):

- Confirm `verify_jwt` behavior matches this function's own manual JWT check (it verifies the caller itself via `userClient.auth.getUser()`, same pattern as `product-metadata`) — a request with no `Authorization` header returns `401 {"error":"auth_required"}` before any database or Auth Admin call runs.
- Confirm a request from a session with **no recent password reauthentication** — including a session kept alive purely by Supabase's own automatic token refresh, never re-entering the password — is rejected with `401 {"error":"reauth_required"}` by `request_account_deletion_challenge()` (checked via `auth.jwt() -> 'amr'`, not the JWT's top-level `iat`; see `0049`'s own header), never proceeding to the database-preparation step. This is the specific case a security review found the original `iat`-only design did not actually protect against — verify it directly, not just that *some* reauth check exists.
- Confirm a stale or already-used deletion-authorization challenge (an old token, someone else's token, or a token already consumed by an earlier successful/attempted call) is rejected by `self_delete_account(uuid)` with the same generic, non-distinguishing failure.
- Using a genuinely disposable test account only, never a real one: confirm the full success path end-to-end (challenge issued → `self_delete_account()` commits → `auth.admin.deleteUser()` succeeds → Storage cleanup runs → `account_deletion_jobs` reaches `storage_cleaned`), then confirm the same test account can no longer sign in.
- Confirm a legal hold placed on a disposable test account (via `place_legal_hold()`) blocks deletion with the generic `db_prep_failed`-shaped response, never a response distinguishable from any other failure.
- Confirm `account_deletion_jobs` **and** `account_deletion_challenges` rows are genuinely unreachable via the anon/publishable key from the browser (RLS enabled, zero policies) — the same kind of direct-REST-API check this document's own Launch Readiness Audit history already establishes as standard practice for a sensitive table.

**Non-atomicity, disclosed explicitly**: this function spans three genuinely separate systems (Postgres, the Supabase Auth Admin API, Storage) with no cross-system transaction — see `supabase/functions/delete-account/index.ts`'s own header and `public.account_deletion_jobs` (`0047`) for the full retry/recovery design. A partial failure never leaves the database half-cleaned with the Auth user still reachable in an inconsistent way; the worst case is a delayed-but-eventually-consistent completion via retry — either the same user's own client retrying `delete-account` (while their session is still valid — see below for the case where it no longer is), or `account-deletion-recovery` (§8.2).

### 8.2 `account-deletion-recovery` — restricted resume worker (implementation-reviewed, NOT yet deployed to production)

Closes a gap `§8.1`'s own original review disclosed: once `auth.admin.deleteUser()` succeeds, the former user has no valid session, so `delete-account` can never be invoked again on their behalf — there was previously no way to resume a Storage cleanup failure, or an Auth-deletion failure, once the client side of that specific attempt was gone. This function has no user-facing caller at all; it is never linked from `js/`, never invoked by `supabase.functions.invoke()`, and carries no user JWT of any kind — see its own `index.ts` header for the full security-boundary reasoning, summarized here only for the deploy procedure.

**Deploy command** (from the repository root, once linked to the target project):

```
supabase functions deploy account-deletion-recovery --project-ref <project-ref>
```

**Requires one new secret, set once before first deploy** (independent of `delete-account`'s own `SUPABASE_SERVICE_ROLE_KEY`, which this function also needs and shares):

```
supabase secrets set ACCOUNT_DELETION_RECOVERY_SECRET=<a long, random value generated for this purpose only> --project-ref <project-ref>
```

**Never**: reuse any other secret in this codebase for this value, paste it into this repository, a commit, a terminal transcript that gets saved anywhere, a screenshot, or this document. Generate it fresh (e.g. `openssl rand -hex 32`, run locally, output entered directly into `supabase secrets set` — never saved to an intermediate file). Same posture `§8.1` already requires for the service-role key itself.

**Requires migration `0050_account_deletion_recovery.sql`** applied first (see the migration list in `§8.1` above) — this function's every RPC call (`claim_account_deletion_jobs`, `record_account_deletion_auth_result`, `record_account_deletion_storage_result`) will fail with "function does not exist" until it is.

**How it is invoked/scheduled** — two supported options, neither of which is set up yet (this function has not been deployed anywhere beyond implementation review):

1. **Supabase's own scheduled Cron** (`pg_cron` + `pg_net`, configured via the Supabase dashboard's Database → Cron Jobs, or a migration calling `cron.schedule()`) — the recommended option for ongoing production use. The scheduled job calls this function's deployed URL via `net.http_post()`, with `x-recovery-secret` sourced from a Supabase Vault secret, never hardcoded into the cron job definition itself. A reasonable starting cadence is every 15-30 minutes — frequent enough that a failed Storage cleanup or Auth-deletion attempt does not sit unresolved for long, infrequent enough that it is never a meaningful load concern (`JOBS_PER_RUN = 10` per invocation, see the function's own `index.ts`).
2. **Manual, operator-run invocation** — for a one-off check or before Cron is set up:

```
curl -X POST "https://<project-ref>.supabase.co/functions/v1/account-deletion-recovery" \
  -H "x-recovery-secret: <the secret, entered directly, never from a file>"
```

**Which secret protects it**: `ACCOUNT_DELETION_RECOVERY_SECRET` alone — this function's own `supabase/config.toml` entry sets `verify_jwt = false` deliberately (see that entry's own comment for why a Supabase Auth JWT check would be actively misleading here, not merely redundant). A request missing the header, or presenting the wrong value, is rejected `401` before any database call — see `isAuthorizedRecoveryRequest()`/`timingSafeEqual()` in the function's own `lib.ts`.

**Production verification checklist, once deployed** (none of this has been performed yet):

- Confirm a request with no `x-recovery-secret` header, and a request with a wrong one, both return `401 {"error":"unauthorized"}` with zero database activity (check no new rows/updates in `account_deletion_jobs`, and nothing in Postgres logs for this request).
- Confirm the correct secret, POSTed with no claimable jobs queued, returns `200 {"claimed":0,"results":[]}`.
- Using a genuinely disposable test account only: drive it through `delete-account` far enough to land in `'db_prepared'` or `'auth_deleted'` deliberately (e.g. by having Storage cleanup fail — a bucket policy or path that will not remove cleanly on a disposable test project only), then invoke this function manually and confirm the job reaches `'auth_deleted'`/`'storage_cleaned'` as appropriate, with `storage_paths` reduced correctly, not reset to the original list.
- Confirm `anon`/`authenticated` PostgREST calls to `claim_account_deletion_jobs`/`record_account_deletion_auth_result`/`record_account_deletion_storage_result` are rejected with a permission error, directly against the REST API with a real anon/authenticated key — not just the SQL-level `has_function_privilege()` check `migration_0050_account_deletion_recovery.test.sql` already covers.

---

## 9. Discord production configuration

Discord account linking (Settings → Connected Accounts) requires its own Supabase provider settings and a matching Discord Developer Portal redirect — the full checklist, troubleshooting table, and security notes live in **[`docs/DISCORD_SETUP.md`](DISCORD_SETUP.md)**; this section only records the current state, not the full procedure.

- **Discord hosted callback** (Discord Developer Portal → OAuth2 → Redirects): `https://xpxjqyraizntbtijzoyp.supabase.co/auth/v1/callback` — Supabase Auth's own fixed callback for this project, not the Specbound Settings page.
- **Settings return URL:** `https://specboundapp.com/pages/settings.html` (see §7).
- **Production verification:** the complete Discord flow has been manually tested successfully — connect and OAuth return, username synchronization, public visibility, the correct outbound Discord profile link, the privacy toggle, refresh, and disconnect with public removal. This documentation task did not repeat that test or modify either dashboard; it records the prior verified result.

---

## 10. Security headers and caching

Verified directly against `_headers` and a live response check today.

`_headers` sets, for every path (`/*`): `X-Content-Type-Options: nosniff`, `Referrer-Policy: strict-origin-when-cross-origin`, `Permissions-Policy: geolocation=(), microphone=(), camera=()`, and a `Content-Security-Policy` with no `unsafe-inline` and no wildcard origins — `script-src` allows only `'self'`, `https://cdn.jsdelivr.net`, and `https://static.cloudflareinsights.com`; `connect-src` allows only `'self'`, the Supabase project origin, and `https://cloudflareinsights.com`. The two `cloudflareinsights.com` entries exist for Cloudflare Pages' own Web Analytics beacon, which Cloudflare injects into HTML responses at the edge — it is not present anywhere in this repo's own source. A live header check today found those two allowances present on the homepage's CSP but absent from CSS/JS response CSPs, consistent with the beacon only ever loading in an HTML document context.

**Post-Milestone-23 maintenance console-warning investigation (2026-08-12)** — production's console consistently shows three categories of noise, each verified down to a specific cause rather than left as an unexplained pattern:

- **CSP inline-script violations, a different hash every page load.** Root cause: Cloudflare's own Bot Management "JS Detections" (`cf.jsd`) fingerprinting snippet, injected directly into the raw HTML response at the edge (confirmed via a direct `fetch("/")` and inspecting the response body — not present in this repository's `index.html` or any other tracked HTML file). It builds a hidden 1×1 iframe and writes an inline `<script>` into it containing a per-request token (`window.__CF$cv$params={r:'...',t:'...'}`), which is exactly why the hash differs every time — a hash-based CSP allowance is not possible for content that's different on every request, and adding `'unsafe-inline'` to `script-src` to accommodate it would weaken the policy for this application's own code too. Cloudflare-injected, not actionable from this repository; documented rather than worked around.
- **`cloudflareinsights.com/cdn-cgi/rum` CORS failures**, and a separate, report-only `"connect-src 'none'"` CSP message. Both trace to Cloudflare Pages' automatic "Speed Brain" feature — every response carries a `Speculation-Rules: "/cdn-cgi/speculation"` header (confirmed live: fetching that URL returns a Cloudflare-authored `{"tag":"cf-speed-brain", "prefetch": [...]}` document, not anything this repo serves), which tells the browser to conservatively prefetch same-origin links via the Speculation Rules API. Chrome applies a restrictive internal policy — including `connect-src 'none'`, report-only — to a document while it's still a speculative prefetch candidate, which is what generates that message; the RUM beacon's own CORS failure against Cloudflare's own endpoint is Cloudflare's issue with its own analytics infrastructure, not this application's. Neither is configurable from `_headers` or any other repository file — Speculation Rules injection is a Cloudflare Pages platform feature, not something this repository opted into or can opt out of from the app side.
- **Four repeated HTTP 400 console errors per page**, present identically regardless of what page or app code runs. Directly ruled out as this application's own doing: the two most plausible first-party candidates — `GET /auth/v1/user` (session check) and the notification unread-count query — were both replicated live against production using the real signed-in session's own access token and both returned `200`, not `400`. This environment's network-inspection tooling cannot capture `fetch()`/XHR-based requests (only document/static-asset loads), so the literal failing request URL could not be captured directly. Given they cluster tightly with the Bot Management/JSD and Speed Brain activity described above in every console capture, on every page, independent of any Specbound code path, the working conclusion is that they are follow-up requests from that same Cloudflare-injected tooling — not confirmed with the same certainty as the two findings above, and intentionally left unfixed rather than guessed at. Flagged here as the one console-noise item that would benefit from Cloudflare-side (dashboard/support) investigation rather than repository changes.

One inline-style violation was **not** Cloudflare's doing: `index.html`'s homepage hero mark used `style="--i:N"` directly on 5 SVG `<path>` elements to drive a staggered entrance/spiral animation (`css/pages/home/home.css`'s `hero-mark-enter`/`hero-mark-spiral` keyframes). With no `'unsafe-inline'` in `style-src`, the browser silently dropped every one of those attributes, so all 5 tiles animated in lockstep instead of staggered — a genuine, live, in-repo bug, fixed in the same maintenance pass by moving `--i` into `:nth-child()` rules in `home.css` instead, removing the inline style entirely rather than relaxing the CSP.

`/css/*` and `/js/*` additionally get `Cache-Control: public, max-age=0, must-revalidate`, forcing a conditional revalidation request on every load instead of relying on Cloudflare Pages' own default 4-hour browser cache — the default that previously caused an already-open browser tab to keep rendering pre-deploy CSS/JS for up to four hours after a new deploy went live. `must-revalidate` (not `no-store`) was chosen deliberately so an unchanged file can still return a cheap 304 instead of a full re-download; a live check today confirmed both CSS and JS responses carry a matching `ETag` and the expected `Cache-Control` value. Images and other static assets are intentionally left on Cloudflare's default caching — they change far less often. **HTML responses were also observed carrying the same `Cache-Control: public, max-age=0, must-revalidate` today**, even though `_headers` doesn't declare that for `/*` — likely a Cloudflare Pages platform default for document navigations rather than anything this repository configures; noted here as an observed fact, not independently diagnosed further.

Cloudflare also adds its own operational headers on every response (`CF-RAY`, `Server: cloudflare`, `NEL`/`Report-To`, a permissive `Access-Control-Allow-Origin: *`, `Speculation-Rules`) — expected platform behavior, not something `_headers` or this repository controls.

If a caching issue is ever suspected beyond what `_headers` already addresses, the Cloudflare dashboard exposes a manual **Purge Cache** action under Caching as a fallback.

---

## 11. SEO and public platform files

Verified directly against the repository source and, where noted, a live fetch today.

- **`robots.txt`:** disallows `/pages/settings.html`, `/pages/workshop.html`, `/pages/notifications.html`, `/pages/moderation.html`, `/pages/feedback.html`, `/pages/my-feedback.html`, `/pages/build/edit.html`, `/design-system.html`, and `/tests/`; references `sitemap.xml` at `https://specboundapp.com/sitemap.xml`. A live fetch today confirmed the repository's own rules are served intact, but Cloudflare additionally injects a "Managed content" block ahead of them — AI-crawler-specific `Disallow` rules (GPTBot, CCBot, Bytespider, etc.) and a `Content-Signal` directive — that isn't present in this repo's committed file. This is Cloudflare account/zone-level behavior, not something `robots.txt`'s source controls.
  - **Policy — two different categories, not one blanket rule (corrected Milestone 27A PR3 follow-up):** this app has two distinct kinds of `noindex`'d page, and they get different `robots.txt` treatment on purpose.
    - **Gated application pages** — Feedback, My Feedback, Moderation, Workshop, Settings, Notifications, the draft editor — require sign-in to show any real content, and their links only ever render in the *authenticated* branch of the navbar (`js/core/layout.js`). An anonymous visitor or crawler never sees an `<a href>` to any of these anywhere on the public site, so `Disallow`-ing them has no discoverability downside — nothing ever offers a crawler the URL in the first place. These keep both `noindex` and a matching `Disallow` line.
    - **Auth-flow utility pages** — Login, Sign Up, Forgot Password, Update Password — are the opposite case: they're usable while signed out (by definition) and are genuinely linked from crawlable surfaces — the navbar's "Sign In" link renders on *every* public page for a signed-out visitor, and the four pages are statically cross-linked to each other (`login.html`↔`signup.html`↔`forgotPassword.html`). An earlier version of this policy `Disallow`'d these too and claimed they were "linked from nowhere outside the signed-in app" — that claim was checked against the actual navbar/link markup and found to be **false** for this category; it was only ever true for the gated-application category above. `Disallow`-ing a page that real links point to prevents a crawler from ever fetching it to read its `noindex` tag, which can leave a bare, snippet-less URL sitting in search results instead of a clean exclusion — the opposite of the intended effect, and exactly the failure mode Google's own guidance warns about for combining the two mechanisms on a linked page. These four now keep `noindex` but are **not** `Disallow`'d, so a crawler that does discover the link can fetch the page and correctly drop it from the index.
    - `tools/ci/check-crawl-policy.js` enforces this three-way split directly: gated pages must have both `noindex` and `Disallow`; auth-utility pages must have `noindex` and must **not** be `Disallow`'d; declared-public pages must never be `Disallow`'d. It also still catches any newly-added page that gates its own content behind `requireAuth()` but isn't yet classified into one of these lists.
    - **Neither `robots.txt` nor `noindex` is a security boundary.** Both are voluntary conventions a well-behaved crawler chooses to respect — they keep search results clean, nothing more. Every one of these pages' real content is still gated server-side by Supabase Auth/RLS regardless of what any crawler does or doesn't fetch; a misbehaving or malicious client ignoring `robots.txt` entirely gains no access it wouldn't otherwise have.
- **`sitemap.xml`:** 13 URLs today — confirmed both from the repository file and a live fetch, all using `https://specboundapp.com`: the homepage, Explore, Search, the 6 category pages, and the 4 legal pages. Individual build/profile pages are deliberately excluded (dynamic, numerous, already reachable via internal links). This count isn't pinned as a permanent constant — verify it directly (`grep -c "<loc>" sitemap.xml`) rather than trusting a frozen number if this file changes later.
- **`manifest.webmanifest`:** references three icon sizes (32×32, 192×192, 512×512), all present under `assets/brand/logo/`. Confirmed identical between the repository file and a live fetch. Not a full PWA (no service worker).
- **Favicons:** `index.html` and `404.html` link PNG favicons at 16×16, 32×32, and 48×48, plus an `apple-touch-icon`. `assets/brand/logo/favicon.svg` exists in the repository but is **not** linked from any page `<head>` as an active favicon today — if a future page adds an SVG favicon link, update this section rather than assuming it already exists.
- **`404.html`:** a custom branded page, correctly returned for a nonexistent path — confirmed live today (`404` status, the actual custom page content, not Cloudflare's generic default). It also sets `<meta name="robots" content="noindex">`. No custom 500 page exists or is needed — this architecture has no server-side code path that could produce one; Supabase-layer failures are handled by the app's own client-side error UI.
- **Open Graph / Twitter Card image:** `assets/brand/og/og-image.png` (1200×630), the single generic image used by every page including dynamic ones. This app has no server-side rendering, so a static HTML template cannot emit a different image per build — a disclosed limitation, not an oversight.

---

## 12. Deployment verification

Kept deliberately separated by who or what actually performs each check, so nothing gets assumed covered by a layer that doesn't actually cover it.

**Automated, on every push and pull request (GitHub Actions, `.github/workflows/ci.yml`):** JavaScript syntax validation, local reference checking, accessibility regressions, CSP/bootstrap validation, production-domain validation, crawl-policy validation, security-header validation, **the deployment-artifact check (`tools/ci/check-deploy-artifact.js`)**, and the browser-based regression suite under `tests/*.test.html`. See `docs/CI.md` for exactly what each covers and its known limitations. **GitHub Actions does not run the SQL migration/RLS policy tests** — those live under `supabase/tests/` and require a separate, disposable local Supabase/Docker stack (`supabase db reset --local`); they are not part of this CI pipeline.

`tools/ci/check-deploy-artifact.js` runs the real `build.sh`, then asserts against the resulting `dist/`: its top-level entries exactly match §5's allowlist (nothing missing, nothing unexpected); none of the excluded categories (`docs/`, `supabase/`, `tests/`, `tools/`, `.github/`, `.claude/`, `README.md`, `build.sh`, package files) exist anywhere within it, at any depth; `_headers`, `404.html`, `robots.txt`, `sitemap.xml`, and `manifest.webmanifest` are present; and every local HTML/CSS/JS reference resolves to a real file *within* `dist/` — not merely somewhere in the repository — so a reference that would 404 in production is caught in CI, not discovered live.

**Post-dashboard-change production verification (run once §3's migration sequence step 2 is complete — not yet performed as of this writing):**
- Homepage, a `pages/` sample, `css/`, `js/`, `assets/` all still `200` with correct content and unchanged `_headers`-driven response headers.
- `robots.txt`/`sitemap.xml`/`manifest.webmanifest` still `200`.
- A nonexistent path still returns the real branded `404`.
- Clean URLs (`/design-system`) and every auth page (login/signup/forgot-password/Discord connect) still load and function.
- Pull-request preview deployments also build correctly via the same `build.sh`.

**Excluded-path checks — two different expected results, not one, since the WAF rule (§3) intercepts four of the six excluded categories before Cloudflare Pages ever sees the request:**

- **WAF-protected paths — expected result: Cloudflare's `403` block page, *not* a `404`, as long as the WAF rule stays enabled:** `/tests/`, `/tools/`, `/.github/`, `/.claude/`. A live HTTP check against these cannot independently prove `build.sh`'s allowlist also excludes them — the WAF answers first, so the request never reaches `dist/` either way. Their absence from `dist/` itself is proven instead by: `tools/ci/check-deploy-artifact.js` (§12, runs on every push/PR), direct inspection of the generated `dist/` tree (`sh build.sh` then `ls dist/`), and, if available, a PR preview / `*.pages.dev` deployment — which is not covered by the custom-domain WAF rule — showing the real branded `404` for these same paths instead of a `403`.
- **Newly excluded, not WAF-protected — expected result: the real branded `404`, proving `build.sh`'s allowlist (not the WAF) is what keeps them out:** `/docs/`, `/supabase/`, `/README.md`, `/build.sh`.

**Safe public endpoint checks (no sign-in, no state change) — performed for this documentation task, results above:** homepage HTTPS/200, HTTP→HTTPS redirect, `robots.txt`, `sitemap.xml`, `manifest.webmanifest`, a nonexistent-path 404, and response headers on an HTML/CSS/JS sample. These are safe to repeat at any time.

**Manual signed-in smoke tests — not performed by this documentation task, and not to be inferred as passing from the checks above:**
- Homepage, Explore, a build page, Login, Signup, the editor, and Settings load with zero CSP violation console errors
- View-source on a sample of pages shows `<title>`, `<meta name="description">`, and `og:*`/`twitter:*` tags in the raw HTML response
- A real password-reset email test against production, confirming the emailed link points at `https://specboundapp.com`

**Already completed, recorded here as verified (not re-performed today):** the full Discord production test in §9.

**Human dashboard checks — cannot be performed from this environment:** confirming the live Cloudflare Pages build/output/pruning settings actually match §3; confirming Supabase's Site URL/Redirect URLs/Discord provider match §7 by looking at the dashboard directly rather than relying on the verified starting state.

---

## 13. Rollback procedure

Cloudflare Pages retains every deployment. To roll back:

1. Cloudflare dashboard → Pages project → **Deployments** tab.
2. Find the last known-good deployment.
3. Open the three-dot actions menu for the desired previous production deployment, select **Rollback to this deployment**, and confirm.
4. Once confirmed, the selected deployment becomes production immediately—no rebuild or git operation is required. Cloudflare's deployment history is independent of git history; a bad deploy can be undone without touching the repository.

This describes Cloudflare Pages' documented rollback **capability**. **No live rollback drill has been performed and is not claimed here** — see §14. Reverting through git (`git revert` on the bad commit and pushing the resulting commit to `main`) is a separate, slower path that triggers a brand-new build rather than instantly restoring a prior one; the dashboard rollback above is the faster option for an active incident.

**Coordinated rollback for the `build.sh`/`dist/` change specifically:** the migration sequence in §3 is a two-part change — a repository commit (`build.sh`, `.gitignore`, `check-deploy-artifact.js`) *and* a Cloudflare dashboard setting (Build command, Build output directory). A `git revert` of the repository commit alone does **not** undo the dashboard setting, and a dashboard-only revert alone leaves `build.sh` untracked-but-referenced. If this change needs to be undone, do both together: dashboard rollback (or reset Build command/Build output directory back to `rm -rf tests tools .github .claude` / `/`) **and** `git revert` the repository commit, in either order, before considering the rollback complete.

---

## 14. Remaining operational checks

Genuinely open items — nothing here is marked complete without evidence:

- SMTP/email provider configuration for production traffic — Supabase's default email service has strict rate limits, not recommended at scale. Not verified in this task.
- Confirming the Supabase project's backup/point-in-time-recovery tier. Not verified in this task.
- A real production password-reset email test, confirming the emailed link resolves to `https://specboundapp.com`.
- A real rollback drill (§13) — capability is documented, a live test is not.
- Cross-browser/cross-device manual checks — not currently covered by any automated or manual process beyond ad hoc spot checks during development.
- Advancing HSTS (§6) past Stage 1 (`max-age=300`, no `includeSubDomains`/`preload`) once the domain has run stably on HTTPS for a burn-in period — a deliberate later-milestone decision, not an oversight.
- Deleting/removing a project once published — no delete-project or delete-draft capability exists anywhere in this app today (confirmed by code search during the post-Milestone-23 maintenance pass); unpublishing is the only way to take a project out of public view. Tracked as a roadmap item — see `docs/ROADMAP.md`'s Backlog, "Recoverable project Trash."

---

## 15. Related documentation

- [`docs/CI.md`](CI.md) — what runs automatically, what still needs manual/browser verification, and how to run the same checks locally
- [`docs/DISCORD_SETUP.md`](DISCORD_SETUP.md) — full Discord account-linking configuration, troubleshooting, and manual test procedure
- [`docs/AUTH_ARCHITECTURE.md`](AUTH_ARCHITECTURE.md) — the auth/profile/RLS model referenced in §7
- [`docs/STORAGE_ARCHITECTURE.md`](STORAGE_ARCHITECTURE.md) — Storage bucket layout and access policy referenced in §7
