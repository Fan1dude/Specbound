# Milestone 9 — Phase 9D: Deployment Preparation — Architecture Proposal

**Status: Architecture only. No implementation. Awaiting approval.**

**Method:** Grounded in the actual current repo state, re-verified fresh for this proposal (not assumed from the earlier Milestone 9 audit): confirmed zero inline `<script>` blocks, zero inline event-handler attributes, and zero inline `style="..."` attributes anywhere in the 25 real app pages (`design-system.html`, an unlinked internal dev page, is the only file with any inline styling — 8 occurrences); the complete external-domain surface is exactly `cdn.jsdelivr.net` (pinned Supabase client), the Supabase project's own domain (API/Auth/Storage), and Google Fonts (`fonts.googleapis.com`/`fonts.gstatic.com`) — `github.com`/`youtube.com` appear only as profile-field link *targets* (`<a href>`), never loaded resources; confirmed only 4 of 29 HTML files have any `<meta name="description">` and **zero** have any Open Graph or Twitter Card tag; confirmed git has no remote configured yet and sits on a single `master` branch; confirmed `robots.txt`, `sitemap.xml`, `manifest.json`, any hosting config file (`vercel.json`/`netlify.toml`/`_headers`/`_redirects`/`.htaccess`), and any custom error page are all still absent.

This grounding matters because it changes what's actually *possible* here, not just what's convenient: a strict CSP with no `'unsafe-inline'` is realistic for this app today (most static sites accumulate inline scripts/styles over time and can't do this cleanly), and the caching strategy can be more aggressive than a naive "static site" default would suggest, because of how the recommended hosts handle deploys (see §3).

---

## 1. Production deployment architecture

### 1.1 Hosting platform — recommendation

**Recommend Cloudflare Pages**, with **Netlify** as an equivalent, fully-acceptable alternative if you have an existing preference. Both are evaluated against what this app actually needs — nothing more:

| Requirement | Why it matters here | Cloudflare Pages | Netlify | Vercel | GitHub Pages | S3 + CloudFront |
|---|---|---|---|---|---|---|
| Serves static files as-is, no build step | Confirmed: no `package.json`, no bundler anywhere | ✅ | ✅ | ✅ | ✅ | ✅ |
| Git-based deploy (push → live) | Matches the just-established git baseline; no separate CI tooling to build/maintain | ✅ | ✅ | ✅ | ✅ | ❌ (needs a manual/CI upload step) |
| Custom cache-header control (`_headers`-style file) | §3's caching strategy needs per-path `Cache-Control` | ✅ native | ✅ native | ✅ (`vercel.json`) | ❌ (no native per-path header control) | ✅ (manual, per-object) |
| Auto SSL on custom domain | §1.6/§3 HTTPS requirement | ✅ auto | ✅ auto | ✅ auto | ✅ auto (slower provisioning) | ⚠️ manual (ACM + CloudFront config) |
| Every deploy is atomic + instantly reversible | Directly answers the still-open **L3 rollback plan** from the original Milestone 9 audit | ✅ (re-promote any prior deployment, seconds) | ✅ (same model) | ✅ (same model) | ⚠️ (revert = new commit + wait for rebuild) | ❌ (no built-in concept of this) |
| Deploy previews per branch/PR | Lets a change be checked live before it touches production | ✅ | ✅ | ✅ | ❌ | ❌ |
| Free tier fits a public community site | No production traffic yet; unknown growth curve | ✅ unlimited bandwidth | ✅ generous, capped bandwidth | ✅ generous, capped bandwidth | ✅ generous | ❌ pay-per-request/egress from day one |
| Ongoing operational burden | Nobody is maintaining infrastructure full-time here | Low | Low | Low | Low | High (you own the CDN config) |

Cloudflare Pages edges out Netlify only on uncapped bandwidth and raw edge-network size — for this app's current scale either is genuinely fine, and if you already have a Netlify/Vercel account or preference, that's a completely reasonable substitution with no changes needed elsewhere in this plan (the `_headers` file format in §3.2 is Netlify/Cloudflare-Pages-compatible as written; Vercel would need the same rules translated into `vercel.json`'s `headers` array). GitHub Pages and S3+CloudFront are both ruled out primarily by the caching/rollback requirements this phase explicitly asks for — not because they couldn't serve the site at all.

**This is the one decision in this document that gates several others below (env var strategy, `_headers` syntax, rollback mechanics) — confirming it first is worth doing before the rest of 9D is implemented, even though the whole document is being submitted together for review.**

### 1.2 Deployment pipeline

1. **GitHub repository.** The local repo (`master` branch, one baseline commit + one Phase 9C commit, no remote) needs a remote. Creating the actual GitHub repository and doing the first push are user-confirmed actions during implementation, not something to pre-decide here — flagging now so it isn't a surprise mid-implementation.
2. **Host project setup.** Connect Cloudflare Pages (or the chosen alternative) to that GitHub repo. Build command: none (empty/no-op). Output/publish directory: repository root (`.`) — no `dist/`, no build artifact directory exists or is needed.
3. **Push-to-deploy.** Every push to the production branch (see §1.5) triggers an automatic deploy; every push to any other branch/PR gets its own preview URL, live before merge.
4. **Exclusions from the deployed output.** `tests/*.test.html` (21 files) and `.claude/` are developer-only and should not ship to production — not a security risk (nothing sensitive in them; already confirmed no secrets anywhere in the repo), but they're dead weight and `tests/*.test.html` could confuse a crawler or a curious visitor poking at URLs. Handled via the host's ignore/exclude config (Cloudflare Pages and Netlify both support a `.pagesignore`/build-ignore mechanism, or simply excluding `tests/` from what gets pushed to the deploy branch) — exact mechanism is an implementation detail to work out with whichever host is confirmed, not a blocker to approving this plan. `design-system.html` (unlinked internal style-guide page, per the original Milestone 9 audit's D10) is left as-is per that finding's "no action needed" resolution — low stakes either way, not part of this phase's scope to revisit.

### 1.3 Production environment variables

This app has **no build-time variable injection today** — `js/core/config.js` hardcodes `SUPABASE_URL` and `SUPABASE_KEY` directly in a committed file, because there's no bundler to substitute values at build time. Per the original audit's L5 finding, this is acceptable *in principle* since `SUPABASE_KEY` is the new-format `sb_publishable_...` key — safe for client-side exposure, confirmed not a service-role key, no secret material.

**Recommendation: keep it exactly as-is — no environment-variable mechanism needed** — unless you want a genuinely separate staging Supabase project (a second project with its own schema/RLS/storage bucket, fully mirroring the migrations in `supabase/migrations/`). That would be a much larger undertaking (re-running all 18 migrations against a second project, keeping both in sync going forward) and nothing in this milestone's scope suggests it's wanted. If a staging split is ever desired later, the lightest-weight approach for a zero-build static site is a one-line build-time find/replace (host build command becomes e.g. `sed` swapping a placeholder token using a host-level environment variable) rather than introducing a bundler just for this.

### 1.4 Production Supabase configuration

The only Supabase-side changes this phase requires are dashboard settings, not schema/RLS (that work is already complete — see `docs/STORAGE_ARCHITECTURE.md` and `docs/AUTH_ARCHITECTURE.md`):

- **Site URL**: update from whatever dev/localhost value is currently set to the real production domain.
- **Auth redirect URLs (allow-list)**: add the production domain's relevant callback paths (password-reset, email-confirmation redirect targets — currently `login.html`/`index.html` per `js/pages/signup/app.js` and `js/pages/login/app.js`). This was flagged as **L7** in the original audit: if missed, password-reset and signup-confirmation emails will link back to a dev URL and silently fail for real users. This is the single highest-consequence item in this whole phase if forgotten.
- No RLS, storage policy, or bucket-configuration change of any kind — those are already correct and verified (Migrations A/B/C, S1–S3 resolutions).
- SMTP/email provider configuration (**L9** from the original audit) and Supabase backup/PITR tier (**L4**) are real open items but belong to **Phase 9E's launch checklist**, not this phase — they're account/dashboard settings unrelated to *deployment* specifically, and grouping them here would blur the phase boundary the milestone plan already drew.

### 1.5 Branch strategy

Repo currently has one branch (`master`) and no remote. Recommendation, sized to this project's actual current scale (effectively solo development):

- Treat `master` as the production branch (rename to `main` first if you'd like to match the modern GitHub default — purely cosmetic, zero functional difference, your call, not worth deliberating further).
- The production branch auto-deploys to the live site on every push.
- Any other branch or PR gets an automatic preview deployment (free with the recommended hosts) — use this as the "does this actually work" check before merging, especially for anything touching Storage/auth given how much careful verification that subsystem already required this milestone.
- No separate long-lived "staging" branch/environment is recommended unless a second Supabase project is provisioned (see §1.3) — a staging *branch* with no staging *backend* would just be a preview deploy pointed at production data, which the automatic PR-preview mechanism already gives you for free without a dedicated branch.

### 1.6 Deployment verification process

Every deploy (first production deploy and every one after) should pass this sequence before being considered done — this is the process; the exact checklist items live in §5 and in the `DEPLOYMENT.md` draft below so they're not defined twice:

1. Confirm the deploy succeeded (host dashboard shows the new deployment live, no build/deploy error).
2. Run the smoke-test checklist (§5 / `DEPLOYMENT.md` §7) against the **production URL**, not a preview URL — signed URLs, auth redirects, and CORS-adjacent behavior can differ subtly between preview and production domains.
3. Confirm HTTPS is enforced (plain `http://` request redirects to `https://`).
4. Confirm the previous deployment is still available to instantly re-promote if anything above fails — this *is* the rollback plan (§1.1, **L3** from the original audit), and confirming it works costs nothing since the recommended hosts do this by default.

---

## 2. Production assets

### 2.1 `robots.txt`

Plan (final content to be written at implementation time, reflecting whatever domain is live):

```
User-agent: *
Disallow: /pages/settings.html
Disallow: /pages/dashboard.html
Disallow: /pages/login.html
Disallow: /pages/signup.html
Disallow: /tests/
Disallow: /design-system.html

Sitemap: https://<production-domain>/sitemap.xml
```

Rationale: `settings.html`/`dashboard.html` are account-specific with no standalone SEO value and nothing there should be indexed against a specific user; `login.html`/`signup.html` have no content worth indexing (excluding them from crawl budget, not a security measure — RLS already governs actual access); `tests/` and `design-system.html` are developer-only. Everything else (homepage, Explore, category pages, individual build/profile pages, the legal "Coming Soon" pages) is left crawlable — the legal pages being "Coming Soon" placeholders doesn't need a `Disallow`, since they're honest about their own state per the already-approved 8D fix, not deceptive content that indexing would misrepresent.

### 2.2 `sitemap.xml`

Plan: a static, hand-maintained XML file listing only the pages that are (a) genuinely public, (b) stable in count, and (c) worth search-engine discovery priority — homepage, `explore.html`, `search.html`, the 6 category pages, and the 4 legal pages. **Individual build pages and profile pages are deliberately excluded from this static file** — they're numerous, dynamic, and already reachable via normal internal links (Explore, Search, category pages all link to them), which is sufficient for crawling without a sitemap entry per build. A dynamically-generated sitemap covering every build/profile would require server-side generation this architecture doesn't have (no backend beyond Supabase) — noted as a known, accepted limitation, not a blocker; internal linking already covers discoverability for that content.

### 2.3 Web app manifest

Per the original audit's **B9** finding: nothing in this app currently signals that "Add to Home Screen"/PWA installability is an actual product goal (no `<link rel="manifest">` anywhere, no service worker, no install prompt handling). **Recommendation: skip unless you specifically want it** — a manifest with no accompanying service worker gives limited practical benefit (some browsers will still offer a basic "add to home screen" affordance, but without a service worker there's no offline support or the fuller PWA experience). If you do want it, it's cheap to add (a static `manifest.json` referencing the already-fixed `favicon.svg` plus a couple of PNG icon sizes, and one `<link rel="manifest">` line per page) — flagging as optional, your call, not defaulting to building it.

### 2.4 Favicon verification

The favicon itself was already fixed in Phase 9C (the 0-byte `favicon.svg` was replaced with a real icon, verified live). This phase's remaining favicon work is narrower:

- Confirm the fix survives deployment (correct `Content-Type: image/svg+xml`, no caching artifacts from a host that might handle SVG differently than the dev server did).
- **Recommend adding a PNG fallback** (`favicon-32.png`/`favicon-192.png` or similar) plus an `apple-touch-icon` link — Safari/iOS and some older browser/OS combinations don't reliably support SVG favicons, so an SVG-only icon can still show a blank/default icon on those platforms even though the SVG itself is now valid. This is a small, self-contained addition, not a re-opening of the already-closed P1 finding.

### 2.5 Metadata review

**New finding, not previously surfaced in the Milestone 9 audit**: only 4 of 29 HTML files (`index.html`, `pages/explore.html`, `pages/search.html`, `pages/build/build.html`) have any `<meta name="description">` at all, and **zero pages** — including those 4 — have any Open Graph (`og:*`) or Twitter Card (`twitter:*`) tag. Practically, this means every link to this app shared on Discord, Slack, X/Twitter, or any messaging app that generates a link preview currently renders as a bare URL with no title, description, or image — a real first-impression gap for a platform whose whole purpose is sharing build progress.

Plan:
- Add a unique, real `<title>` and `<meta name="description">` to every page currently missing one (most already have a `<title>`; the gap is specifically the description).
- Add a baseline Open Graph set (`og:type`, `og:title`, `og:description`, `og:url`, `og:image`) and matching Twitter Card tags (`twitter:card` = `summary_large_image`, `twitter:title`, `twitter:description`, `twitter:image`) to at minimum: the homepage, `explore.html`, and — highest value — individual build pages (`pages/build/build.html`), since those are what actually gets shared.
- **Known limitation, accepted rather than solved**: `og:image` needs a real image URL, and this app has no server-side rendering or image-generation service to produce a per-build preview image dynamically. Two honest options: (a) use each build's own cover image directly as `og:image` where one exists (client-side-rendered pages can still emit static meta tags server-side... except this app has no server — the meta tags in the HTML `<head>` are static per the page template, not per-build, since the build's own data loads client-side via JS after the page is served). This is a real architectural constraint: **a single static `build.html` template cannot emit a different `og:image`/`og:title` per build without server-side rendering, which this app does not have and isn't in scope to add.** Recommend a **generic, brand-level `og:image`** (a static Specbound logo/banner image) for `build.html` and every other page for now, explicitly noting that true per-build social preview images would require either a server-rendering layer or a serverless function generating them on demand — both out of scope for this milestone. This is a real, disclosed tradeoff, not an oversight.

---

## 3. Production infrastructure

### 3.1 Caching strategy

The naive "static site" instinct is to be cautious with caching because there's no content-hashed/versioned filenames (no bundler means `app.js` is always literally named `app.js`, deploy after deploy) — a long cache lifetime would normally risk serving stale JS after a deploy. **That risk doesn't actually apply here**, because both recommended hosts (Cloudflare Pages, Netlify) serve every deploy as an atomic, independent deployment and automatically invalidate their edge cache the moment a new deploy goes live — there is no manual purge step and no window where old and new files are inconsistently mixed. This means a meaningfully more aggressive cache policy than the "static site default" is safe:

| Path pattern | `Cache-Control` | Why |
|---|---|---|
| `/css/*`, `/js/*` | `public, max-age=3600` | Host auto-invalidates on deploy; an hour is a reasonable balance between "meaningfully reduces repeat-visit requests" and "any manual same-day re-deploy still resolves within the hour regardless" |
| `/assets/*` (images, icons, brand assets) | `public, max-age=86400` | Same reasoning, longer window — these change far less often than app code |
| `/*.html` (every page) | `public, max-age=0, must-revalidate` | The HTML shell should always be fetched fresh — it's the cheapest thing to re-fetch and is the top-level entry point; no reason to ever risk a stale one |
| `/tests/*` | N/A — excluded from the deploy entirely (§1.2) | — |

### 3.2 Cache headers (implementation draft)

Netlify/Cloudflare-Pages-compatible `_headers` file, to be created at repo root at implementation time:

```
/css/*
  Cache-Control: public, max-age=3600

/js/*
  Cache-Control: public, max-age=3600

/assets/*
  Cache-Control: public, max-age=86400

/*.html
  Cache-Control: public, max-age=0, must-revalidate

/*
  X-Content-Type-Options: nosniff
  Referrer-Policy: strict-origin-when-cross-origin
  Permissions-Policy: geolocation=(), microphone=(), camera=()
  Content-Security-Policy: default-src 'self'; script-src 'self' https://cdn.jsdelivr.net; style-src 'self' https://fonts.googleapis.com; font-src 'self' https://fonts.gstatic.com; img-src 'self' data: https://xpxjqyraizntbtijzoyp.supabase.co; connect-src 'self' https://xpxjqyraizntbtijzoyp.supabase.co; frame-ancestors 'none'
```

(If Vercel is chosen instead of Cloudflare Pages/Netlify, these same rules translate directly into `vercel.json`'s `headers` array — noting this so the choice in §1.1 doesn't lock out the caching plan.)

### 3.3 Error pages

**404**: a minimal, on-brand static page (reuses `styles.css`, matches the app's visual language, a short message + a link back to the homepage) — recommend creating this at implementation time. Every recommended host supports a custom 404 with zero extra configuration (a `404.html` at the root is the standard convention both Cloudflare Pages and Netlify auto-detect).

**500**: **not applicable to this architecture, and not planned** — this is a static site with no server-side rendering or backend logic of its own. There is no code path on the hosting layer that could produce a traditional "500 Internal Server Error" the way a dynamic backend would. Supabase-layer failures (a failed query, a denied RLS check, a network error) are already handled entirely client-side by the app's own existing error/toast UI (confirmed throughout this milestone's work — e.g. `mediaRepository.js`'s fail-soft `.catch(() => "")` patterns, `showToast` calls throughout the page controllers) — that *is* this app's "500 page" equivalent, and it already exists. Building a separate static 500.html would handle a case that structurally cannot occur at the hosting layer for this app.

### 3.4 HTTPS expectations

Both recommended hosts auto-provision and auto-renew SSL certificates for the production domain (and any preview domains) with zero manual certificate management. Plan:
- Enforce HTTPS redirect (on by default on both hosts; confirm during deployment verification, §1.6).
- Optional `Strict-Transport-Security` (HSTS) header — recommend adding once the domain has been running correctly on HTTPS for a short burn-in period (HSTS is intentionally hard to undo quickly — browsers cache it — so it's safer to add a little after initial launch rather than in the very first deploy, in case the domain/DNS needs any last-minute adjustment).

### 3.5 Content Security Policy and other security headers

Grounded directly in this repo's actual external-resource footprint (verified fresh for this proposal, §-header above) — not a generic template:

- `script-src 'self' https://cdn.jsdelivr.net` — this app's **entire** external script dependency is the one pinned Supabase client import. Confirmed zero inline `<script>` blocks anywhere in the 25 real app pages, so no `'unsafe-inline'` is needed for `script-src`.
- `style-src 'self' https://fonts.googleapis.com` — confirmed zero inline `style="..."` attributes in any real app page (only the unlinked `design-system.html` has any, and it's excluded from the production deploy per §1.2) — but this needs a **verification caveat**: some of this app's own CSS (or a future change) could rely on inline `style` being set via JS (`element.style.foo = ...`), which is a *different* CSP surface (`style-src-attr` in newer CSP levels) than a literal `style="..."` HTML attribute — worth a dedicated grep for `.style.` JS usage during implementation to confirm this doesn't silently break anything, rather than assuming the HTML-only check above is the complete picture.
- `font-src https://fonts.gstatic.com` — Google Fonts' actual font-file host (distinct from `fonts.googleapis.com`, which only serves the CSS that *points to* `fonts.gstatic.com`).
- `img-src 'self' data: https://<supabase-project>.supabase.co` — signed Storage URLs all resolve to the Supabase project's own domain; `data:` covers any inline SVG/base64 usage already present (e.g. the inline `<svg>` icons in `renderReadinessChecklist.js`, which are template strings inserted as HTML, not CSP-relevant `data:` URIs — included defensively rather than assumed unnecessary).
- `connect-src 'self' https://<supabase-project>.supabase.co` — every `fetch`/XHR this app makes (all Supabase REST/Auth/Storage calls) targets exactly this one external origin.
- `frame-ancestors 'none'` — this app is never meant to be embedded in an iframe; blocks clickjacking-style embedding.
- `X-Content-Type-Options: nosniff`, `Referrer-Policy: strict-origin-when-cross-origin`, a minimal `Permissions-Policy` — standard, low-risk, broadly-recommended hardening headers with no app-specific tradeoffs to weigh.

**This CSP needs to be verified against the live deployed site before being treated as final** — a CSP is exactly the kind of change that can silently break something (a missed external resource, a browser-specific quirk) if shipped without testing against the real production build. §5's verification plan treats this as a required, not optional, post-deploy check.

---

## 4. Documentation — `docs/DEPLOYMENT.md` (draft content, for review)

The following is the complete planned content for `docs/DEPLOYMENT.md`, presented here for review rather than written to that file yet, per "architecture only, no implementation." Once this whole Phase 9D plan is approved, this section becomes that file's actual content (with the placeholder domain/host names filled in from whatever gets confirmed during implementation).

> ### Deployment steps
> 1. Push the production branch to the connected GitHub repository.
> 2. The host (Cloudflare Pages/Netlify) auto-detects the push and deploys automatically — no build command, no publish-directory changes needed (root directory, static files as-is).
> 3. Wait for the deploy to report success in the host dashboard.
> 4. Run the smoke-test checklist (§7 below) against the production URL.
>
> ### Required environment variables
> None. `SUPABASE_URL`/`SUPABASE_KEY` are committed directly in `js/core/config.js` (the publishable key is safe for client-side exposure — see `docs/STORAGE_ARCHITECTURE.md`/`docs/AUTH_ARCHITECTURE.md` for the full security model). If a staging environment is introduced later, document its variable-substitution mechanism here at that time.
>
> ### DNS / domain configuration
> Point the production domain's DNS at the host per its own instructions (typically a `CNAME` to a host-provided subdomain, or host-managed nameservers for the fastest SSL provisioning). Confirm the domain resolves and serves the site before proceeding to the Supabase Auth redirect URL update below — that update needs the final, real domain.
>
> ### HTTPS expectations
> SSL is auto-provisioned and auto-renewed by the host. HTTPS redirect is enforced by default — confirm a plain `http://` request 301/302s to `https://` as part of every deployment verification pass.
>
> ### Rollback procedure
> Every deploy is atomic and independently addressable. To roll back: open the host dashboard's deployment history and re-promote the last known-good deployment to production — this takes effect immediately (no rebuild, no waiting). No git revert or force-push is required to roll back production; git history and deployment history are independent, so a bad deploy can be undone without touching the repository at all.
>
> ### Cache invalidation
> Not manually required in normal operation — the host invalidates its edge cache automatically as part of every deploy. If a cache-related issue is ever suspected despite this (e.g. a host-side incident), the host dashboard exposes a manual "purge cache" action as a fallback.
>
> ### Post-deployment smoke test checklist
> See §5 below — reproduced here verbatim at implementation time so this file is self-contained.

---

## 5. Verification plan

Exactly how each item above will be tested before this phase is considered done, and again after every future production deploy:

| Item | How it's verified |
|---|---|
| Host serves the site correctly | Navigate to the production URL, confirm the homepage renders, confirm `read_console_messages`/`read_network_requests` show no new errors compared to the current dev-server baseline |
| HTTPS enforced | Request the `http://` version of the production URL, confirm a redirect to `https://` |
| `robots.txt` | Fetch `/robots.txt` directly, confirm it returns the exact planned content, confirm the disallowed paths match §2.1 |
| `sitemap.xml` | Fetch `/sitemap.xml` directly, confirm valid XML, confirm every listed URL actually resolves (200) on the live domain |
| Manifest (if built) | Confirm `<link rel="manifest">` resolves and the browser doesn't report a manifest parse error in the console |
| Favicon | Confirm the SVG favicon loads with `Content-Type: image/svg+xml`; if a PNG fallback/apple-touch-icon is added, confirm those resolve too |
| Metadata (title/description/OG/Twitter) | For each updated page: view page source (not JS-rendered DOM) to confirm the tags are present in the static HTML `<head>` — this matters specifically because social-media crawlers and search engines generally do **not** execute this app's JS, so the tags must exist in the raw HTML response, not be injected client-side |
| Cache headers | `read_network_requests` (or a direct `curl -I`) against a JS file, a CSS file, an asset, and an HTML page — confirm each returns the exact `Cache-Control` value planned in §3.1/§3.2 |
| CSP / security headers | Load the production site with browser console open, confirm zero CSP violation errors across every page type (home, explore, a build page, login, signup, settings, the editor) — a CSP violation is silent in the UI but loud in the console, so this check must actually open the console, not just eyeball the page |
| 404 page | Request a deliberately nonexistent URL on the production domain, confirm the custom 404 renders (not the host's generic default) |
| Rollback mechanism | Before calling this phase done: perform one real test rollback (promote the previous deployment, confirm the site reverts, then re-promote forward again) — proving the rollback plan works in practice, not just on paper, directly closing out the original audit's **L3** finding |
| Supabase Auth redirect URLs | Trigger a real password-reset email against the production domain (using a real or test account you control) and confirm the emailed link points at the production domain, not a dev/localhost URL |
| Deployment verification process itself (§1.6) | Run it once, live, as part of closing out this phase — not just described, actually executed |

---

Stopping here for review, per your instructions — no implementation performed. The one decision worth confirming explicitly before implementation begins is the hosting platform (§1.1); everything else in this document is written to be equally valid under either Cloudflare Pages or Netlify, so it doesn't block reviewing the rest of the plan.
