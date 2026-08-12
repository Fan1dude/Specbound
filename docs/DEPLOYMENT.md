# Deployment

This is Specbound's current production deployment and operations guide — how the site is hosted, how a change reaches production, and what to check before and after a deploy. It reflects the live site, not a milestone-in-progress snapshot.

---

## 1. Purpose and current production state

- **Production URL:** https://specboundapp.com
- **Production branch:** `main`
- **Hosting:** Cloudflare Pages, deploying directly from this GitHub repository
- **Architecture:** static HTML/CSS/JavaScript — no framework, no bundler, no root-level application build step

The site is live, HTTPS is active, and Cloudflare preview deployments on pull requests have been observed working. Supabase Auth's Site URL, Redirect URLs, and Discord provider are configured for this domain, and the Discord account-linking flow has been manually verified end-to-end in production (see §9). This document does not claim every operational item below is finished — §14 lists what's genuinely still open.

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

`design-system.html` (an unlinked internal style-guide page) is deliberately **not** pruned — it's harmless to publish and is already covered by `robots.txt`'s disallow list (§11).

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

**HSTS (`Strict-Transport-Security`) is not currently present** in `_headers`, and a live header check today confirmed it's absent from the production response — consistent with the repository's own documented decision to add it only after the domain has run correctly on HTTPS for a burn-in period, since HSTS is hard to undo quickly once browsers cache it. See §14.

---

## 7. Supabase and authentication configuration

**Public client configuration** (safe to commit, safe for client-side exposure): `js/core/config.js` hardcodes the Supabase project URL and a *publishable* client key (Supabase's `sb_publishable_...` format, not a service-role key). This document intentionally does not reproduce that key's literal value — see `docs/AUTH_ARCHITECTURE.md` and `docs/STORAGE_ARCHITECTURE.md` for the RLS model this configuration relies on. **Never commit a service-role key, a Discord Client Secret, an access token, or any other credential to this repository.**

**Current Supabase Auth configuration** (per the verified starting state for this task — not re-inspected in the live dashboard during this documentation task):

- **Site URL:** `https://specboundapp.com` — this is the single highest-consequence setting in this whole document if it's ever wrong. Password-reset and signup-confirmation emails embed a link back to whatever URL is configured here; the signup confirmation flow in particular has no explicit `redirectTo` in this repo's code, so it relies entirely on this setting.
- **Redirect URLs** includes `https://specboundapp.com/pages/settings.html` — the exact URL `js/pages/settings/app.js` passes as `redirectTo` when a user links Discord (`window.location.href` at the moment "Connect Discord" is clicked). The password-reset flow (`js/pages/forgotPassword/app.js`) builds its own `redirectTo` dynamically from the current origin, so it doesn't require a separate allowlist entry beyond the Site URL itself.
- **Discord provider:** enabled, with manual identity linking enabled (`GOTRUE_SECURITY_MANUAL_LINKING_ENABLED`) — required for `supabase.auth.linkIdentity()` to attach Discord to an already-signed-in account rather than only supporting first-time sign-in.

No RLS, storage policy, or schema change is required as part of deployment — those are managed through this repository's tracked migrations (`supabase/migrations/`, currently 36 files, `0000`–`0035`) and applied independently via the Supabase CLI, not through Cloudflare Pages. Repository presence of a migration file is not the same fact as production application. As of the Milestone 23 production deployment (2026-08-12), **production's migration history matches local through `0035`** — `supabase migration list --linked` confirmed all 36 migrations present on both sides, and a `supabase db push --linked --dry-run` afterward reported production up to date. `0034` had, in fact, already been applied before that deployment's own preflight even started (this document previously said otherwise — see `supabase/migrations.md`'s `0034` entry for that discrepancy); `0035` was the one genuinely pending migration, applied as part of that deployment.

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

- **`robots.txt`:** disallows `/pages/settings.html`, `/pages/workshop.html`, `/pages/notifications.html`, `/pages/login.html`, `/pages/signup.html`, `/pages/build/edit.html`, `/design-system.html`, and `/tests/` (all account-specific, private, or developer-only — no public SEO value); references `sitemap.xml` at `https://specboundapp.com/sitemap.xml`. A live fetch today confirmed the repository's own rules are served intact, but Cloudflare additionally injects a "Managed content" block ahead of them — AI-crawler-specific `Disallow` rules (GPTBot, CCBot, Bytespider, etc.) and a `Content-Signal` directive — that isn't present in this repo's committed file. This is Cloudflare account/zone-level behavior, not something `robots.txt`'s source controls.
- **`sitemap.xml`:** 13 URLs today — confirmed both from the repository file and a live fetch, all using `https://specboundapp.com`: the homepage, Explore, Search, the 6 category pages, and the 4 legal pages. Individual build/profile pages are deliberately excluded (dynamic, numerous, already reachable via internal links). This count isn't pinned as a permanent constant — verify it directly (`grep -c "<loc>" sitemap.xml`) rather than trusting a frozen number if this file changes later.
- **`manifest.webmanifest`:** references three icon sizes (32×32, 192×192, 512×512), all present under `assets/brand/logo/`. Confirmed identical between the repository file and a live fetch. Not a full PWA (no service worker).
- **Favicons:** `index.html` and `404.html` link PNG favicons at 16×16, 32×32, and 48×48, plus an `apple-touch-icon`. `assets/brand/logo/favicon.svg` exists in the repository but is **not** linked from any page `<head>` as an active favicon today — if a future page adds an SVG favicon link, update this section rather than assuming it already exists.
- **`404.html`:** a custom branded page, correctly returned for a nonexistent path — confirmed live today (`404` status, the actual custom page content, not Cloudflare's generic default). It also sets `<meta name="robots" content="noindex">`. No custom 500 page exists or is needed — this architecture has no server-side code path that could produce one; Supabase-layer failures are handled by the app's own client-side error UI.
- **Open Graph / Twitter Card image:** `assets/brand/og/og-image.png` (1200×630), the single generic image used by every page including dynamic ones. This app has no server-side rendering, so a static HTML template cannot emit a different image per build — a disclosed limitation, not an oversight.

---

## 12. Deployment verification

Kept deliberately separated by who or what actually performs each check, so nothing gets assumed covered by a layer that doesn't actually cover it.

**Automated, on every push and pull request (GitHub Actions, `.github/workflows/ci.yml`):** JavaScript syntax validation, local reference checking, accessibility regressions, CSP/bootstrap validation, production-domain validation, and the browser-based regression suite under `tests/*.test.html`. See `docs/CI.md` for exactly what each covers and its known limitations. **GitHub Actions does not run the SQL migration/RLS policy tests** — those live under `supabase/tests/` and require a separate, disposable local Supabase/Docker stack (`supabase db reset --local`); they are not part of this CI pipeline.

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

---

## 14. Remaining operational checks

Genuinely open items — nothing here is marked complete without evidence:

- SMTP/email provider configuration for production traffic — Supabase's default email service has strict rate limits, not recommended at scale. Not verified in this task.
- Confirming the Supabase project's backup/point-in-time-recovery tier. Not verified in this task.
- A real production password-reset email test, confirming the emailed link resolves to `https://specboundapp.com`.
- A real rollback drill (§13) — capability is documented, a live test is not.
- Cross-browser/cross-device manual checks — not currently covered by any automated or manual process beyond ad hoc spot checks during development.
- Revisiting HSTS (§6) once the domain has run stably on HTTPS for a burn-in period.
- Deleting/removing a project once published — no delete-project or delete-draft capability exists anywhere in this app today (confirmed by code search during the post-Milestone-23 maintenance pass); unpublishing is the only way to take a project out of public view. Tracked as a roadmap item — see `docs/ROADMAP.md`'s Backlog, "Recoverable project Trash."

---

## 15. Related documentation

- [`docs/CI.md`](CI.md) — what runs automatically, what still needs manual/browser verification, and how to run the same checks locally
- [`docs/DISCORD_SETUP.md`](DISCORD_SETUP.md) — full Discord account-linking configuration, troubleshooting, and manual test procedure
- [`docs/AUTH_ARCHITECTURE.md`](AUTH_ARCHITECTURE.md) — the auth/profile/RLS model referenced in §7
- [`docs/STORAGE_ARCHITECTURE.md`](STORAGE_ARCHITECTURE.md) — Storage bucket layout and access policy referenced in §7
