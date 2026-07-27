# Milestone 9 — Phases 9C/9D/9E: Architecture Proposal

**Status: Phase 9C is complete and verified live (2026-07-26). Phases 9D/9E remain architecture only, awaiting their own approval to begin.**

## Phase 9C — completion note

Implemented as scoped above, with a few corrections discovered during implementation (all applied, all noted here rather than silently absorbed):

- **Git was initialized first** (user-approved deviation from the original sequencing recommendation), with a baseline commit before any 9C file changes, so every change below is tracked and revertible. A repo-local git identity was set (not global) since none existed.
- **D3** (blueprint-feed unused layout variants) was deleted without a separate question — same low-risk "confirmed dead in HTML/JS, git-recoverable" reasoning as D1/D2/D5, not worth a 5th product-decision question.
- **D6 turned out to be based on a stale premise.** The original finding pointed at `js/pages/upload/app.js`, but that file has no upload-zone UI at all — `pages/upload.html` (the page it renders) contains no file input or drag-drop zone anywhere. Investigation found the entire `.upload-zone`/`.upload-form`/`.has-file` rule family in `css/pages/upload/upload.css` was **orphaned dead CSS**, superseded by a separate, already-correct `css/components/uploadzone.css` that styles the *actual* reachable upload zone (the editor's gallery section, `pages/build/edit.html`) — which already has full upload feedback via its own `.is-dragging` state, status text, and immediate thumbnail rendering. There was no real "no confirmation" gap to wire up. Deleted the dead CSS instead (same treatment as D2/D5), consistent with the user's "wire it up" intent (closing the UX gap) since the gap didn't exist in reachable code.
- **D11** was worse than the original estimate: 20 files had local `escapeHtml`/`escapeAttribute` copies (not ~18), including `settings/app.js` despite that file being directly touched during the storage remediation. All 20 migrated to import the shared `js/utils/escapeHtml.js`.
- **Q4**: only `formatCategory.js` and `formatDate.js` were recreated as real files (holding D12/D13's consolidated logic), plus a new `avatarInitial.js` for D14. `formatStatus.js` and `slugify.js` were deliberately **not** recreated — investigation found `formatStatus` has two same-named but behaviorally different functions (`renderBuild.js`'s is a display-label formatter, `renderDashboard.js`'s is an internal status passthrough/default) that are not real duplication and would be a functional bug to merge, and `slugify` no longer exists anywhere in the codebase. Creating empty stub files for either would have repeated the exact anti-pattern Q4 itself criticized.
- All other items (D1, D2, D4, D5, D7, D8, D9 [no action, per approval], D10 [no action], D12, D13, D14, S4, S5, S6, B2, B4, P1–P4) implemented exactly as scoped.
- Verified live via the browser preview across home, explore, upload, a build page, a public profile page, followers, and search — no new console errors, all touched features (category badges, dates, avatar initials, comments, follow lists, gallery upload, Featured Spotlight via the pinned Supabase CDN version) render correctly.
- Net diff: 57 files changed, 78 insertions, 920 deletions (mostly dead CSS/JS removal).

Not yet committed to git — awaiting the user's decision on that.

---

**Scope:** the remaining Milestone 9 production work, now that the storage subsystem (originally findings S1/S3/S6 in `docs/MILESTONE_9_ARCHITECTURE.md`) is complete and verified — see `docs/STORAGE_ARCHITECTURE.md`. This document reorganizes the original audit's still-open findings into three phases, after re-verifying every one of them fresh against the current codebase (2026-07-26, post-storage-remediation) to confirm none drifted while that work was in progress. All 27 re-checked items came back unchanged except D11 (escaping duplication — now confirmed 20 files, not the original document's approximate ~18-20 estimate).

---

## Phase 9C — Production Cleanup

*Dead code, unused assets, duplicate utilities, bundle cleanup.*

### Dead code — delete outright (no product decision needed)

| # | Item | Files | Action |
|---|---|---|---|
| D1 | `Spotlight`/`SpotlightSlide` component pair — zero importers, hardcodes a path to a nonexistent image | `js/components/Spotlight/Spotlight.js`, `SpotlightSlide.js` | Delete both files |
| D2 | `css/layout/grid.css` — imported, zero selectors used anywhere | `css/layout/grid.css`, import at `css/styles.css:9` | Delete file + import line |
| D5 | ~10 dead CSS selectors scattered across page-specific files | `home.css`, `explore.css`, `upload.css`, `hero.css`, `badge.css`, `card.css`, `progress.css`, `typography.css`, `page.css` | Delete each confirmed-dead selector |
| D7 | 5 empty directories | `js/models`, `assets/brand/brand-book`, `assets/brand/patterns`, `assets/icons/ui`, `assets/images/demo` | Delete |
| S5 | `js/pages/build/deleteRevision.js` — dead, unreachable (`setupDeleteRevision` has zero importers); latent risk is moot since it's unreachable | `js/pages/build/deleteRevision.js` | Delete file |
| S6 | `uploadGalleryImage()` still constructs and returns a discarded `getPublicUrl()` value — dead output confirmed, and now provably unusable since the bucket is Private | `js/services/imageService.js:129-134` | Remove the `getPublicUrl()` call and return; caller already discards the return value |

### Dead code / dead CSS — needs a product decision before acting

| # | Item | Files | Options |
|---|---|---|---|
| D3 | `blueprint-feed.css` `horizontal`/`compact` layout variants unreachable — all 4 call sites hardcode `layout: "grid"` | `css/components/blueprint-feed.css`, `js/pages/explore/app.js`, `js/pages/search/app.js` | Delete the unused variant CSS, or confirm one of these layouts is actually planned before deleting |
| D4 | `css/themes/light.css` entirely dead — no theme toggle exists anywhere, nothing sets `data-theme="light"` | `css/themes/light.css`, import at `css/styles.css:31` | Delete (if no light theme is planned), or treat as a real feature request and wire up a toggle — not pure cleanup |
| D6 | `.upload-zone.has-file` — dead CSS for an apparently-intended "file selected" visual state the JS never wires up | `css/pages/upload/upload.css:158-172`, `js/pages/upload/app.js` | Recommend wiring it up (one-line JS fix, closes a real "no confirmation a file was chosen" UX gap) rather than deleting |
| D8 | `pages/add-revision.html`/`edit-revision.html` + backing JS fully orphaned — the live "view a past revision" flow goes through `build.html?revision=...` instead | `pages/add-revision.html`, `pages/edit-revision.html`, `js/pages/revision/app.js`, `js/pages/edit-revision/app.js` | Delete (dead weight) or wire up as a real "add/edit a revision entry" flow if planned |
| D9 | `pages/legal/affiliate-disclosure.html`/`community-guidelines.html` unlinked from the footer (only Privacy/Terms are linked) — no longer a compliance risk since both are "Coming Soon," just a reachability gap | `js/core/layout.js` (footer), the two pages | Link both from the footer alongside Privacy/Terms (same "Coming Soon" framing), or leave unlinked until real content exists |
| D10 | `design-system.html` unlinked from anywhere — almost certainly an intentional internal dev/style-guide page | `design-system.html` | No action, or explicitly exclude from the production deploy (relevant to Phase 9D's hosting config) |

### Duplicate utilities — consolidate

| # | Item | Current state (re-verified) | Proposed fix |
|---|---|---|---|
| D11 | `escapeHtml`/`escapeAttribute` duplication | Shared module `js/utils/escapeHtml.js` exists but only **2 files** import it (`featured.js`, `renderDashboard.js`). **20 files** still carry local copies, including `settings/app.js` — which was directly edited during the storage remediation and still wasn't migrated | Migrate all 20 files to import from the shared module. Mechanical, one file at a time, independently testable (behaviorally identical implementations already confirmed in the original audit) |
| D12 | `formatCategory` — 3 independent implementations with 3 different fallback strings (`"Build"`/`"Blueprint"`/`"Technology"`) | Unchanged: `BlueprintCard.js:243`, `featured.js:79`, `renderBuild.js:365` | Consolidate into `js/utils/formatCategory.js`, pick one fallback string |
| D13 | `formatDate` — 2 implementations, different month format (`"long"` vs `"short"`), both render on the same `build.html` page | Unchanged: `renderTimeline.js:207`, `renderComments.js:296` | Consolidate into `js/utils/formatDate.js`, pick one format |
| D14 | Avatar-initial fallback (`charAt(0).toUpperCase()`) duplicated in 5 files | Unchanged: `renderBuild.js`, `renderComments.js`, `settings/app.js`, `renderProfile.js`, `renderFollowList.js` | Extract to a shared one-line util alongside the above |
| Q4 | The 4 `js/utils/` stub files meant to hold D12-D14's consolidated logic (`formatCategory.js`, `formatDate.js`, `formatStatus.js`, `slugify.js`) were deleted in 8D's cleanup, but the consolidation itself was never done — still confirmed absent | Create these as real, filled-in files as part of the D11-D14 work, not empty placeholders again |

### Bundle cleanup / production build

| # | Item | Current state | Proposed fix |
|---|---|---|---|
| B1 | No build step at all — no bundling, minification, tree-shaking, cache-busting. `build.html` alone pulls 29 JS modules; `styles.css` chains 39 `@import`s | Unchanged | Not launch-blocking at this app's likely scale — but should be a **conscious documented decision**, not silence. Recommend explicitly accepting the current per-page request count for initial launch, revisiting bundling only if traffic/performance data later justifies it |
| B2 | 3 leftover debugging `console.log`/`console.warn` calls (not the established `console.error`-only convention) | Unchanged: `js/pages/editor/app.js:193,198,212` | Remove/downgrade to match the codebase's `console.error`-only convention |
| B4 | Supabase client imported from an **unpinned** CDN URL — a breaking upstream release could silently alter auth/data-fetching behavior with zero warning | Unchanged: `js/core/supabase.js:1`, `@supabase/supabase-js/+esm` with no version | Pin to an exact version, e.g. `@supabase/supabase-js@2.x.x/+esm`. One-line fix, high value |
| P4 | `loading="lazy"` missing on comment-author and follow-list avatars, unlike every other repeated-card image in the app | Unchanged: `renderComments.js:258`, `renderFollowList.js:189` | Add `loading="lazy"` to match the established pattern |

### Broken/empty assets (bundled into 9C since they're an asset-file fix, not a deployment concern)

| # | Item | Current state | Proposed fix |
|---|---|---|---|
| P1 | `favicon.svg` is a literally empty (0-byte) file — every browser tab shows a blank icon | Confirmed still 0 bytes | Replace with a real SVG icon |
| P2 | `default-cover.svg` is a literally empty (0-byte) file — every image-less build card renders a blank placeholder | Confirmed still 0 bytes | Replace with a real placeholder graphic |
| P3 | 5 pages missing the Google Fonts `preconnect`/stylesheet links entirely, causing a visible font swap on navigation | Confirmed still missing on `dashboard.html`, `followers.html`, `following.html`, `notifications.html`, `profile.html` | Add the same 3 `<head>` lines every other page already has |

### Recommended for bundling into 9C despite not being "dead code/duplicate/bundle" in the strict sense

| # | Item | Why it fits here | Files |
|---|---|---|---|
| S4 | `getProfile()` (selects all columns) used for two other-users'-profile views reachable by any anonymous visitor, instead of the app's established `getPublicProfile()` allowlist pattern used everywhere else | Small, mechanical, low-risk code fix touching files already in scope for this cleanup pass; flagged as a real (if minor-until-S2-resolved) inconsistency in the original audit | `js/pages/build/loadBuild.js:49`, `js/pages/followList/loadFollowList.js:29` — change both call sites to `getPublicProfile()` |

---

## Phase 9D — Deployment Preparation

*Git verification, production configuration, robots.txt, sitemap.xml, manifest, caching, error pages.*

### Git verification

| # | Item | Current state | Proposed fix |
|---|---|---|---|
| L1 | No version control at all — confirmed no `.git` directory anywhere, still true as of this re-check | Unchanged | Initialize git, commit the current state as a baseline. **Recommend doing this first, before Phase 9C's implementation begins** (once approved) — 9C involves multiple file deletions and edits across ~25 files, and none of that should happen without version history to fall back on. This is the one Phase 9D item worth pulling ahead of 9C in actual execution order, even though it's catalogued here under 9D |

### Production configuration

| # | Item | Current state | Proposed fix |
|---|---|---|---|
| L2 | No deployment pipeline or hosting configuration (`vercel.json`/`netlify.toml`/CI config/Dockerfile) — the app has never been deployed anywhere | Unchanged | Choose a static host (Vercel/Netlify/Cloudflare Pages/S3+CDN all fit this architecture), configure it, document the deploy steps — this is a decision to present to you, not one to make unilaterally |
| L3 | No rollback plan — direct consequence of L1+L2 | Unchanged | Once L1/L2 exist: "rollback = redeploy the previous git commit/tag," confirm the chosen host supports instant redeploys |
| L5 | Supabase URL/publishable key hardcoded in a committed file (`js/core/config.js`) rather than injected at deploy time | Unchanged | Only relevant if a staging/production environment split is wanted (a separate Supabase project for staging). If this will only ever be one environment, no change needed — flagging as a decision, not a default action |
| L7 | Domain/DNS/SSL checklist — cannot be verified from the repository | Unverified | Standard pre-launch checklist once a host is chosen (L2): custom domain, SSL (most modern hosts auto-provision), and **Supabase auth redirect URLs updated to the real production domain** — password reset/OAuth flows will silently fail against a stale `localhost`/dev redirect URL if this is missed |

### `robots.txt` / `sitemap.xml` / `manifest`

| # | Item | Current state | Proposed fix |
|---|---|---|---|
| B7 | `robots.txt` absent | Confirmed still absent | Add before public launch — at minimum, disallow `pages/settings.html`, auth pages, and any pages still orphaned per Phase 9C's D8/D9/D10 decisions |
| B8 | `sitemap.xml` absent | Confirmed still absent | Growth/discoverability nicety, not urgent for initial launch (builds/profiles are still crawlable via internal links) — can follow shortly after `robots.txt` |
| B9 | `manifest.json`/`site.webmanifest` absent, nothing expects one | Confirmed still absent | Only relevant if "Add to Home Screen"/PWA installability is an actual product goal. **Needs a decision from you** — nothing in the app currently suggests this is planned; recommend skipping unless you want it |

### Caching

| # | Item | Current state | Proposed fix |
|---|---|---|---|
| P5 | No production hosting/cache-header configuration exists anywhere. The dev server explicitly disables all caching, which tells you nothing about production | Confirmed still absent (no `_headers`/`.htaccess`/host-level cache config) | Decide and document a real caching strategy as part of the L2 hosting decision — e.g. long-lived immutable caching for versioned/hashed assets (none currently exist, ties back to B1's no-bundler decision) vs. short caching for HTML. Should be resolved as part of the deployment plan, not discovered after the first stale-asset incident |

### Error pages

| # | New item | Current state | Proposed fix |
|---|---|---|---|
| — | No custom `404`/`500`/error page anywhere in the repo (confirmed absent this round — not in the original audit, newly identified) | Confirmed absent | Add a minimal branded 404 page at minimum (most static hosts serve their own generic 404 otherwise) at deploy time; a 500-equivalent is less standard for a static site but worth a one-line decision (most static hosts don't have a server-error case in the traditional sense) |

---

## Phase 9E — Final Launch Verification

*Lighthouse, accessibility, performance, console/network audit, production readiness scoring, launch checklist.*

This phase runs **after** 9C and 9D land — it verifies the cumulative result, not individual fixes in isolation, and is where the original audit's Production Readiness Scores get formally recomputed against the then-current state (not re-litigated now, before any of 9C/9D exists to measure).

### Lighthouse

Run Lighthouse (Performance/Accessibility/Best Practices/SEO) against the key page types once 9C/9D land: homepage, Explore, a build page, a profile page, the editor. Compare against a rough baseline captured now (pre-9C/9D) so the delta itself is documented, not just the final number.

### Accessibility

The original audit's 8/10 accessibility score was explicitly **not** re-scored in depth (out of that audit's scope) — it's carried forward as an estimate resting on 8D's thorough pass (keyboard, focus, screen-reader, contrast, mobile). Phase 9E should include a dedicated re-check, not just an inherited number, especially since Phase 9C's cleanup work touches several of the same files 8D fixed (footer links, page structure).

### Performance

Re-run the performance-relevant checks from the original audit (P1-P5) to confirm Phase 9C actually closed them — this phase is verification, not re-discovery.

### Console/network audit

Live check via the browser preview tools: zero console errors/warnings across the key pages, zero failed network requests, zero mixed-content warnings, confirm the pinned Supabase CDN version (B4, once fixed) loads correctly.

### Production readiness scoring

Recompute the original audit's 0-10 table (Security/Reliability/Performance/Accessibility/Maintainability/Code Quality/UX/Overall) against the actual post-9C/9D state, not the pre-fix snapshot it currently shows. The Security score in particular should reflect: S1/S3 already closed (storage), plus whatever S2 (see below) resolves to.

### Launch checklist

Consolidates every remaining live-verification/decision item that doesn't fit cleanly into 9C or 9D's code-level work — these are dashboard settings, product/legal decisions, or external service configuration, not things I can implement:

| # | Item | Note |
|---|---|---|
| S2 | **RESOLVED.** Live `pg_policies` check confirmed RLS enabled, public SELECT intentional, authenticated UPDATE correctly owner-scoped. A follow-up code audit of the profile *creation* (INSERT) path is now documented in `docs/AUTH_ARCHITECTURE.md`: no SECURITY DEFINER RPC or DB trigger exists — creation is a direct client-side insert (`ensureProfile()`) gated by RLS, called at signup/login. One narrow open item remains: the INSERT policy's exact `with_check` scoping wasn't independently re-verified (only SELECT/UPDATE were) — low urgency (structurally safe regardless, per `AUTH_ARCHITECTURE.md` §3), recommend a quick `pg_policies WHERE cmd = 'INSERT'` check before public launch, not a blocker to 9C/9D/9E |
| L4 | Supabase backup/point-in-time-recovery tier — account-level setting, not visible in any file | Confirm plan tier and whether PITR/daily backups are enabled |
| L6 | Legal pages (Privacy, Terms, Community Guidelines, Affiliate Disclosure) are correctly "Coming Soon" placeholders — real legal documents still don't exist | Legal/product task, not engineering — hard prerequisite for a genuine public launch, acceptable as-is for a private beta/soft launch |
| L9 | Supabase default email service has strict rate limits, not recommended for production auth traffic by Supabase's own docs; no evidence of custom SMTP configured | Confirm in the dashboard whether custom SMTP is set up before real signup/password-reset traffic arrives |
| L10 | No error-tracking/monitoring (Sentry or equivalent) configured | Not strictly launch-blocking for a small/community-scale launch, but recommended — right now a production error is only visible to the one user who hit it |
| L8 | No analytics/consent tooling — correctly deferred until L6 (Privacy Policy) exists, so analytics has something real to disclose in | No action needed until L6 resolves |

The final deliverable of Phase 9E is a single **launch checklist document** — every item above plus every Phase 9C/9D item, in one place, each marked done/not-done, so "are we launch-ready" has one authoritative answer instead of being scattered across four documents.

---

## Sequencing recommendation

1. ~~**S2 live check**~~ — done (see above); the one remaining sub-item (INSERT policy scoping) is low-urgency and deferred to the Phase 9E launch checklist.
2. **Git init** (L1) — before any Phase 9C code changes land, so they're tracked from the start.
3. **Phase 9C** (production cleanup) — mechanical, low-risk, same pattern as 8D's cleanup phase and Migration A/B/C's own careful sequencing.
4. **Phase 9D** (deployment prep) — needs a host decision from you before most of it can proceed; `robots.txt`/`sitemap.xml`/caching strategy depend on knowing where the app will actually live.
5. **Phase 9E** (final verification) — runs against the real, deployed-or-deployable result of 9C+9D, not before.

Phase 9C is approved and now underway.
