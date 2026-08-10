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

Cloudflare Pages serves the static files from its configured output directory without transforming them. The developer and CI directories are kept out of production through the build command and a WAF rule described in §§3 and 5. `tools/ci/package.json` exists only for CI's own tooling (Playwright, for the browser test suite) and is deliberately kept out of the repository root so Cloudflare Pages' root-directory build detection never sees it; see `docs/CI.md`.

Supabase provides everything server-side: Auth (including Discord's native OAuth identity-linking), the PostgreSQL database, Storage for images, RPC functions, and Row Level Security as the access-control layer on every table. The frontend talks to Supabase directly from the browser using a publishable client key — see §7.

---

## 3. Cloudflare Pages configuration

| Setting | Value |
|---|---|
| Framework preset | None |
| Build command | `rm -rf tests tools .github .claude` |
| Build output directory | `/` (repository root) |
| Root directory | `/` (repository root) |
| Production branch | `main` |

The build command isn't building anything — it removes the developer/CI-only directories (`tests/`, `tools/`, `.github/`, `.claude/`) from each new deployment's copy of the repository before Cloudflare Pages publishes it. This only affects Cloudflare's own temporary deployment copy — it doesn't delete anything from GitHub or from any local development environment. Cloudflare's build-watch exclusions are a separate setting that only controls whether a commit triggers a new build; they don't remove anything from what's already published, which is why the `rm -rf` build command above is the mechanism that actually performs the pruning.

A Cloudflare WAF custom rule, **"Block developer and CI paths,"** additionally blocks requests to the `tests/`, `tools/`, `.github/`, and `.claude/` path prefixes at the edge — a second, independent layer on top of the build command. This protects against legacy Pages assets that may remain distributed temporarily (for example, cached at a specific edge location from a deployment made before the build command was corrected), not just new deployments going forward.

**Read-only production checks performed for this task confirm these two layers separately, since a 403 from the WAF rule alone can't prove anything about what the deployment copy itself contains — the WAF intercepts a request before Cloudflare Pages would ever get to answer it.**

- **Pruning layer:** confirmed by the fresh production deployment's own build log, which showed `rm -rf tests tools .github .claude` executing successfully. Before the WAF rule below was enabled, cache-busted requests for representative tracked files from all four directories returned `404` — supporting that those files were genuinely absent from that deployment's published copy, not just cached-and-then-blocked.
- **WAF layer:** confirmed afterward, once the rule was enabled — representative plain and cache-busted requests across all four path prefixes consistently returned `403`, with Cloudflare's own generic block page as the response body in every case, never the original file content.
- The production homepage remained available at `200` throughout both rounds of checking.

Together these are two independent pieces of evidence for two independent mechanisms, not one check standing in for both. Neither round tested every file under every directory — only representative tracked files.

`design-system.html` (an unlinked internal style-guide page) is deliberately **not** pruned — it's harmless to publish and is already covered by `robots.txt`'s disallow list (§10).

---

## 4. Branch, deployment, and preview flow

- **Production branch:** `main`. A push to `main` triggers an automatic Cloudflare Pages build and deploy — no manual "deploy" step exists or is needed.
- **Preview deployments:** other branches and pull requests receive their own automatically-generated preview URL. This has been observed working in this repository. Use a preview deployment to sanity-check a change — especially anything touching Storage or auth — before it reaches production.
- Both the initial GitHub repository connection and the initial Cloudflare Pages project connection have already been completed; this document doesn't re-describe them as pending setup.

---

## 5. Published and excluded content

**Intended to be published:** `index.html`, `404.html`, `robots.txt`, `sitemap.xml`, `manifest.webmanifest`, `_headers`, `pages/**`, `css/**`, `js/**`, `assets/**`, `design-system.html`, and `supabase/**` (the SQL migration/rollback source). These SQL files are not executable by a static host and publishing them does not grant any database access — the live database is reachable only through Supabase's own API surface, governed by RLS, entirely independent of whether its schema source is publicly readable. They aren't secret; they simply document schema history.

**Pruned before publishing:** `tests/` (the browser-based regression suite), `.claude/` (local dev tooling), `tools/` (CI scripts and CI-only `package.json`), `.github/` (the CI workflow definition). Removed from each new deployment's published copy by the build command in §3, with a Cloudflare WAF rule additionally blocking those four path prefixes at the edge as a second, independent layer — see §3 for the separate deployment-log and HTTP evidence behind each.

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
3. Open the three-dot actions menu for the desired previous production deployment, select **Rollback to this deployment**, and confirm.
4. Once confirmed, the selected deployment becomes production immediately—no rebuild or git operation is required. Cloudflare's deployment history is independent of git history; a bad deploy can be undone without touching the repository.

This describes Cloudflare Pages' documented rollback **capability**. **No live rollback drill has been performed and is not claimed here** — see §13. Reverting through git (`git revert` on the bad commit and pushing the resulting commit to `main`) is a separate, slower path that triggers a brand-new build rather than instantly restoring a prior one; the dashboard rollback above is the faster option for an active incident.

---

## 13. Remaining operational checks

Genuinely open items — nothing here is marked complete without evidence:

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
