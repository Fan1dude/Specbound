# Deployment

**Status: current and accurate as of Phase 9D implementation, 2026-07-27.** Hosting platform: **Cloudflare Pages** (approved choice, see `docs/milestones/MILESTONE_9_PHASE_9D_ARCHITECTURE.md` §1.1 for the evaluated alternatives).

This document describes how Specbound is deployed to production. Where a step can only be performed by a human with Cloudflare/DNS/domain-registrar access, it's written as an instruction, not a claim that it's already been done.

---

## 1. Cloudflare Pages setup

Specbound is a static site with **no build step** — no bundler, no `package.json`, every file in the repo (minus a couple of exclusions below) is served exactly as committed.

**One real "build command" is needed anyway**, not to build anything, but to keep two developer-only directories out of the live deployment. Cloudflare Pages has **no `.pagesignore`-style file-exclusion mechanism** for git-connected deployments (verified against Cloudflare's own documentation and community-confirmed as a known, longstanding gap — there is no built-in way to exclude files from what gets published). The workaround: a build command that deletes them before Pages publishes the directory.

### Project configuration (Cloudflare dashboard → Pages → Create a project → Connect to Git)

| Setting | Value |
|---|---|
| Framework preset | None |
| Build command | `rm -rf tests .claude` |
| Build output directory | `/` (repository root) |
| Root directory | `/` (repository root) |
| Production branch | `master` (or `main`, if renamed — see §2) |

The build command isn't building anything — it's pruning `tests/` (21 developer-only `*.test.html` files) and `.claude/` (local dev tooling, no secrets) from the published output before Cloudflare serves it. Both directories contain nothing sensitive (already confirmed repo-wide — no `.env`, no service-role key, no credentials anywhere), so this is tidiness, not a security fix; it just keeps test scaffolding off the public site and out of search-engine crawl budget.

`design-system.html` (an unlinked internal style-guide page) is **not** excluded from the deploy — it's harmless to publish (no sensitive content) and excluding it would need its own bespoke `rm` line for marginal benefit. It's already covered by `robots.txt`'s disallow list (§3 below) so it won't be crawled/indexed.

### What gets published

Everything else: `index.html`, `404.html`, `robots.txt`, `sitemap.xml`, `manifest.webmanifest`, `_headers`, `pages/**`, `css/**`, `js/**`, `assets/**`, `supabase/**` (SQL migration files — not executable by a static host, harmless to publish, but not linked from anywhere either), `design-system.html`.

## 2. Git branch and deployment flow

- **Production branch**: whichever branch is set as the Pages project's production branch (recommend `master`, the repo's current single branch — renaming to `main` is a purely cosmetic option, your call, not required).
- **Push to deploy**: every push to the production branch triggers an automatic Cloudflare Pages build+deploy. No manual "deploy" step exists or is needed.
- **Preview deployments**: every other branch or pull request gets its own automatically-generated preview URL (`<hash>.specbound.pages.dev`-style), live before anything merges to production. Use this to sanity-check a change — especially anything touching Storage/auth — before it reaches the real domain.
- **First deploy**: requires (a) a GitHub repository the local git history is pushed to, and (b) connecting that repository in the Cloudflare Pages dashboard. Both are actions you need to take — creating a remote repository and doing the first push are outside what this environment does unprompted (visible, shared-state actions), and connecting a Cloudflare account to a repo requires your own Cloudflare login.

## 3. Required public configuration

**No environment variables are required or used.** `js/core/config.js` hardcodes `SUPABASE_URL` and the publishable `SUPABASE_KEY` directly in a committed file — this is intentional and safe: the key is the new-format `sb_publishable_...` key, meant for client-side exposure, not a service-role key (see `docs/STORAGE_ARCHITECTURE.md`/`docs/AUTH_ARCHITECTURE.md` for the full security model this rests on). There is nothing to configure in Cloudflare Pages' "Environment variables" panel for this project to function.

Production assets already committed at the repo root, all verified locally (§7):

- `robots.txt` — disallows `/pages/settings.html`, `/pages/dashboard.html`, `/pages/workshop.html`, `/pages/notifications.html`, `/pages/login.html`, `/pages/signup.html`, `/pages/build/edit.html`, `/design-system.html`, `/tests/` (all account-specific/private or developer-only, zero public SEO value); references `sitemap.xml`.
- `sitemap.xml` — 13 URLs: homepage, Explore, Search, the 6 category pages, and the 4 legal pages. Individual build/profile pages are deliberately excluded (dynamic, numerous, already reachable via internal links — see `docs/milestones/MILESTONE_9_PHASE_9D_ARCHITECTURE.md` §2.2 for the reasoning).
- `manifest.webmanifest` — linked from every real page's `<head>`, referencing the two PNG icon sizes below. Not a full PWA (no service worker) — just closes the "missing manifest" gap cheaply.
- `assets/brand/logo/favicon.svg`, `favicon-32.png`, `favicon-192.png`, `apple-touch-icon.png` — SVG favicon (Phase 9C) plus PNG fallbacks for browsers/platforms that don't reliably support SVG favicons (notably Safari/iOS).
- `assets/brand/og/og-image.png` (1200×630) — the generic brand Open Graph/Twitter Card image used by every page, including dynamic ones (`build.html`, `profile.html`, `followers.html`, `following.html`, `pages/build/edit.html`). **This app has no server-side rendering**, so a single static HTML template cannot emit a different `og:image` per build — a real, disclosed limitation, not an oversight. See `docs/milestones/MILESTONE_9_PHASE_9D_ARCHITECTURE.md` §2.5.
- `404.html` — custom branded 404 page, auto-detected by Cloudflare Pages (no configuration needed; Cloudflare looks for `404.html` at the deployment root and any matching subdirectory).
- `_headers` — CSP and security headers (§5 below). **No 500 page exists or is planned** — this architecture has no server-side code path that could produce one; Supabase-layer failures are already handled by the app's own client-side toast/error UI.

### The `https://specbound.app` placeholder

Every canonical URL, `og:url`, and the `Sitemap:`/URLs inside `sitemap.xml` use `https://specbound.app` as a placeholder domain, since no real production domain was confirmed at implementation time. **Before going live, replace every occurrence with the real domain** — a single find-and-replace across the repo:

```bash
grep -rl "specbound.app" --include="*.html" --include="*.xml" --include="*.txt" . | xargs sed -i 's/specbound\.app/YOUR-REAL-DOMAIN/g'
```

Run this, review the diff, commit, and redeploy before announcing the site publicly. Everything else in this document and in the app itself is domain-agnostic.

## 4. Supabase production settings

No RLS, storage policy, or schema change is needed for deployment — that work is already complete (Migrations A/B/C; see `docs/STORAGE_ARCHITECTURE.md` and `docs/AUTH_ARCHITECTURE.md`). Two dashboard settings need updating once the real domain is known:

1. **Supabase dashboard → Authentication → URL Configuration → Site URL**: set to the real production domain.
2. **Authentication → URL Configuration → Redirect URLs**: add the production domain's relevant paths (at minimum, wherever `login.html`/`index.html` resolve on the real domain — these are the post-auth redirect targets used by `js/pages/signup/app.js` and `js/pages/login/app.js`).

**This is the single highest-consequence item in this whole document if missed** — password-reset and signup-confirmation emails embed a link back to whatever URL is configured here. If it's still pointing at a dev/localhost value, those emails will silently send users to a broken link once the site goes live.

Two further Supabase settings are real open items but belong to **Phase 9E's launch checklist**, not deployment itself: SMTP/email provider configuration (Supabase's default email service has strict rate limits, not recommended for production traffic) and confirming the project's backup/point-in-time-recovery tier. Not addressed here — tracked separately.

## 5. Custom domain and DNS setup

1. In the Cloudflare Pages project, go to **Custom domains** and add the desired domain.
2. If the domain's DNS is already on Cloudflare: it auto-configures. If not: Cloudflare provides the exact CNAME/nameserver instructions for your registrar — follow them there (this step requires access to whatever registrar/DNS provider is used, which is outside this environment).
3. Wait for DNS propagation and automatic SSL certificate provisioning (usually minutes, occasionally longer) — Cloudflare Pages handles both automatically once the domain is added and DNS points at it correctly.
4. Confirm the domain resolves and serves the site (`https://<domain>/` returns 200) before doing the Supabase Auth redirect URL update in §4 — that update needs the final, real domain.

## 6. HTTPS expectations

SSL is auto-provisioned and auto-renewed by Cloudflare Pages for both the `*.pages.dev` subdomain and any custom domain — no manual certificate management. HTTPS redirect is enforced by default. Confirm as part of every deployment verification pass (§8): a plain `http://` request to the production domain should redirect to `https://`.

Adding `Strict-Transport-Security` (HSTS) is deliberately **not** included in the initial `_headers` file — recommend adding it once the domain has run correctly on HTTPS for a short burn-in period, since HSTS is intentionally hard to undo quickly (browsers cache it aggressively) and it's safer to confirm DNS/domain setup is fully correct first.

## 7. Rollback procedure

Cloudflare Pages keeps every deployment. To roll back:

1. Cloudflare dashboard → Pages project → **Deployments** tab.
2. Find the last known-good deployment in the list.
3. Click **Retry deployment** / use the "..." menu → **Rollback to this deployment** (exact label may vary slightly by dashboard version).
4. This takes effect immediately — no rebuild, no waiting, no git operation required. Git history and Cloudflare's deployment history are independent; a bad deploy can be undone without touching the repository at all.

This directly closes the **L3 rollback plan** gap flagged in the original Milestone 9 audit (`docs/milestones/MILESTONE_9_ARCHITECTURE.md`).

## 8. Cache invalidation

**No manual cache invalidation step exists or is needed in normal operation.** Cloudflare Pages automatically invalidates its edge cache as part of every deployment — a new deploy's assets are live immediately, not gradually replacing a stale cached copy.

This app deliberately does **not** set custom long-lived `Cache-Control` headers on JS/CSS/assets via `_headers`, despite having no content-hashed/versioned filenames. This was a real correction made during implementation: Cloudflare's own documentation explicitly recommends *against* adding custom caching rules on a custom domain, because doing so can cause stale assets to be served after a deployment — the custom-domain traffic path applies standard HTTP caching semantics to whatever `Cache-Control` you set, independent of Cloudflare Pages' own deployment-aware cache invalidation. Since nothing in this app has a hashed filename (no bundler), setting an aggressive `max-age` would reintroduce exactly the staleness risk Cloudflare's own default behavior already avoids. **The correct, safest approach for this app's shape is to not override caching at all** and rely on Cloudflare Pages' built-in behavior — which is what `_headers` does (security headers only, no `Cache-Control` line).

If a caching issue is ever suspected despite this (e.g. a Cloudflare-side incident), the dashboard exposes a manual **Purge Cache** action under Caching as a fallback — not expected to be needed in normal operation.

## 9. Post-deployment smoke tests

Run after the first production deploy, and after every deploy that touches anything listed:

1. Homepage loads, no console errors beyond expected/unrelated ones.
2. HTTPS enforced (`http://` → `https://` redirect).
3. `/robots.txt` returns the expected disallow list.
4. `/sitemap.xml` returns valid XML with the 13 expected URLs, each resolving 200.
5. `/manifest.webmanifest` returns valid JSON; both icon URLs resolve 200.
6. Favicon (SVG) and the PNG fallback both resolve with correct `Content-Type`.
7. Request a nonexistent URL — confirm the custom `404.html` renders (not Cloudflare's generic default).
8. Open browser console on: homepage, Explore, a build page, Login, Signup, the editor, Settings — confirm **zero CSP violation errors** on any of them (a CSP violation is silent in the UI but appears as a `Refused to ...` console error).
9. View-source (not the rendered DOM) on a sample of pages — confirm `<title>`, `<meta name="description">`, and the `og:*`/`twitter:*` tags are present in the raw HTML response, since social/search crawlers generally don't execute this app's JS.
10. Trigger a real password-reset email against the production domain (a real or test account) — confirm the emailed link points at the production domain, not a dev/localhost URL.
11. Perform one real rollback test (§7): promote the previous deployment, confirm the site reverts, then re-promote forward again — proving the rollback plan works in practice, not just on paper.

## 10. Production environment verification checklist

One-time, before announcing the site publicly:

- [ ] `https://specbound.app` placeholder replaced with the real domain everywhere (§3)
- [ ] Cloudflare Pages project connected to the GitHub repo, build command/output directory set (§1)
- [ ] Custom domain added, DNS configured, SSL active (§5)
- [ ] Supabase Site URL and Redirect URLs updated to the real domain (§4)
- [ ] All 11 smoke tests in §9 pass
- [ ] Rollback tested once, live (§9.11)
- [ ] `robots.txt`/`sitemap.xml` reference the real domain, not the placeholder
- [ ] No secrets committed anywhere in the repo (already confirmed clean throughout this milestone; re-check `git log`/`git diff` for this deploy's changes specifically before pushing)
