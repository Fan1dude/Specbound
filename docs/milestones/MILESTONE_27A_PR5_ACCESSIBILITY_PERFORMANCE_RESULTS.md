# Milestone 27A PR5 — Accessibility & Performance Verification Results

Status: PR5 complete and verified (draft PR [#27](https://github.com/Fan1dude/Specbound/pull/27), not yet merged, still draft). Baseline audit, narrowly-scoped fixes, post-fix Cloudflare Preview re-verification, and a follow-up round addressing three findings from an independent PR #27 review are all recorded below (§11). **This does not mean Milestone 27A as a whole is complete** — see `docs/ROADMAP.md`'s 27A row for what remains (PR1 blocked on 27B; Storage/backup/monitoring/staff-bootstrap adult-owner actions outstanding).

- **Date:** 2026-08-15
- **Branch:** `27a-a11y-perf-pass`
- **Base commit:** `38ae6217219e42d47a3b5871ddc133efb7ac94d4` (PR #26 merge — Milestone 27A PR4, operator documentation, merged to `main`)
- **Scope:** Audit plus narrowly-scoped fixes only, per the PR5 task brief. Does not start PR1 (signup posture, held for 27B) or any 27B legal work.

This document is a results record, not a specification. It exists to satisfy the PR5 requirement for an auditable baseline: what was measured, in which environment, with what limitations, before and after the fixes in this PR.

---

## 1. Environments used

| Test type | Environment | Why |
|---|---|---|
| Lighthouse (baseline, before fixes) | **Production** (`specboundapp.com`) | The local static dev server (`.claude/nocache_server.py`, port 8431) resolves its working directory to the main repo checkout, not this git worktree, so it cannot serve this worktree's edits — confirmed via `preview_list` showing the server `cwd` pointed at the main checkout root, not this worktree path. No Cloudflare Preview exists yet at baseline time (branch not yet pushed). Production was therefore the only environment that could serve real, current content for a real Lighthouse run. |
| Lighthouse (after fixes) | **Cloudflare Preview** (recorded once the branch is pushed and the draft PR's preview URL exists) | Per the task brief's own instruction to verify against the Cloudflare Preview once fixes are applied. See §6. |
| axe-core (automated) | **Production**, signed-out pages | Same reasoning as above — the local server could not serve this worktree's content, and no authenticated Docker/local Supabase environment was available this pass (see §4 limitation). |
| Static checks (syntax, references, a11y-regressions, auth-redirects, csp-bootstrap, production-domain, security-headers, crawl-policy) | **This git worktree, on disk** | These are pure Node scripts that read files directly — unaffected by the dev-server cwd issue. |
| Browser regression suite (`tools/ci/run-tests.js`) | **This git worktree**, via its own bundled HTTP server (not the affected `.claude/nocache_server.py`) | Confirmed unaffected — this runner serves the repo root directly from its own script location, not the main checkout. |
| Manual keyboard/focus verification | **Production**, real keyboard input via the Browser pane's `computer` tool (real Tab keypresses, not scripted `.focus()`) | Scripted `.focus()` + `:focus-visible` checks gave an ambiguous false negative in an earlier pass; real keyboard interaction is the only environment that reliably reproduces `:focus-visible` matching. |

**Do not treat production and Cloudflare Preview numbers as directly comparable to a hypothetical unthrottled/local run.** All Lighthouse numbers in this document come from the same tool, the same default settings, and (for the before/after pair on a given page) the same network path where possible — see §6 for what changes between the baseline and after-fix environment.

### Limitation: Docker unavailable

Docker was not available in this environment this pass, so no local Supabase instance could be started and no disposable authenticated test account could be created. Per the task brief, **no production test account was created and no real production data was altered.** All pages that call `requireAuth()` on load (Feedback, My Feedback, Workshop, Settings, Notifications) were verified only for their signed-out fail-closed behavior — confirmed each redirects to `login.html` rather than exposing any authenticated UI. Authenticated-state behavior (queue interactions, dialogs, live regions inside those pages, Connected Accounts controls, notification bell dropdown contents) is **not verified this pass** and is not claimed as passing. This is a real, stated gap, not a fabricated result.

---

## 2. Tooling versions

- **Lighthouse:** 13.4.1, via `npx --yes lighthouse`, headless Chrome (`--chrome-flags="--headless=new"`), `CHROME_PATH` pinned to a local Chrome install. **Default Lighthouse settings were used — no `--preset=desktop` flag** — meaning every run below used Lighthouse's default mobile device emulation and simulated mobile network/CPU throttling, not an unthrottled desktop measurement. This is why LCP/Speed Index/TTI read in the multi-second range even though the site's actual transfer sizes are small; treat the Performance category and Core Web Vitals numbers below as **lab, throttled-mobile** figures, not real-world desktop timings.
- **User agent (all runs):** `Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) HeadlessChrome/151.0.0.0 Safari/537.36`
- **axe-core:** 4.10.2, loaded via `https://cdn.jsdelivr.net/npm/axe-core@4.10.2/axe.min.js` (already CSP-whitelisted for `script-src`), run as `axe.run(document, { resultTypes: ["violations"] })` in-page.
- **Browser test runner:** `tools/ci/run-tests.js` (Playwright/Chromium), serves the repo over plain HTTP on port 4173.

---

## 3. Lighthouse baseline — before fixes (production)

Three runs per page, same settings, run back-to-back on 2026-08-15. Median reported; range in parentheses. Scores are 0–100 (Lighthouse category scores); LCP/FCP/TBT/Speed Index/TTI in milliseconds; CLS unitless; transfer in KB.

The public build page tested is a real published build on production, generically labeled here rather than by its slug/ID (see task instruction not to expose identifying content in committed reports).

| Metric | Home | Explore | Public build page | Login |
|---|---|---|---|---|
| Performance | 73 (66–75) | 70 (64–72) | 61 (51–70) | 72 (71–72) |
| Accessibility | 100 | 100 | 100 | **95** |
| Best Practices | 92 | 92 | 92 | 92 |
| SEO | 100 | 100 | 100 | **66** (see note) |
| LCP (ms) | 4615 (3492–6034) | 4624 (3932–5736) | 5427 (4823–6583) | 3776 (3630–3777) |
| CLS | 0 (0–0.239) | **0.195** (0–0.195) | **0.282** (0.055–0.287) | **0.229** (0.224–0.229) |
| Total Blocking Time (ms) | 0 | 0 | 0 | 0 |
| First Contentful Paint (ms) | 3208 | 3285 | 3356 | 3126 |
| Speed Index (ms) | 4706 | 4110 | 4509 | 3126 |
| Time to Interactive (ms) | 4623 | 4624 | 5427 | 3776 |
| Transfer size (KB) | 424 | 1891 | 454 | 370 |
| Requests | 135 | 123 | 146 | 106 |

**Interaction responsiveness (INP):** Lighthouse's lab run does not measure real INP (Interaction to Next Paint) — that requires field data or a scripted interaction trace, neither available here. Total Blocking Time (above, 0ms on every run) is the available lab proxy for main-thread responsiveness during load; it does not substitute for a real INP measurement, which is not claimed.

**Login's SEO score (66) is by design, not a defect.** It is fully explained by the page's intentional `noindex` directive, established in Milestone 27A PR3's crawl-policy work (`docs/milestones` PR3 change, `tools/ci/check-crawl-policy.js`) — Lighthouse's SEO category penalizes `noindex` pages by default. Fixing this score would mean reversing PR3's deliberate policy; it is not treated as a finding.

**No universal score targets are asserted.** These numbers are the recorded baseline; the bar for future 27A work is "no material regression from this baseline," not any specific number.

### Root cause identified: CLS

Every page above ships `<nav id="navbar"></nav>` and `<footer id="footer"></footer>` **empty** in its raw HTML (confirmed by reading `pages/login.html` and the other tested pages' source) — both are populated asynchronously by `loadNavbar()`/`loadFooter()` in `js/core/layout.js`. Neither `.navbar` nor `.footer` reserved any height before this pass, so the page's layout jumps once the async fetch resolves. This is the CLS root cause on Explore (0.195), the public build page (0.282), and Login (0.229); Home's 0–0.239 spread suggests the same cause intermittently, depending on how the async fetch races against the paint. Lighthouse's own `layout-shift-elements` audit detail confirmed `cumulativeLayoutShiftMainFrame` matching these numbers on the build/explore/login runs, with no other shift contributor reported. See §5 for the fix.

### Root cause identified: Login accessibility score

Lighthouse's accessibility audit failure detail for every login run was exactly one audit: `target-size` — "Touch targets do not have sufficient size or spacing," flagging `<a href="forgotPassword.html">` ("Forgot password?"). Live measurement confirmed the link's actual rendered height was 17px, below the WCAG 2.5.8 AA 24px minimum. See §5 for the fix.

---

## 4. Automated accessibility checks

### axe-core (production, signed-out)

Run against 6 signed-out-reachable pages: **Home, Explore, a public build page, Login, the editor entry (`pages/upload.html`, reachable signed-out by design — see note below), and a public Builder Portfolio page.** Zero violations (`resultTypes: ["violations"]`) reported on every page.

**`pages/upload.html` is intentionally reachable while signed out.** `js/pages/upload/app.js` calls `requireAuth("login.html")` only inside the form's submit handler (not on page load), so a signed-out visitor can browse and fill the public project form freely; Supabase RLS still protects the actual database write. This was confirmed by reading the source, not assumed — it is deliberate design, not a broken redirect.

### Static repository checks (all 8, on this worktree)

| Check | Result |
|---|---|
| `check-syntax.js` | 162/162 JS files pass |
| `check-references.js` | All local references OK (97 HTML, 56 CSS, 162 JS) |
| `check-a11y-regressions.js` | No regressions (56 CSS files, 97 HTML files) |
| `check-auth-redirects.js` | 11 call-site/page combinations OK across 97 pages |
| `check-csp-bootstrap.js` | OK — 28 pages, 152 JS files scanned |
| `check-production-domain.js` | No obsolete domain references (33 files) |
| `check-security-headers.js` | OK — Stage 1 HSTS intact, all required headers present |
| `check-crawl-policy.js` | OK — noindex/crawlable classification unchanged |

### Browser regression suite

1551/1551 passing at baseline (before any PR5 edits), full run via `tools/ci/run-tests.js`.

### At-minimum page coverage required by the task brief

| Page | Coverage this pass |
|---|---|
| Home | axe-clean (production) |
| Explore | axe-clean (production) |
| Public build | axe-clean (production) |
| Login | axe-clean (production); the one Lighthouse a11y finding (target-size) is fixed, see §5 |
| Feedback | Signed-out redirect to `login.html` confirmed. Authenticated state not tested (Docker unavailable). |
| My Feedback | Signed-out redirect to `login.html` confirmed. Authenticated state not tested. |
| Workshop | Signed-out redirect to `login.html` confirmed. Authenticated state not tested. |
| Settings | Signed-out redirect to `login.html` confirmed. Authenticated state not tested. |
| Notifications | Signed-out redirect to `login.html` confirmed. Authenticated state not tested. |
| Editor (`upload.html`) | axe-clean signed-out (intentionally public until submit, see above). Authenticated publish/edit flow not tested. |

---

## 5. Manual accessibility matrix

| Item | Result |
|---|---|
| Keyboard-only navigation | Verified via real Tab keypresses (Browser pane `computer` tool) on production — reaches all interactive elements in visual order. |
| Logical tab order | Matches visual/DOM order on pages checked (Home, Login). |
| Visible focus indicators | Confirmed via real keyboard input: `:focus-visible` matches and a visible `box-shadow` ring renders (`--focus-ring` token). An earlier scripted-`.focus()` check gave a false negative (`outline-style: none` despite `outline-width: 3px`) — corrected by using real keyboard interaction instead of `.focus()` + `:focus-visible` script checks, which don't reliably reproduce the browser's own focus-visible heuristics. |
| Focus restoration after dialogs/actions | Not independently re-verified this pass beyond what Milestone 26's existing focus-restoration regression tests already cover (`tests/myFeedback.test.html`, feedback-queue focus tests) — those continue to pass unchanged. |
| Skip-link behavior | Present and functional (Milestone 18 audit baseline, reconfirmed present in current markup). |
| Keyboard traps | None found on pages checked. |
| Accessible names (buttons, links, inputs, menus, tabs, status pills, icon-only controls) | axe-clean on all 6 pages tested (§4). Two real, small mismatches found by Lighthouse specifically (not axe, on these particular production pages/data) — see §5 fixes below. |
| Heading hierarchy | **Informational, not fixed this pass:** every page has two `<h1>` elements — the navbar's logo (`<h1 class="logo">`, `js/core/layout.js:117`, injected on every page via `loadNavbar()`) and the page's own content `<h1>` (e.g. Home's "Document Every Build."). Confirmed live on production (`document.querySelectorAll("h1")` returned 2 elements on the homepage). Fixing this means changing the shared navbar component's semantics sitewide — broader than this pass's narrow-fix policy allows; flagged as follow-up work, not fixed here. |
| Landmarks | **Corrected during PR #27 review (2026-08-15) — not a landmark issue.** `BlueprintCard.js` renders a `<footer class="blueprint-card-footer">` per card (`js/components/BlueprintCard.js:148`), and an earlier version of this document characterized that as "multiple non-page `<footer>` landmarks per page." That was inaccurate. Per the HTML→ARIA mapping, a `<footer>` nested inside `<article>` (as every `.blueprint-card-footer` is) carries **no landmark role at all** — only a page-level `<footer>` with no such ancestor exposes `contentinfo`. Verified directly: walking every `<footer>` element on the live homepage and checking for an `article`/`aside`/`main`/`nav`/`section` ancestor found exactly **one** `contentinfo` landmark (the real page footer, `<footer id="footer">`) among 14 `<footer>` elements total; axe-core independently reported 0 violations on the same page. **Informational only, non-impacting:** using `<footer>` as a per-card sectioning wrapper is an unconventional but harmless choice — it does not create landmark-navigation noise for assistive technology and needs no follow-up. |
| Live-region behavior (loading/success/error/empty/denied) | Not independently tested this pass for authenticated states (Docker unavailable). Signed-out denied states (redirect) confirmed. |
| Reduced-motion behavior | Confirmed handled — `prefers-reduced-motion` rules exist in 7 CSS files including the base `css/base/animations.css` (verified via source grep after an initial live-DOM script check gave a false negative from not recursing into nested `@media` blocks). |
| Color contrast (incl. Feedback/My Feedback status pills) | Covered by axe's automated contrast checks (0 violations on pages tested); Feedback/My Feedback pages themselves not independently re-tested this pass (require an authenticated account with feedback data — Docker unavailable). |
| 200% browser zoom / reflow | Not tested this pass. |
| Mobile viewport (~375px) | Tested on Login at 375px width — no horizontal overflow found. |
| Desktop viewport (~1280px) | Tested on Login at 1280px width — no horizontal overflow found. |
| Meaningful image alt text | `BlueprintCard`'s cover image uses the build title as `alt` text (confirmed in source); axe-clean on pages with cards. |
| Error association / form instructions | Not independently re-tested this pass beyond axe's automated pass (0 violations on Login's form). |

**Note on assistive technology:** all of the above used the Browser pane's accessibility tree / axe-core / real keyboard input, not a real screen reader (VoiceOver/NVDA). No VoiceOver/NVDA pass is claimed.

---

## 6. Functional surface checks

| Surface | Coverage this pass |
|---|---|
| Feedback queue (tabs, filters, actions, confirmation dialog, focus restoration, states) | Not tested — requires an authenticated account; Docker unavailable. Existing regression tests (`tests/feedbackQueue.test.html`, 76/76) continue to pass unchanged. |
| My Feedback (legend, statuses, bounded-history note, states) | Not tested — same limitation. `tests/myFeedback.test.html` (22/22) continues to pass unchanged. |
| Authentication redirects | Verified signed-out redirect behavior for Feedback, My Feedback, Workshop, Settings, Notifications (all redirect to `login.html`). |
| Editor publish/edit flow | Not tested — requires an authenticated account. Editor's public-until-submit page structure confirmed axe-clean (§4). |
| Notification bell/page | Not tested — requires an authenticated account for real notification data; signed-out page-load behavior only. |
| Connected Accounts controls | Not tested — requires an authenticated account. |
| Public Builder Portfolio | Reached signed-out on production, axe-clean (§4). Generic label used in this document per the task's PII instruction — no builder username recorded here. |

No fake production content was created. No disposable local fixtures were used this pass because no local Supabase instance was available to seed them into (Docker unavailable) — this is stated as a limitation, not worked around by testing against real production data.

---

## 7. Findings, classified by severity

### Blocking launch issues
None identified this pass.

### Important, non-blocking — fixed this pass

1. **Login "Forgot password?" touch target below WCAG 2.5.8 AA minimum.** Measured 17px tall; AA minimum is 24px. Root-caused to `.auth-forgot a` having no padding. **Fixed** in `css/pages/auth/auth.css`, originally using the app's existing padding+negative-margin hit-area-without-layout-shift technique (already used for `.footer-group a`/`button`). **Superseded during PR #27 review (2026-08-15) — see §11.1:** that technique put the link's padded hit-area 4px into the password input's own box, because `.auth-forgot`'s own container was already flush against the input with no buffer to absorb the pull. Now uses `min-height: 24px` with no negative margin, so the box only grows downward within its own normal flow. The target now meets the ≥24×24px minimum (verified 24×~132px) without overlapping the password input or the submit button at any pixel.
2. **Unreserved navbar/footer height causes CLS on every page.** `<nav id="navbar">`/`<footer id="footer">` ship empty and are populated async, contributing 0.195–0.282 CLS across Explore/build/Login (Home intermittently). **Fixed** by adding `min-height` to `.navbar`/`.footer` and their responsive breakpoints, set to each breakpoint's real measured shell height (measured live via `getBoundingClientRect()` at desktop/tablet/mobile widths on production).
3. **`BlueprintCard`'s image-link accessible name omits its visible stage-badge text** (WCAG 2.5.3, Label in Name) — flagged by Lighthouse as `label-content-name-mismatch` on the production Explore and build pages. The link's `aria-label` was `"View {title}"`, but its visible rendered content includes a stage badge (e.g. "In Progress") not reflected in the accessible name. **Fixed** in `js/components/BlueprintCard.js` by appending the stage label to the `aria-label`.
4. **The build page's like button accessible name omits its visible like count** (same WCAG 2.5.3 category) — the button's `aria-label` ("Like this project") suppresses all child content, including the visible `#likeCount` number, from the accessible name, so the count was never announced. **Fixed** in `js/pages/build/renderLike.js` by folding the current count into the label every time it changes (initial render, optimistic update, server reconciliation, and rollback).

### Informational — not fixed this pass (out of narrow-fix scope)

1. Every page has two `<h1>` elements (navbar logo + page content) — sitewide navbar semantics change, broader than this pass. **Still open, tracked as a separate sitewide follow-up — not addressed by the PR #27 review follow-up (§11).**
2. ~~`BlueprintCard` renders a `<footer>` landmark per card — shared-component rename, broader than this pass.~~ **Corrected during PR #27 review — see the Landmarks row in §5 and §11.2. This was never a real landmark issue: card-local `<footer>` elements nested in `<article>` carry no landmark role under the HTML→ARIA mapping, and only the one page-level footer exposes `contentinfo`. No follow-up needed.**

---

## 8. Fixes implemented — files changed

- `css/pages/auth/auth.css` — `.auth-forgot a` touch-target fix.
- `css/layout/navbar.css` — `.navbar` CLS min-height reservation (base + `@media (max-width: 700px)`).
- `css/layout/footer.css` — `.footer` CLS min-height reservation (base + `@media (max-width: 900px)` + `@media (max-width: 560px)`).
- `js/components/BlueprintCard.js` — image-link `aria-label` now includes the stage badge text.
- `js/pages/build/renderLike.js` — like-button `aria-label` now includes the live count.

All five are small, single-concern, CSS/markup-level or single-attribute JS changes. None change database behavior, workflow, or broad visual design; the dark design system and portfolio presentation are untouched.

## 9. Regression tests added

- `tests/a11yPerfPass27A5.test.html` (new) — asserts the login touch-target fix, the navbar/footer `min-height` reservation (existence and approximate real value, guarding against a future revert to a token non-zero value that wouldn't actually prevent the shift), and the BlueprintCard accessible-name fix, against the real shipped CSS/JS.
- `tests/like.test.html` (extended, 3 new cases) — asserts the like button's `aria-label` includes the count on initial render (plural and singular count wording) and stays in sync after a click updates the count.

Full suite: **1562/1562 passing** (1551 baseline + 11 new), all 8 static checks passing, after these changes.

---

## 10. After-fix verification

Draft PR: [#27](https://github.com/Fan1dude/Specbound/pull/27). Cloudflare Preview: `https://27a-a11y-perf-pass.specbound.pages.dev`, confirmed live and serving this branch's commit (`7cb308f`) — spot-checked via `getComputedStyle()` on `#navbar`/`#footer` returning the expected `min-height: 79px` / `228px` before re-running Lighthouse. Same tool, same flags, same 3-runs-per-page methodology as §3, run 2026-08-15.

**Important comparability note:** the "before" numbers in §3 are from **production**; the "after" numbers below are from the **Cloudflare Preview**, because the fix isn't live on production yet. These are not a perfectly controlled A/B — see the two environment-driven deltas called out below that are **not** caused by this PR's changes.

| Metric | Home (before → after) | Explore (before → after) | Public build page (before → after) | Login (before → after) |
|---|---|---|---|---|
| Performance | 73 → 85 | 70 → 91 | 61 → 73 | 72 → 85 |
| Accessibility | 100 → 100 | 100 → 100 | 100 → 100 | **95 → 100** |
| Best Practices | 92 → 96 | 92 → 96 | 92 → 96 | 92 → 96 |
| SEO | 100 → **69** | 100 → **69** | 100 → **66** | 66 → 66 |
| LCP (ms, median) | 4615 → 3483 | 4624 → 2891 | 5427 → 5138 | 3776 → 3484 |
| **CLS (median)** | **0 → 0.025** | **0.195 → 0.002** | **0.282 → 0.076** | **0.229 → 0.017** |
| Total Blocking Time | 0 → 0 | 0 → 0 | 0 → 0 | 0 → 0 |
| Transfer (KB) | 424 → 409 | 1891 → 1876 | 454 → 443 | 370 → 359 |

### CLS — the fix's direct target — confirmed working

CLS dropped sharply on every page: Explore 0.195→0.002, the public build page 0.282→0.076, Login 0.229→0.017. CLS is a pure layout-timing measurement, not sensitive to CDN edge location or network conditions the way LCP/Performance-score are, so this drop is attributable to the `min-height` reservation fix, not an environment artifact. The build page's remaining 0.076 is real and non-zero — smaller than before, but the reservation isn't a perfect match for every possible content height on that page (its `.navbar-inner`/`.footer-inner` content can vary slightly, e.g. a long build title wrapping); it is a large, clearly attributable improvement, not a claim of full elimination.

### Login accessibility — 95 → 100 — confirmed fixed

The one Lighthouse accessibility finding from §3 (`target-size` on the "Forgot password?" link) is gone; Login's accessibility score is now 100. No other page's accessibility score changed (Home/Explore/build were already 100).

### Two deltas that are environment artifacts, not caused by this PR

- **SEO dropped to 69/69/66 on Home/Explore/build.** Lighthouse's `is-crawlable` audit failed on the preview with "Page is blocked from indexing" — Cloudflare Pages preview deployments are blocked from indexing by the platform itself, independent of anything in this repository. This is expected preview behavior, not a regression, and not something to "fix" (doing so would mean making a preview URL indexable, which is wrong). Login's SEO score is unchanged (66→66) because it was already explained by its own intentional `noindex` (§3) on both environments.
- **Best Practices rose from 92 to 96 on every page.** Diffing the audit failures: production failed both `errors-in-console` and `inspector-issues`; the preview only fails `errors-in-console`. The remaining console-error finding is present on both environments and unrelated to this PR's changes — not chased here, consistent with the performance-fix policy's instruction to treat Cloudflare-injected script cost separately from repository-owned code and not change CDN/Cloudflare configuration in this PR.
- **The rest of the Performance-score movement (LCP, transfer size, overall category score) likely reflects a mix of the CLS improvement (a real scoring component) and ordinary environment noise between production and a different edge deployment** (e.g. Explore's LCP range was 2628–5218ms across 3 preview runs, wider than its production range) — it is not claimed as a verified performance win beyond the CLS figure itself.

### Automated/static re-verification

- Full browser regression suite: **1562/1562 passing** (unchanged from the pre-push local run).
- All 8 static checks: passing (unchanged).
- No new console errors attributable to this PR's changes were found on the preview (the one pre-existing `errors-in-console` Best Practices finding above is present on both environments and predates this PR).
- Desktop (1280px) and mobile (375px) visual check of the CLS fix: confirmed via `getComputedStyle()` that `#navbar`/`#footer` reserve non-zero height matching each breakpoint before content loads, on the live preview.
- No temporary reports containing sensitive URLs or data were committed — all raw Lighthouse JSON output and intermediate aggregation scripts live only in the local scratchpad directory (outside this git worktree), never staged or committed.

---

## 11. PR #27 review follow-up (2026-08-15)

An independent review of draft PR #27 (base `38ae621`, head `d99f9c7`) found two real, small defects in this PR's own fixes (F1, F2 below) and one factual overstatement in this document (F3 below, corrected in §5 and §7 above rather than here). This section records what changed and why. **It does not touch or reinterpret the historical Lighthouse measurements in §3/§10** — those remain the record of what was measured on 2026-08-15 before this follow-up.

### 11.1 F1 — Forgot-password link overlapped the password input

The original touch-target fix (`.auth-forgot a { display: inline-block; margin: calc(var(--space-0) * -1); padding: var(--space-0); }`) reused the negative-margin/padding technique from `.footer-group a`/`button` without accounting for a difference in context: `.auth-forgot`'s own `margin-top: calc(var(--space-3) * -1)` already pulls it flush (0px gap) against the password field, so the link's *own* negative top margin pulled its padded hit-area a further 4px upward, into the password input's own box.

**Fix:** replaced the negative-margin/padding technique with `display: inline-flex; align-items: center; min-height: 24px; padding: 0 var(--space-0);` — no negative margin at all, so the box can only grow downward within `.auth-forgot`'s own normal flow, never upward into the input above.

**Real measurements** (login page, real DOM, desktop width — captured via `tests/a11yPerfPass27A5.test.html`, matching methodology used throughout this audit):

| Metric | Before (F1) | After |
|---|---|---|
| Link height | 31.8px | 24.0px |
| Link width | 126.4px | 131.2px |
| Link's own top margin | `-4px` | `0px` |
| Password-input-bottom vs. link-top | password bottom 569.19px, link top 565.19px (**link starts 4px above the input's own bottom — overlap**) | password bottom 563.47px, link top 563.47px (**exact match, zero gap, zero overlap**) |
| Gap to submit button | 28.2px | 32.0px |

Both dimensions of the "after" box clear the WCAG 2.5.8 AA 24×24px minimum; it no longer overlaps the password input at any pixel, and the gap to the submit button widened slightly rather than shrinking.

### 11.2 F2 — Skip-link was invisible and pointer-unreachable behind the navbar

`.skip-link` (`css/base/reset.css`) and `.navbar` (`css/layout/navbar.css`) shared `z-index: 1000`. With tied z-index, paint order falls back to DOM order — the navbar (inserted later in `<body>` by `loadNavbar()`, `js/core/layout.js`) painted over the skip-link whenever it was focused, because both sit in the same top-left region of the page. A sighted keyboard user tabbing to the skip-link got no visible confirmation focus moved there, and a pointer user clicking at its expected location hit the navbar's logo link instead. Activation itself (Enter/click navigating to `#main`) was never broken — this was purely a visual/pointer-hit-testing defect.

**Fix:** `.skip-link`'s `z-index` raised to `1001`, one above the navbar's `1000`. No other change; the navbar itself is untouched.

**Real measurements** (real skip-link + real navbar markup, inserted as the first two children of `<body>` to match production exactly, focused via a real DOM `.focus()` call and measured after `.skip-link`'s own `transition: top .15s ease` completes — captured via `tests/a11yPerfPass27A5.test.html`):

| Check | Before (F2) | After |
|---|---|---|
| `.skip-link` z-index vs. `.navbar` z-index | 1000 vs. 1000 (tied) | 1001 vs. 1000 (skip-link wins) |
| Pointer hit-test at the focused skip-link's own visual center (`document.elementFromPoint`) | resolved to the navbar (confirmed live on the PR #27 preview during review, via a real Tab press + `elementFromPoint`) | resolves to the skip-link itself |

### 11.3 F3 — Landmark-proliferation claim corrected, not a code fix

No code change; see §5 (Landmarks row) and §7 (Informational finding #2) above for the corrected finding text. Recorded here as an entry in this document's own audit trail: the original claim ("multiple non-page `<footer>` landmarks per page") was inaccurate — only the one page-level `<footer>` exposes a `contentinfo` landmark; card-local `<footer>` elements nested in `<article>` carry no landmark role under the HTML→ARIA mapping.

### 11.4 Explicitly not addressed in this follow-up

The duplicate-`<h1>` finding (§5, §7 informational item 1 — navbar logo `<h1>` + page content `<h1>` on every page) remains open, unfixed, and out of scope here by design — it requires a sitewide navbar semantics change and is tracked as a separate follow-up, not part of this PR.

### 11.5 Regression tests

`tests/a11yPerfPass27A5.test.html` extended with 6 new assertions (9→15 total in this file):
- F1: link ≥24px tall, ≥24px wide, no negative top margin, no pixel overlap with the password input, no pixel overlap with the submit button — against the real `.auth-form` markup (email group, password group, forgot link, submit button, in real DOM order).
- F2: skip-link z-index > navbar z-index; the two elements' boxes actually overlap in the fixture (proving the z-index check isn't vacuous); pointer hit-test at the focused skip-link's center resolves to the skip-link, not the navbar — against real skip-link + navbar markup inserted as the first children of `<body>`, matching production structure.
- F3: the results document no longer contains the old inaccurate landmark claim, and does contain the corrected one — a content-fingerprint guard against the doc regressing to the same overstatement.

All three regressions were reproduced locally (reverting each fix in turn) and confirmed to fail the newly-added assertions before being restored byte-for-byte via `git checkout`; see the delivery report for this follow-up for the exact before/after test counts.
