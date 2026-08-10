# Deployment

This is Specbound's current production deployment and operations guide — how the site is hosted, how a change reaches production, and what to check before and after a deploy. It reflects the live site, not a milestone-in-progress snapshot.

---

## 1. Purpose and current production state

- **Production URL:** https://specboundapp.com
- **Production branch:** `main`
- **Hosting:** Cloudflare Pages, deploying directly from this GitHub repository
- **Architecture:** static HTML/CSS/JavaScript — no framework, no bundler, no root-level application build step

The site is live, HTTPS is active, and Cloudflare preview deployments on pull requests have been observed working. Supabase Auth's Site URL, Redirect URLs, and Discord provider are configured for this domain, and the Discord account-linking flow has been manually verified end-to-end in production (see §8). This document does not claim every operational item below is finished — §13 lists what's genuinely still open.

---

## 2. Architecture and hosting model

Every file in the repository (minus the exclusions in §5) is served exactly as committed — there is no build step transforming it. `tools/ci/package.json` exists only for CI's own tooling (Playwright, for the browser test suite) and is deliberately kept out of the repository root so Cloudflare Pages' root-directory build detection never sees it; see `docs/CI.md`.

Supabase provides everything server-side: Auth (including Discord's native OAuth identity-linking), the PostgreSQL database, Storage for images, RPC functions, and Row Level Security as the access-control layer on every table. The frontend talks to Supabase directly from the browser using a publishable client key — see §7.

---

## 3. Cloudflare Pages configuration

The repository documents the following as the **expected** Cloudflare Pages project configuration. This task did not inspect the live Cloudflare dashboard directly — confirm these values there rather than treating this table as independently re-verified today:

| Setting | Expected value |
|---|---|
| Framework preset | None |
| Build command | `rm -rf tests .claude tools .github` |
| Build output directory | `/` (repository root) |
| Root directory | `/` (repository root) |
| Production branch | `main` |

The build command isn't building anything — it's intended to prune developer/CI-only directories (`tests/`, `.claude/`, `tools/`, `.github/`) from the published output before Cloudflare serves it, since Cloudflare Pages has no `.pagesignore`-style file-exclusion mechanism for git-connected deployments (a known platform gap, not something this repo can configure around).

**Read-only production checks performed for this task show this pruning is not currently taking effect.** Fetching `https://specboundapp.com/tests/mobileAccountMenu.test.html`, `.../tools/ci/check-syntax.js`, and `.../.github/workflows/ci.yml` each returned real, live content, not a 404. None of the exposed files contain secrets — confirmed both by this repository's own no-secrets convention (no `.env`, no service-role key, no credentials anywhere in tracked files) and by `git ls-files .claude/`, which shows only `README.md`, `launch.json`, and `nocache_server.py` are actually tracked there (`.claude/settings.local.json` is git-ignored and was never pushed to GitHub, so Cloudflare never had it regardless of pruning). The practical impact today is low — dev/CI scaffolding and test pages are reachable but not secret-bearing — but the configured build command should be confirmed and corrected in the Cloudflare dashboard; see §13.

`design-system.html` (an unlinked internal style-guide page) is deliberately **not** pruned — it's harmless to publish and is already covered by `robots.txt`'s disallow list (§10).

---

## 4. Branch, deployment, and preview flow

- **Production branch:** `main`. A push to `main` triggers an automatic Cloudflare Pages build and deploy — no manual "deploy" step exists or is needed.
- **Preview deployments:** other branches and pull requests receive their own automatically-generated preview URL. This has been observed working in this repository. Use a preview deployment to sanity-check a change — especially anything touching Storage or auth — before it reaches production.
- Both the initial GitHub repository connection and the initial Cloudflare Pages project connection have already been completed; this document doesn't re-describe them as pending setup.

---

## 5. Published and excluded content

**Intended to be published:** `index.html`, `404.html`, `robots.txt`, `sitemap.xml`, `manifest.webmanifest`, `_headers`, `pages/**`, `css/**`, `js/**`, `assets/**`, `design-system.html`, and `supabase/**` (the SQL migration/rollback source). These SQL files are not executable by a static host and publishing them does not grant any database access — the live database is reachable only through Supabase's own API surface, governed by RLS, entirely independent of whether its schema source is publicly readable. They aren't secret; they simply document schema history.

**Intended to be pruned before publishing:** `tests/` (the browser-based regression suite), `.claude/` (local dev tooling), `tools/` (CI scripts and CI-only `package.json`), `.github/` (the CI workflow definition). As documented in §3, live checks today show this pruning is not currently in effect — these directories are reachable in production, though none contain secrets.

---

## 6. Production domain, DNS, and HTTPS

The production domain, `specboundapp.com`, is live and already connected to this Cloudflare Pages project — this document doesn't re-describe domain selection or first connection as future work.

A read-only check today confirmed: `http://specboundapp.com/` redirects to `https://specboundapp.com/` (200 after redirect), and a direct HTTPS request to the homepage returns 200. SSL is auto-provisioned and auto-renewed by Cloudflare Pages for both the production domain and the `*.pages.dev` subdomain — no manual certificate management.

**HSTS (`Strict-Transport-Security`) is not currently present** in `_headers`, and a live header check today confirmed it's absent from the production response — consistent with the repository's own documented decision to add it only after the domain has run correctly on HTTPS for a burn-in period, since HSTS is hard to undo quickly once browsers cache it. See §13.

---

## 7. Supabase and authentication configuration

**Public client configuration** (safe to commit, safe for client-side exposure): `js/core/config.js` hardcodes the Supabase project URL and a *publishable* client key (Supabase's `sb_publishable_...` format, not a service-role key). This document intentionally does not reproduce that key's literal value — see `docs/AUTH_ARCHITECTURE.md` and `docs/STORAGE_ARCHITECTURE.md` for the RLS model this configuration relies on. **Never commit a service-role key, a Discord Client Secret, an access token, or any other credential to this repository.**

**Current Supabase Auth configuration** (per the verified starting state for this task — not re-inspected in the live dashboard during this documentation task):

- **Site URL:** `https://specboundapp.com` — this is the single highest-consequence setting in this whole document if it's ever wrong. Password-reset and signup-confirmation emails embed a link back to whatever URL is configured here; the signup confirmation flow in particular has no explicit `redirectTo` in this repo's code, so it relies entirely on this setting.
- **Redirect URLs** includes `https://specboundapp.com/pages/settings.html` — the exact URL `js/pages/settings/app.js` passes as `redirectTo` when a user links Discord (`window.location.href` at the moment "Connect Discord" is clicked). The password-reset flow (`js/pages/forgotPassword/app.js`) builds its own `redirectTo` dynamically from the current origin, so it doesn't require a separate allowlist entry beyond the Site URL itself.
- **Discord provider:** enabled, with manual identity linking enabled (`GOTRUE_SECURITY_MANUAL_LINKING_ENABLED`) — required for `supabase.auth.linkIdentity()` to attach Discord to an already-signed-in account rather than only supporting first-time sign-in.

No RLS, storage policy, or schema change is required as part of deployment — those are managed through this repository's tracked migrations (`supabase/migrations/`, currently 34 files, `0000`–`0033`) and applied independently via the Supabase CLI, not through Cloudflare Pages. Repository presence of a migration file is not the same fact as production application; the most recent live preflight check (`supabase migration list --linked`) confirmed production's migration history matches local through `0033`.

---

## 8. Discord production configuration

Discord account linking (Settings → Connected Accounts) requires its own Supabase provider settings and a matching Discord Developer Portal redirect — the full checklist, troubleshooting table, and security notes live in **[`docs/DISCORD_SETUP.md`](DISCORD_SETUP.md)**; this section only records the current state, not the full procedure.

- **Discord hosted callback** (Discord Developer Portal → OAuth2 → Redirects): `https://xpxjqyraizntbtijzoyp.supabase.co/auth/v1/callback` — Supabase Auth's own fixed callback for this project, not the Specbound Settings page.
- **Settings return URL:** `https://specboundapp.com/pages/settings.html` (see §7).
- **Production verification:** the complete Discord flow has been manually tested successfully — connect and OAuth return, username synchronization, public visibility, the correct outbound Discord profile link, the privacy toggle, refresh, and disconnect with public removal. This documentation task did not repeat that test or modify either dashboard; it records the prior verified result.

---

## 9. Security headers and caching

Verified directly against `_headers` and a live response check today.

`_headers` sets, for every path (`/*`): `X-Content-Type-Options: nosniff`, `Referrer-Policy: strict-origin-when-cross-origin`, `Permissions-Policy: geolocation=(), microphone=(), camera=()`, and a `Content-Security-Policy` with no `unsafe-inline` and no wildcard origins — `script-src` allows only `'self'`, `https://cdn.jsdelivr.net`, and `https://static.cloudflareinsights.com`; `connect-src` allows only `'self'`, the Supabase project origin, and `https://cloudflareinsights.com`. The two `cloudflareinsights.com` entries exist for Cloudflare Pages' own Web Analytics beacon, which Cloudflare injects into HTML responses at the edge — it is not present anywhere in this repo's own source. A live header check today found those two allowances present on the homepage's CSP but absent from CSS/JS response CSPs, consistent with the beacon only ever loading in an HTML document context.

`/css/*` and `/js/*` additionally get `Cache-Control: public, max-age=0, must-revalidate`, forcing a conditional revalidation request on every load instead of relying on Cloudflare Pages' own default 4-hour browser cache — the default that previously caused an already-open browser tab to keep rendering pre-deploy CSS/JS for up to four hours after a new deploy went live. `must-revalidate` (not `no-store`) was chosen deliberately so an unchanged file can still return a cheap 304 instead of a full re-download; a live check today confirmed both CSS and JS responses carry a matching `ETag` and the expected `Cache-Control` value. Images and other static assets are intentionally left on Cloudflare's default caching — they change far less often. **HTML responses were also observed carrying the same `Cache-Control: public, max-age=0, must-revalidate` today**, even though `_headers` doesn't declare that for `/*` — likely a Cloudflare Pages platform default for document navigations rather than anything this repository configures; noted here as an observed fact, not independently diagnosed further.

Cloudflare also adds its own operational headers on every response (`CF-RAY`, `Server: cloudflare`, `NEL`/`Report-To`, a permissive `Access-Control-Allow-Origin: *`, `Speculation-Rules`) — expected platform behavior, not something `_headers` or this repository controls.

If a caching issue is ever suspected beyond what `_headers` already addresses, the Cloudflare dashboard exposes a manual **Purge Cache** action under Caching as a fallback.

---

## 10. SEO and public platform files

Verified directly against the repository source and, where noted, a live fetch today.

- **`robots.txt`:** disallows `/pages/settings.html`, `/pages/workshop.html`, `/pages/notifications.html`, `/pages/login.html`, `/pages/signup.html`, `/pages/build/edit.html`, `/design-system.html`, and `/tests/` (all account-specific, private, or developer-only — no public SEO value); references `sitemap.xml` at `https://specboundapp.com/sitemap.xml`. A live fetch today confirmed the repository's own rules are served intact, but Cloudflare additionally injects a "Managed content" block ahead of them — AI-crawler-specific `Disallow` rules (GPTBot, CCBot, Bytespider, etc.) and a `Content-Signal` directive — that isn't present in this repo's committed file. This is Cloudflare account/zone-level behavior, not something `robots.txt`'s source controls.
- **`sitemap.xml`:** 13 URLs today — confirmed both from the repository file and a live fetch, all using `https://specboundapp.com`: the homepage, Explore, Search, the 6 category pages, and the 4 legal pages. Individual build/profile pages are deliberately excluded (dynamic, numerous, already reachable via internal links). This count isn't pinned as a permanent constant — verify it directly (`grep -c "<loc>" sitemap.xml`) rather than trusting a frozen number if this file changes later.
- **`manifest.webmanifest`:** references three icon sizes (32×32, 192×192, 512×512), all present under `assets/brand/logo/`. Confirmed identical between the repository file and a live fetch. Not a full PWA (no service worker).
- **Favicons:** `index.html` and `404.html` link PNG favicons at 16×16, 32×32, and 48×48, plus an `apple-touch-icon`. `assets/brand/logo/favicon.svg` exists in the repository but is **not** linked from any page `<head>` as an active favicon today — if a future page adds an SVG favicon link, update this section rather than assuming it already exists.
- **`404.html`:** a custom branded page, correctly returned for a nonexistent path — confirmed live today (`404` status, the actual custom page content, not Cloudflare's generic default). It also sets `<meta name="robots" content="noindex">`. No custom 500 page exists or is needed — this architecture has no server-side code path that could produce one; Supabase-layer failures are handled by the app's own client-side error UI.
- **Open Graph / Twitter Card image:** `assets/brand/og/og-image.png` (1200×630), the single generic image used by every page including dynamic ones. This app has no server-side rendering, so a static HTML template cannot emit a different image per build — a disclosed limitation, not an oversight.

---

## 11. Deployment verification

Kept deliberately separated by who or what actually performs each check, so nothing gets assumed covered by a layer that doesn't actually cover it.

**Automated, on every push and pull request (GitHub Actions, `.github/workflows/ci.yml`):** JavaScript syntax validation, local reference checking, accessibility regressions, CSP/bootstrap validation, production-domain validation, and the browser-based regression suite under `tests/*.test.html`. See `docs/CI.md` for exactly what each covers and its known limitations. **GitHub Actions does not run the SQL migration/RLS policy tests** — those live under `supabase/tests/` and require a separate, disposable local Supabase/Docker stack (`supabase db reset --local`); they are not part of this CI pipeline.

**Safe public endpoint checks (no sign-in, no state change) — performed for this documentation task, results above:** homepage HTTPS/200, HTTP→HTTPS redirect, `robots.txt`, `sitemap.xml`, `manifest.webmanifest`, a nonexistent-path 404, and response headers on an HTML/CSS/JS sample. These are safe to repeat at any time.

**Manual signed-in smoke tests — not performed by this documentation task, and not to be inferred as passing from the checks above:**
- Homepage, Explore, a build page, Login, Signup, the editor, and Settings load with zero CSP violation console errors
- View-source on a sample of pages shows `<title>`, `<meta name="description">`, and `og:*`/`twitter:*` tags in the raw HTML response
- A real password-reset email test against production, confirming the emailed link points at `https://specboundapp.com`

**Already completed, recorded here as verified (not re-performed today):** the full Discord production test in §8.

**Human dashboard checks — cannot be performed from this environment:** confirming the live Cloudflare Pages build/output/pruning settings actually match §3; confirming Supabase's Site URL/Redirect URLs/Discord provider match §7 by looking at the dashboard directly rather than relying on the verified starting state.

---

## 12. Rollback procedure

Cloudflare Pages retains every deployment. To roll back:

1. Cloudflare dashboard → Pages project → **Deployments** tab.
2. Find the last known-good deployment.
3. Use **Rollback to this deployment** (or "Retry deployment" — exact label may vary by dashboard version).
4. Takes effect immediately — no rebuild, no waiting, no git operation required. Cloudflare's deployment history is independent of git history; a bad deploy can be undone without touching the repository.

This describes Cloudflare Pages' documented rollback **capability**. **No live rollback drill has been performed and is not claimed here** — see §13. Reverting through git (reverting or resetting a commit on `main` and pushing) is a separate, slower path that triggers a brand-new build rather than instantly restoring a prior one; the dashboard rollback above is the faster option for an active incident.

---

## 13. Remaining operational checks

Genuinely open items — nothing here is marked complete without evidence:

- **Confirm and, if needed, correct the live Cloudflare Pages build command.** §3's read-only checks today show `tests/`, `.claude/`, `tools/`, and `.github/` are currently reachable in production, contradicting the documented pruning behavior. No secrets are exposed by this, but the dashboard setting should be checked and fixed.
- SMTP/email provider configuration for production traffic — Supabase's default email service has strict rate limits, not recommended at scale. Not verified in this task.
- Confirming the Supabase project's backup/point-in-time-recovery tier. Not verified in this task.
- A real production password-reset email test, confirming the emailed link resolves to `https://specboundapp.com`.
- A real rollback drill (§12) — capability is documented, a live test is not.
- Cross-browser/cross-device manual checks — not currently covered by any automated or manual process beyond ad hoc spot checks during development.
- Revisiting HSTS (§6) once the domain has run stably on HTTPS for a burn-in period.

---

## 14. Related documentation

- [`docs/CI.md`](CI.md) — what runs automatically, what still needs manual/browser verification, and how to run the same checks locally
- [`docs/DISCORD_SETUP.md`](DISCORD_SETUP.md) — full Discord account-linking configuration, troubleshooting, and manual test procedure
- [`docs/AUTH_ARCHITECTURE.md`](AUTH_ARCHITECTURE.md) — the auth/profile/RLS model referenced in §7
- [`docs/STORAGE_ARCHITECTURE.md`](STORAGE_ARCHITECTURE.md) — Storage bucket layout and access policy referenced in §7
