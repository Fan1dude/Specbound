# Milestone 8D — Accessibility & Polish: Architecture Proposal

**Status:** Architecture only. No implementation. Awaiting review.

**Goal (as given):** Bring Specbound to production-quality usability without changing its overall design or adding new features.

**Method:** This audit re-verifies every accessibility/responsive/dead-code claim from `docs/MILESTONE_8_AUDIT.md` (written before 8A/8B/8C shipped) against the *current* code, and extends it into the specific sub-areas the user asked for that the original pass only lightly covered (focus management in depth, live regions, mobile drawer/scroll-lock behavior, measured contrast ratios, dead icon/CSS assets). Three parallel read-only audits fed this document: keyboard/focus/screen-reader, color/contrast/mobile CSS, and dead-UI/consistency. Every finding below was checked against current file contents, not assumed from the old doc — findings are tagged **[confirmed]** (old audit was right, unchanged), **[changed]** (old audit was right but code has since shifted), or **[new]** (not in the old audit).

Findings are numbered by category prefix so later phases/PRs can reference them: **K**=Keyboard, **F**=Focus management, **S**=Screen reader, **C**=Color/contrast, **M**=Mobile, **X**=Consistency, **D**=Dead UI.

---

## Executive summary

- **62 findings total**: 5 Critical/High-critical, 21 High, 25 Medium, 11 Low.
- Nothing found requires a real design change — every proposed fix is additive (new attribute, new helper call, new CSS rule, new file deletion) except **C1** (button text-on-brand-color contrast), which technically requires nudging two color values and is flagged for explicit sign-off since it's the one item that brushes against "redesign."
- The single most consequential structural gap is **focus management**: outside two dropdowns, the entire app never programmatically moves focus — not after page loads, not after errors, not after Retry. This is one root cause with many symptoms (F1–F3), cheaper to fix once as a pattern than per-page.
- The user's named "dashboard interpolation issue" (**X1**) is confirmed exactly as before, untouched by 8A/8B/8C because `renderDashboard.js` was never in their file sets — and a second, previously-unflagged instance of the identical bug exists in `js/features/featured.js` (**X2**), which *was* touched by 8C's performance work but for a different reason, so this escaping gap survived that pass too.
- Dead code confirmed essentially unchanged since the old audit (22 empty JS files, 18 empty component-scaffold dirs, 4 empty CSS files, 5 empty category pages, 4 empty legal pages) plus new findings: 2 more imported-but-unused CSS files, 5 unreferenced brand/placeholder assets, and no favicon wired anywhere.

---

## 1. Keyboard accessibility

### K1 — No skip-to-main-content link anywhere **[new]**
- **Severity:** High
- **User impact:** Every page forces a keyboard user to tab through 6–8 navbar stops (logo, hamburger toggle, search input, Explore/Workshop/Publish links, notification bell, builder menu) before reaching page content — on *every* full-page navigation, since this app has no client-side routing (confirmed: the only `history.*` call in the codebase is a `replaceState` for the search query string, not a router).
- **Proposed fix:** Add one visually-hidden-until-focused `<a href="#main" class="skip-link">Skip to content</a>` as the first element in `<body>` on every page template, plus `id="main"` on each page's `<main>` element (already present as a semantic wrapper on most pages — verify/add where missing).
- **Files affected:** `js/core/layout.js` (or each `pages/*.html`, whichever the team prefers as the insertion point — recommend `layout.js`'s navbar render since it's the one shared entry point already used for the footer), one new CSS rule in `css/layout/navbar.css` or `css/base/reset.css`.
- **Behavior change:** No visible change for mouse/touch users (link is off-screen until focused). Adds one new Tab stop for keyboard users, always additive.
- **Verification:** Tab from a fresh page load on 3 representative pages (home, build, settings) and confirm the skip link is the very first focus stop, is visible when focused, and jumps focus to `<main>` when activated.

### K2 — Footer navigation links are inert `<p>` tags, not `<a>` **[confirmed, unchanged]**
- **Severity:** High
- **User impact:** "Explore", "Publish", "Categories", "Workshop", "Profiles", "Privacy", "Terms" render styled to look like links on every page's footer but are completely unreachable by keyboard and inert to click — a sighted mouse user gets no cursor/hover feedback either. This is also why the (empty) legal pages have zero live references anywhere in the app (see **D2**).
- **Proposed fix:** Change each `<p>` to a real `<a href="...">` in `loadFooter()`.
- **Files affected:** `js/core/layout.js:160-185`.
- **Behavior change:** Yes, narrowly: these become real, clickable/focusable links (currently non-functional). No visual change if link styling matches existing `<p>` styling (verify `css/layout/footer.css` has an `a` rule or add one matching the current text style).
- **Verification:** Tab through the footer on any page, confirm each item is a focusable, activatable link; confirm visual appearance is unchanged (screenshot diff) unless intentionally now hover-styled.

### K3 — Modal focus-trap infrastructure is entirely absent, but no *live* gap currently exists **[confirmed, unchanged]**
- **Severity:** Medium
- **User impact:** None today — every confirm-style interaction in the app (`js/pages/editor/app.js` Unpublish, `js/pages/build/deleteRevision.js`, `renderGallerySection.js` delete image, `renderComments.js` delete comment) uses the browser's native `confirm()`, which the browser itself handles correctly for focus/keyboard. The risk is latent: `js/components/Modal.js` is a 0-byte stub and `css/components/modal.css` is fully unused (cross-ref **D-list**), so if any future work reaches for "the modal component," there is no focus-trap/Escape/return-focus logic to reuse.
- **Proposed fix:** No code change required for 8D. Recommend documenting (in this file or a code comment on the empty stub) that `Modal.js` must not be used as-is until focus-trap/Escape/focus-return are implemented, so a future feature doesn't silently ship an inaccessible dialog.
- **Files affected:** None (documentation only) — or delete the dead stub entirely as part of **D-cleanup**, which removes the false signal that a ready-to-use modal exists.
- **Behavior change:** None.
- **Verification:** N/A (no code change) or, if deleted, confirm zero importers via grep before removal (see D-cleanup verification).

### K4 — Activity feed tabs lack `role="tablist"`/`role="tab"`/`aria-selected` **[confirmed, unchanged]**
- **Severity:** Medium
- **User impact:** The Following/Explore toggle on the homepage (`index.html`) is keyboard-reachable (real `<button>`s) but announces as two unrelated buttons rather than a tab pair, and nothing tells a screen-reader user which scope is currently active — unlike the editor's tabs, which correctly implement the full pattern already (usable as the in-repo reference).
- **Proposed fix:** Add `role="tablist"` to the container, `role="tab"` + `aria-selected="true|false"` to each button, matching `pages/build/edit.html`'s existing pattern; update `setActiveTab()` to toggle `aria-selected` alongside its existing `classList.toggle`.
- **Files affected:** `index.html` (tab markup), `js/pages/home/renderActivityFeed.js` (`setActiveTab()`).
- **Behavior change:** No visible/functional change — additive ARIA attributes only.
- **Verification:** Inspect computed accessibility tree (browser devtools) before/after; confirm `aria-selected` flips correctly on click for both tabs.

### K5 — Explore filter pills / lifecycle buttons lack `aria-pressed` **[confirmed, unchanged]**
- **Severity:** Medium
- **User impact:** Toggle-style filter buttons only convey active/inactive via a CSS class; Like/Save/Follow buttons in the same app correctly set `aria-pressed` for the identical UI pattern, so this is an inconsistency, not a novel technique to introduce.
- **Proposed fix:** Add `aria-pressed` toggling to `setActiveButton()`, mirroring the existing Like/Save/Follow implementation.
- **Files affected:** `js/pages/explore/app.js` (`setActiveButton()`, lines ~297-304).
- **Behavior change:** None visible — additive ARIA only.
- **Verification:** Toggle each filter pill, confirm `aria-pressed` reflects state in devtools accessibility tree.

### K6 — Editor tabs implement `role="tab"` but no arrow-key navigation **[new]**
- **Severity:** Low-Medium
- **User impact:** Minor deviation from the WAI-ARIA Tabs pattern — tabs are still fully keyboard-operable via sequential Tab + Enter/Space (real `<button>`s), just missing the "ArrowLeft/ArrowRight moves between tabs" convenience some screen-reader/keyboard power users expect once a tab is focused.
- **Proposed fix:** Add an arrow-key handler in the tabs' click-listener setup that moves focus + activates the adjacent tab on ArrowLeft/ArrowRight (wrapping at the ends), matching the standard pattern.
- **Files affected:** `js/pages/editor/editorTabs.js`.
- **Behavior change:** Additive only — existing click/Tab/Enter behavior unchanged, new arrow-key path added.
- **Verification:** Focus a tab, press ArrowRight/ArrowLeft, confirm focus and active-tab state move correctly and wrap at the boundaries.

### K7 — Featured Spotlight carousel auto-advances every 6s with no pause control **[new]**
- **Severity:** Medium
- **User impact:** WCAG 2.2.2 (Pause, Stop, Hide) territory — content that moves/updates automatically for more than 5 seconds needs a way to pause it. Currently `startCarousel()` runs an uninterruptible `setInterval`; a user who needs more than 6 seconds to read a slide (low vision, cognitive disability, screen magnifier) never gets a stable view without manually clicking Prev/Next repeatedly to interrupt it.
- **Proposed fix:** Add a pause on hover/focus-within (cheap, common pattern: clear the interval on `mouseenter`/`focusin`, restart on `mouseleave`/`focusout`), or a persistent pause/play toggle button next to the existing Prev/Next controls.
- **Files affected:** `js/features/featured.js`, `index.html` (if adding a visible pause button).
- **Behavior change:** Yes, narrowly: the carousel stops auto-advancing while hovered/focused (currently it never stops). No change to the default auto-advancing behavior otherwise.
- **Verification:** Hover over the spotlight, confirm auto-advance pauses; move away, confirm it resumes; if a pause button is added, confirm it's keyboard-operable and correctly labeled.

---

## 2. Focus management

### F1 — No page ever moves focus after a loading→loaded or loading→error transition **[new, app-wide]**
- **Severity:** High
- **User impact:** A repo-wide grep for `.focus()` returns exactly 2 hits in the entire `js/` tree, both inside the two dropdown Escape-handlers. Every other page (Dashboard, Workshop, Build, Profile, Explore, Search, Editor, Notifications, Follow lists) goes from a "Loading…" placeholder to real content or an error card with zero screen-reader announcement — an AT user navigating straight to a page hears nothing change and has to manually re-explore to discover whether it loaded, is empty, or failed.
- **Proposed fix:** Two complementary, additive fixes rather than a per-page rewrite: (a) add `aria-live="polite"` to the shared loading/content containers driven by `js/utils/listState.js` and the equivalent hand-rolled containers (`#commentsList`, `#notificationDropdownList`, etc. — see **S7/S-list**), so content changes are announced without any JS logic change; (b) for pages whose primary content is a heading-led section (Dashboard, Workshop, Build, Profile), move focus to that page's main heading only on the *error* path (not the success path, to avoid disorienting a sighted-but-AT-using reader on every normal load) once `listState.renderErrorState()` fires.
- **Files affected:** `js/utils/listState.js` (`renderLoadingState`/`renderErrorState` — add `aria-live` to the container they write into, add an optional `focusTarget` param for the error case), plus each of its 4 current callers (`loadDashboard.js`, `loadWorkshop.js`, `loadBuild.js`, `settings/app.js`) to pass a heading selector; leave the hand-rolled list renderers (comments/follow-list/notifications/activity-feed/gallery) with just the `aria-live` addition for 8D, deferring their retry-button unification to **X5**.
- **Behavior change:** No visible change for sighted mouse users. Screen-reader users get new announcements on load/error; keyboard focus visibly jumps to a heading only on the error path (a deliberate, minor, additive UX change — flagging for review since it's the one part of this finding that's user-visible to keyboard users, not purely additive-invisible).
- **Verification:** With a screen reader (or the browser's accessibility-tree inspector plus a live-region test harness), load each of the 4 primary-pattern pages normally (confirm no disruptive announcement on success) and with a simulated failure (confirm the error is announced and, where applicable, focus lands on the page heading).

### F2 — Clicking "Try Again" (listState.js retry) strands focus **[new]**
- **Severity:** High
- **User impact:** `renderErrorState()`'s Retry button re-invokes the whole page-load function, which replaces the container's `innerHTML` — destroying the very button that had focus. Neither `listState.js` nor its 4 callers ever call `.focus()` afterward, so keyboard focus silently drops to `<body>` with no landmark picked up next. This directly affects Dashboard, Workshop, Settings, and Build's revision-history retry path (the four current adopters of this 8B-era shared helper).
- **Proposed fix:** After a successful retry re-render, move focus to the re-rendered section's heading (same target as **F1**'s error-path fix — these two should share one small helper so the fix is written once). On a *repeated* failure (retry fails again), move focus to the new error message itself so the user immediately hears/sees the fresh failure state rather than being stranded.
- **Files affected:** `js/utils/listState.js`, and the 4 current callers listed in F1.
- **Behavior change:** Yes, minor and additive: focus now lands somewhere meaningful after Retry instead of nowhere. No change to what Retry actually does.
- **Verification:** Simulate a load failure, click Retry, confirm focus lands on the newly-rendered heading (success case) or the new error message (repeated-failure case) rather than being lost to `<body>`.

### F3 — Mobile nav drawer has no focus handling of any kind **[new]**
- **Severity:** Medium-High (shared with **M3** — this is the keyboard/focus half of that finding; full detail lives in the Mobile section to avoid duplicating the fix description)
- **User impact / proposed fix / files / behavior change / verification:** See **M3**.

*(Note: focus restoration after closing the notification bell and builder/account dropdowns is already correctly implemented — `js/core/notificationBell.js` and `js/core/layout.js` both call `.focus()` on the triggering button inside their Escape handlers. Confirmed unchanged from the old audit, cited here as a working reference pattern, not a finding.)*

---

## 3. Screen reader support

### S1 — Toasts have no `role`/`aria-live` **[confirmed, unchanged]**
- **Severity:** High
- **User impact:** The app's primary async-feedback mechanism (60+ call sites: likes, saves, follows, comments, uploads, settings, publish/unpublish, gallery) is entirely silent to screen-reader users. Toast *content* itself is otherwise well-built (4 consistent types, consistent tone/punctuation — confirmed clean, no fix needed there).
- **Proposed fix:** Add `role="status"` (for success/info) or `role="alert"` (for error/warning) to each toast element as it's created, or simpler and equally correct: put a single `aria-live="polite"` (or `"assertive"` for errors) on the shared `#toastContainer` itself so all toasts inherit the live region regardless of type.
- **Files affected:** `js/core/toast.js` (toast element creation), `js/core/layout.js` (`ensureToastContainer()`).
- **Behavior change:** None visible. Purely additive ARIA.
- **Verification:** Trigger a success and an error toast with a screen reader running (or devtools live-region simulation), confirm both are announced without requiring focus to move.

### S2 — 7 of 8 Settings form fields have no programmatic label association **[confirmed, unchanged]**
- **Severity:** High
- **User impact:** Display Name, Username, Bio, Location, Website, GitHub, YouTube fields have visible `<label>` text but no `for`/`id` linkage (the Avatar field is correctly linked, proving the team knows the pattern) — a screen-reader user focusing any of these 7 inputs hears no label at all.
- **Proposed fix:** Add matching `for`/`id` pairs (the `id`s already exist on the inputs; just add `for` to each `<label>`).
- **Files affected:** `pages/settings.html`.
- **Behavior change:** None visible.
- **Verification:** Click each label's text and confirm focus moves to its input (a quick manual proxy for correct association); confirm with the accessibility tree that each input now has an accessible name.

### S3 — ComponentAutocomplete's ARIA combobox pattern is incomplete **[confirmed, unchanged]**
- **Severity:** High
- **User impact:** Used in the editor's Specifications tab, a primary form-heavy interaction. Keyboard interaction itself already works (Arrow keys/Enter/Escape all correctly wired), but the results list has no `role="listbox"`/`id` to hang `aria-controls` off of, and the highlighted option is only tracked via a CSS class, never `aria-activedescendant` — a screen-reader user navigating options hears no announcement of which one is highlighted.
- **Proposed fix:** Give the results container `role="listbox"` and a stable `id`; set `aria-controls` on the input to that id; set `aria-activedescendant` on the input to the currently-highlighted option's `id` inside `updateActiveResult()`.
- **Files affected:** `js/components/ComponentAutocomplete.js`.
- **Behavior change:** None visible/functional — additive ARIA wiring on top of already-working interaction logic.
- **Verification:** With a screen reader, open the autocomplete, arrow through results, confirm each option is announced as it's highlighted.

### S4 — Editor's autosave status has no `role`/`aria-live` **[new]**
- **Severity:** High
- **User impact:** `#editorSaveStatus` cycles through "Unsaved changes" / "Saving…" / **"Couldn't save — retrying"** / "Last saved …" — this is the editor's primary data-loss-prevention signal (the exact concern 8B's reliability work targeted for other failure modes). A screen-reader user currently gets zero notification when autosave starts silently failing and retrying.
- **Proposed fix:** Add `role="status"` and `aria-live="polite"` to the `#editorSaveStatus` element.
- **Files affected:** `pages/build/edit.html` (element), `js/pages/editor/editorStatus.js` (no logic change needed, just the static attribute).
- **Behavior change:** None visible. Purely additive.
- **Verification:** Trigger a simulated autosave failure, confirm the status change is announced without requiring the user to have focus on that element.

### S5 — Like button has no accessible name **[new]**
- **Severity:** High
- **User impact:** The button's only content is an `aria-hidden` heart glyph plus a bare number (`<span id="likeCount">0</span>`) — since the icon is correctly hidden from AT, the button's computed accessible name is just the count. A screen reader announces "0, toggle button" with zero indication this is a Like control, on the single most-visited page type in the app (every build page). This is a materially worse gap than the aria-pressed items above (K5/K4), which at least have descriptive visible text.
- **Proposed fix:** Add `aria-label="Like this project"` (toggling to reflect state if desired, e.g. "Unlike this project" when pressed) to the button.
- **Files affected:** `pages/build/build.html` (or wherever the like button's static markup lives), `js/pages/build/renderLike.js` (if the label needs to change with state).
- **Behavior change:** None visible. Additive ARIA only.
- **Verification:** Focus the Like button with a screen reader running, confirm it announces as "Like this project, button" (or equivalent), not just a bare number.

### S6 — Navbar search input has no label **[new, sitewide]**
- **Severity:** High
- **User impact:** The `.search-bar` input rendered by `loadNavbar()` on every single page has no `id`, no `<label>`, and no `aria-label` — only a placeholder, which is not a reliable accessible name (disappears on focus/input, and some AT doesn't expose it as a name at all). Contrast with `pages/search.html`'s own search input, which correctly uses a `.sr-only`-labeled `<label for="searchPageInput">`.
- **Proposed fix:** Add `aria-label="Search builds, builders, parts"` (or reuse the sr-only label pattern already proven on the search page) to the navbar search input.
- **Files affected:** `js/core/layout.js` (navbar render).
- **Behavior change:** None visible. Additive ARIA only.
- **Verification:** Focus the navbar search input on any page with a screen reader, confirm it announces a meaningful name.

### S7 — Hint elements (`#commentFormHint`, `#likeHint`, `#saveHint`, `#followHint`) lack `aria-live` **[confirmed, unchanged]**
- **Severity:** Medium
- **User impact:** These already correctly use visible text (never `title=` attributes — a real project-wide strength), but a screen-reader user isn't notified *when* they appear (e.g., "Write something before posting" on an empty comment submit).
- **Proposed fix:** Add `aria-live="polite"` to each hint container.
- **Files affected:** `js/pages/build/renderComments.js`, `pages/build/build.html` (likeHint/saveHint), `js/pages/profile/renderFollow.js`/`pages/profile.html` (followHint).
- **Behavior change:** None visible. Additive ARIA only.
- **Verification:** Trigger each hint's appearance condition with a screen reader running, confirm each is announced.

### S8 — No `aria-describedby` anywhere linking hints/errors to their controls **[new, sitewide pattern]**
- **Severity:** Medium
- **User impact:** Even once S7 lands, a screen-reader user focused directly on (say) the comment textarea won't hear the hint unless they separately discover it via linear navigation — `aria-describedby` is what makes a hint "belong" to its control from the control's own focus point.
- **Proposed fix:** Add `aria-describedby="commentFormHint"` (etc.) to each relevant input, pointing at the hint element's `id` (ids already exist).
- **Files affected:** Same files as S7, plus Settings' avatar upload hint if one exists.
- **Behavior change:** None visible. Additive ARIA only.
- **Verification:** Focus each control with a screen reader, confirm the associated hint text is read as part of the control's description (even before the hint is visually shown, which is standard/expected `aria-describedby` behavior).

### S9 — Comment textarea and Editor Resource inputs have no `<label>` at all **[new]**
- **Severity:** Medium
- **User impact:** `#commentBody` (comment composer) and the Editor's Resource-row label/URL inputs rely on placeholder text only — no `<label>` element exists for either. The Resource case is worse: it's a repeating-row form (multiple identically-placeholdered inputs), so a screen-reader user can't distinguish "Resource 1's URL" from "Resource 2's URL" by label alone.
- **Proposed fix:** Add visually-hidden (`.sr-only`, matching the pattern already proven on `pages/search.html`) `<label>` elements for each, using per-row unique `id`s for the Resource inputs.
- **Files affected:** `js/pages/build/renderComments.js` (compose form markup), `js/pages/editor/renderResourcesSection.js` (row markup).
- **Behavior change:** None visible (sr-only labels are invisible by design).
- **Verification:** Focus each input with a screen reader, confirm a meaningful, per-row-unique name is announced.

### S10 — `featured.js`'s image `alt` attribute is unescaped **[new; cross-ref X2 for the full fix, since it's one bug with both a11y and injection consequences]**
- **Severity:** High (accessible-name integrity + injection risk — full detail and fix under **X2**)
- **User impact / proposed fix / files / behavior change / verification:** See **X2**.

### S11 — `add-revision.html`/`edit-revision.html` forms are almost entirely unlabeled **[new, but currently unreachable]**
- **Severity:** Low (would be Medium-High if reachable — see **D-list** for the orphan status)
- **User impact:** None currently — these pages have zero in-app links pointing to them (same orphan category as `continue.html`). If ever relinked without this fix, every field (title, description, version, timeSpent, image upload) except the "Build Progress" range input would be unlabeled.
- **Proposed fix:** Defer — fix only if/when these pages are intentionally relinked (a product decision, not an 8D task); note this file's status so nobody assumes the pages are already accessible.
- **Files affected:** N/A for 8D.
- **Behavior change:** N/A.
- **Verification:** N/A — re-audit at relink time.

---

## 4. Color and contrast

### C1 — White button text on `--color-primary`/`--color-danger` backgrounds fails WCAG AA **[new, systemic]**
- **Severity:** High — **flagged for explicit sign-off, this is the one item that touches visual design**
- **User impact:** Measured, not estimated: `#fff` text on `--color-primary` (`#4f7dff`) computes to **3.68:1** (needs 4.5:1 for normal-size text); on hover (`--color-primary-hover:#6a91ff`) it drops further to **2.96:1**. Same pattern on `--color-danger` (`#ef4444` → 3.76:1, hover `#f56767` → 3.00:1). This affects the app's primary CTA button (`.btn-primary`), destructive-action button (`.btn-danger`), the active-pagination indicator, the Follow button, the active Activity-Feed tab, and the unread-notification-count badge — all real interactive/informational text, not decoration, on every page.
- **Proposed fix:** Two non-redesign-shaped options, either acceptable: (a) darken `--color-primary`/`--color-danger` by roughly 10-15% (a token-value change, not a layout/visual-system change — buttons keep their exact current shape, just a slightly deeper blue/red); or (b) keep the existing color values and switch the *text* color on these specific backgrounds to a near-black instead of pure white. Recommend (a) since the current hue reads as the brand color and (b) would visibly change button appearance more.
- **Files affected:** `css/base/tokens.css` (`--color-primary`, `--color-primary-hover`, `--color-danger`, `--color-danger-hover` and/or their consuming component rules in `button.css`, `pagination.css`, `profile.css`, `home.css`, `notification-bell.css`).
- **Behavior change:** Yes — a small, visible color shift on every primary/danger button and the notification badge, app-wide. This is the one 8D item that should get explicit user approval before implementation, per the "no redesign" constraint — recommend either approving the token nudge or deferring this specific item to the eventual visual redesign pass (it was already flagged, unmeasured, for that pass in the original Milestone 8 audit).
- **Verification:** Recompute contrast ratios for the new values against WCAG AA (4.5:1) before implementation; visually diff every affected button/badge before/after to confirm the change reads as "slightly deeper," not "different color."

### C2 — `--color-border`/`--color-border-strong` fail the 3:1 non-text contrast requirement **[confirmed, now measured]**
- **Severity:** Medium
- **User impact:** Measured at **1.19:1** and **1.43:1** respectively against the page background — both fail SC 1.4.11's 3:1 bar for identifying UI component boundaries. Concretely: every text input's border (`css/components/form.css`) is essentially invisible by contrast math, relying on an almost-imperceptible background shift instead.
- **Proposed fix:** Increase the alpha value on both tokens until they clear 3:1 (e.g., roughly 0.20-0.24 alpha instead of the current 0.08/0.14) — a token-only change, borders keep their current color/position, just become visible.
- **Files affected:** `css/base/tokens.css` (`--color-border`, `--color-border-strong`).
- **Behavior change:** Yes, minor and visible: form-field and card borders become slightly more visible app-wide. Lower-risk than C1 since it's a subtlety increase, not a hue change, but still a visible diff — recommend approval alongside C1, or independently if C1 is deferred.
- **Verification:** Recompute contrast against 3:1; visually confirm borders are now perceptible without looking "heavy" or changing the app's overall dark, low-contrast aesthetic more than necessary.

### C3 — `--color-text-muted` passes AA only marginally (~4.6:1) **[confirmed, now measured]**
- **Severity:** Medium
- **User impact:** Currently clears the 4.5:1 bar by roughly 0.13-0.15, used for real content (timestamps, hints, save-status text) in numerous places. Any future token or surface-color drift risks silently dropping it below AA.
- **Proposed fix:** Bump the alpha slightly (e.g., 0.46 → ~0.55-0.6) for headroom rather than leaving it balanced on the line. Low-risk, small visual change (muted text becomes a little more legible, not a color/hue change).
- **Files affected:** `css/base/tokens.css` (`--color-text-muted`).
- **Behavior change:** Yes, minor and visible (slightly more legible muted text) — bundle with C1/C2's sign-off ask since all three are the same class of "small necessary token nudge."
- **Verification:** Recompute contrast against 4.5:1 with real margin; spot-check readability on timestamps/hints across a few pages.

### C4 — Disabled form inputs have zero `:disabled` styling **[new]**
- **Severity:** Low-Medium
- **User impact:** Buttons consistently signal disabled state via `opacity` app-wide (a real, confirmed-consistent pattern), but `<input>`/`<textarea>`/`<select>` have no `:disabled` rule anywhere — combined with C2's already-faint borders, a disabled field may be difficult to distinguish from an enabled one.
- **Proposed fix:** Add a `:disabled` rule to the shared input styling (reduced opacity and/or a slightly different background, matching the existing button pattern for consistency).
- **Files affected:** `css/components/form.css`.
- **Behavior change:** Yes, but purely additive/visible-only-when-disabled — no currently-enabled UI changes appearance.
- **Verification:** Trigger a real disabled-input state (e.g., Settings' avatar/save fields after a failed profile load, per the 8B reliability fix) and visually confirm it now reads as clearly non-interactive.

### C5 — App is dark-only in practice; `light.css`/`dark.css` are both effectively dead **[new framing, corrects old audit's premise]**
- **Severity:** Low/Informational
- **User impact:** None currently — this isn't a bug, just a naming/architecture note. `css/themes/light.css` is scoped entirely to `html[data-theme="light"]`, but nothing in the codebase (grepped repo-wide) ever sets that attribute — so its rules never match anything at runtime. `css/themes/dark.css` is a separate, confirmed-empty file. There is exactly one active theme, defined directly on `:root` in `tokens.css`.
- **Proposed fix:** No functional fix needed for 8D. Recommend, as a documentation-only note (or fold into the **D-cleanup** file deletions), either deleting both dead theme files or renaming them to reflect that only one theme currently exists, so a future contributor doesn't assume light-mode support exists and try to "fix" it in isolation.
- **Files affected:** `css/themes/light.css`, `css/themes/dark.css` (if deleted as part of D-cleanup).
- **Behavior change:** None if deleted (confirmed zero live effect either way).
- **Verification:** Confirm via grep that `data-theme` is set nowhere before deleting `light.css`; confirm `styles.css` no longer references either file after deletion.

---

## 5. Mobile interaction polish

### M1 — Several touch targets are below ~44×44px **[confirmed unchanged, plus one new instance]**
- **Severity:** Medium
- **User impact:** Notification bell (40×40), modal close button (40×40, currently unreachable UI per K3 but worth fixing for whenever it is used), `.btn-small` (~34px tall — used by Follow/Unfollow row buttons, comment delete, gallery delete, saved-remove, and 4+ other call sites), and **[new]** Like/Save buttons on the build page (~35px tall) all fall short of the ~44px guidance. The nav hamburger toggle is correctly 44×44px, proving the team already applies the right size elsewhere.
- **Proposed fix:** Increase padding/min-height on `.btn-small`, the notification bell button, the modal close button, and `.like-btn`/`.save-btn` to reach ~44px effective tap area, without necessarily growing the visible glyph/text size (padding-only change keeps visual density similar).
- **Files affected:** `css/components/button.css` (`.btn-small`), `css/components/notification-bell.css`, `css/components/modal.css`, `css/pages/build/hero.css` (`.like-btn`, `.save-btn`).
- **Behavior change:** Yes, minor visual: these controls get slightly larger tap areas/padding. Low risk of layout breakage given they're mostly standalone buttons, not tightly packed rows — verify `.follow-row` and comment-item layouts don't wrap awkwardly at the new size.
- **Verification:** Measure rendered size in devtools at common mobile widths (375/414px) before/after; visually confirm no unwanted wrapping/overlap in follow-list rows, comment items, and gallery thumbnails.

### M2 — Builder/account dropdown doesn't actually go responsive on mobile (CSS cascade bug) **[confirmed, unchanged, byte-for-byte]**
- **Severity:** High
- **User impact:** `css/components/dropdown.css` declares `.builder-dropdown { position: absolute; ... }` unconditionally; `css/layout/navbar.css`'s mobile media query tries to override it to `position: static` at ≤900px, but since `dropdown.css` is `@import`ed *after* `navbar.css` in `css/styles.css`, the unconditional rule wins the cascade at equal specificity. The account menu renders as a floating absolutely-positioned box instead of the intended full-width static block on every signed-in page, on mobile. (The notification-bell dropdown has its own self-contained mobile override as the last rule in its own file and is correctly unaffected.)
- **Proposed fix:** Move the mobile static-position override into `dropdown.css` itself (after its own unconditional rule, so it wins on specificity-tie-by-source-order within the same file), or reorder the two `@import`s in `styles.css`.
- **Files affected:** `css/components/dropdown.css`, `css/styles.css` (if reordering instead).
- **Behavior change:** Yes — this fixes a bug, so the dropdown's actual mobile rendering changes (to the originally-intended full-width static layout). This is a bugfix restoring intended behavior, not a new design.
- **Verification:** Resize to ≤900px, open the builder/account dropdown, confirm it now renders full-width/static like the notification-bell dropdown does, matching the CSS's own already-written (but currently shadowed) intent.

### M3 — Mobile nav drawer has no scroll lock, no Escape-to-close, no click-outside-to-close, no focus trap **[new]**
- **Severity:** Medium-High
- **User impact:** The hamburger menu's entire JS implementation is a single `classList.toggle` + `aria-expanded` update — nothing else. Compare directly with the *same file*'s notification-bell and builder-dropdown handling, both of which correctly implement Escape, click-outside, and focus-return. The primary mobile navigation drawer itself has none of these, an inconsistency within the very file that demonstrates the correct pattern twice already. Additionally, repo-wide, there is no scroll-lock mechanism anywhere (`element.style.overflow` is never set in any `.js` file) — this affects the drawer specifically today, and will affect any future overlay (including a real modal, if `Modal.js` is ever implemented) unless fixed as a shared pattern.
- **Proposed fix:** Add, to the same `navToggle`/`navLinks` block in `layout.js`: an Escape-key listener that closes the menu and returns focus to the toggle button (mirroring the dropdown pattern already in the same file); a click-outside listener (same mirroring); and a scroll-lock toggle (`document.body.style.overflow = "hidden"` while open, restored on close) so background content doesn't scroll behind an open drawer.
- **Files affected:** `js/core/layout.js`.
- **Behavior change:** Yes, additive/correcting: the drawer gains new dismiss paths (Escape, click-outside) it didn't have before, plus scroll-locks while open. No change to how it's opened or its visual appearance.
- **Verification:** Open the mobile menu at a mobile viewport width; confirm Escape closes it and returns focus to the hamburger button; confirm clicking outside closes it; confirm the page behind it does not scroll while it's open; confirm normal link-clicking inside the drawer still navigates correctly.

### M4 — Horizontal overflow: mostly clean, one low-risk spot **[confirmed clean, one low new note]**
- **Severity:** Low
- **User impact:** No confirmed overflow bugs found from static analysis — the spec grid, the autocomplete results dropdown, and the footer grid all collapse safely. One low-confidence risk: Explore's sort `<select>` (`min-width: 180px`) sits in an unwrapped flex row that hasn't been device-tested at very narrow widths (320-375px).
- **Proposed fix:** Spot-check Explore's catalog/sort row on a real narrow device or emulator; add `flex-wrap: wrap` to that row only if actual overflow is observed (don't fix speculatively).
- **Files affected:** `css/pages/explore/explore.css` (`.catalog-sort`), only if confirmed.
- **Behavior change:** None unless a real bug is found and fixed, in which case: minor layout wrap at very narrow widths only.
- **Verification:** Load Explore at 320px and 375px widths, confirm no horizontal scrollbar/clipped content in the sort/filter row.

### M5 — No `env(safe-area-inset-*)` handling anywhere **[confirmed absent]**
- **Severity:** Low
- **User impact:** No confirmed clipping without a real notched-device test — flagged as a known gap, not a verified bug. The toast container (`position: fixed; bottom: 24px`) and the sticky navbar are the two elements that would benefit most if a real device issue is ever reported.
- **Proposed fix:** Defer unless a real device test shows clipping; if addressed, add `padding-bottom: max(24px, env(safe-area-inset-bottom))` (etc.) to the toast container as the one highest-value spot.
- **Files affected:** `css/components/toast.css`, if addressed.
- **Behavior change:** None on non-notched devices (the `env()` fallback is inert); minor additional spacing on notched devices only.
- **Verification:** Test on an actual notched device/simulator before deciding whether to implement; this is explicitly optional for 8D given zero confirmed impact.

### M6 — Inconsistent breakpoint values across the app **[confirmed, unchanged]**
- **Severity:** Medium
- **User impact:** No functional bug, but the dominant breakpoint set (500/600/650/700/720/900/1100px) is joined by unexplained one-offs (800px in footer/dashboard, 980px in Explore) with no evident reason for the divergence — a maintenance/consistency issue more than a user-facing one, though it can produce slightly different "feels" for where content reflows between adjacent pages.
- **Proposed fix:** Introduce CSS custom properties for the breakpoint values (e.g., `--bp-sm`, `--bp-md`, `--bp-lg` as documented reference values in a comment, since raw custom properties can't be used inside `@media` conditions without a preprocessor) and migrate the 800px/980px outliers to the nearest dominant value (900px in both cases) where doing so doesn't change the actual layout intent.
- **Files affected:** `css/layout/footer.css`, `css/pages/dashboard/dashboard.css`, `css/pages/explore/explore.css` (the 3 outlier files); optionally a new shared reference comment/token file.
- **Behavior change:** Minor — collapsing 800px→900px and 980px→900px shifts exactly where those 3 layouts reflow by a small margin. Recommend verifying each doesn't currently rely on its specific value for a reason not visible from the CSS alone (e.g., matching a specific component's natural width) before consolidating.
- **Verification:** Visually diff each of the 3 affected pages at widths spanning 780-1000px before/after, confirm no awkward reflow introduced.

### M7 — `.follow-row` has no narrow-viewport stacking, unlike the structurally identical `.notification-row` **[confirmed, unchanged]**
- **Severity:** Medium
- **User impact:** At 375px, avatar + username + Follow button are squeezed with no truncation handling on long usernames, while the near-identical Notifications row already correctly stacks under 600px.
- **Proposed fix:** Port `.notification-row`'s existing mobile stacking rule to `.follow-row`, adjusted for its specific children.
- **Files affected:** `css/pages/followlist/followlist.css` (or wherever `.follow-row` is currently defined), referencing `css/pages/notifications/notifications.css`'s existing pattern as the template.
- **Behavior change:** Yes, visible only below 600px width: the row switches from a squeezed single line to a stacked layout, matching Notifications' existing behavior.
- **Verification:** Load Followers/Following at 375px with a long username, confirm it now stacks/truncates gracefully instead of squeezing.

---

## 6. Consistency cleanup

### X1 — Dashboard build-card renderer: no output escaping, no lazy-loading **[confirmed, exact, this is the named "dashboard interpolation issue"]**
- **Severity:** High (Critical if `pages/dashboard.html` is ever relinked/reachable — see **D4**)
- **User impact:** `renderDashboard.js` is the one card renderer in the app that doesn't reuse the shared `BlueprintCard` component and defines no `escapeHtml`/`escapeAttribute` at all. `build.title` and `build.description` are interpolated directly into an `innerHTML` template, and `build.title` is interpolated unescaped into the `alt` attribute — a title containing `"` breaks out of the attribute; a title/description containing `<img onerror=...>` or `<script>` renders as live markup. Since this is the *account owner's own build data* on their *own* dashboard, the practical exploit path is narrow (self-XSS-shaped), but the pattern is a real, direct inconsistency against every other card renderer in the app, all of which escape correctly. Also missing `loading="lazy"`/`decoding="async"`, present on the equivalent `BlueprintCard`.
- **Proposed fix:** Add the standard `escapeHtml`/`escapeAttribute` calls around `build.title`/`build.description`/`build.slug` at the interpolation points (matching `BlueprintCard.js`'s existing correct pattern), and add `loading="lazy" decoding="async"` to the `<img>` tag. Given `pages/dashboard.html` is itself an orphaned duplicate of Workshop (**D4**), also flag for the phasing discussion whether it's cheaper to just delete this page/renderer entirely rather than patch it — see D4's proposed fix for the tradeoff.
- **Files affected:** `js/pages/dashboard/renderDashboard.js`.
- **Behavior change:** None visible for well-formed data (titles/descriptions without special characters render identically). Fixes a real bug for titles containing `< > " '` characters, which currently render broken/dangerous.
- **Verification:** Render a card with a title containing `<`, `"`, and `<script>` in a test build, confirm it now displays as literal text rather than executing/breaking the markup; confirm lazy-loading attribute is present.

### X2 — `featured.js` has the identical unescaped-`alt` bug as X1 **[new — a second instance of the same class of bug, in a file 8C's performance work touched for an unrelated reason]**
- **Severity:** High
- **User impact:** Same mechanism as X1: `showBuild()` interpolates `build.title` directly into an `<img alt="${build.title}">` template with no escaping defined anywhere in the file. This is the Featured Spotlight carousel on the homepage — higher-traffic than Dashboard.
- **Proposed fix:** Add the same `escapeHtml`/`escapeAttribute` helper call (or import the shared one if consolidated as part of D-cleanup) around `build.title` at the interpolation point.
- **Files affected:** `js/features/featured.js`.
- **Behavior change:** None visible for well-formed titles; fixes the same broken/unsafe-rendering bug as X1 for titles with special characters.
- **Verification:** Same as X1, applied to the Featured Spotlight carousel specifically.

### X3 — `escapeAttribute` has 3 duplicated, unequal-strength copies **[partially fixed since old audit, not fully]**
- **Severity:** Medium
- **User impact:** `js/pages/settings/app.js` still escapes only `&`/`"` (unchanged weak copy). `renderResourcesSection.js` and `renderGallerySection.js` were both improved at some point since the old audit to also escape `<` — but neither escapes `>` or `'`, unlike the full 5-character reference version in `BlueprintCard.js`. A narrow, but real, behavioral inconsistency in a security-relevant function depending on which file happens to render a given piece of user content.
- **Proposed fix:** Bring all 3 copies to parity with `BlueprintCard.js`'s full escaping (or, better, consolidate into one shared `js/utils/escapeHtml.js` export and have all current copies import it — the empty `js/utils/` stub files already earmarked for exactly this per the old audit; see **D-cleanup**).
- **Files affected:** `js/pages/settings/app.js`, `js/pages/editor/renderResourcesSection.js`, `js/pages/editor/renderGallerySection.js` (and the ~14 other files with duplicated-but-correct copies, if consolidating fully).
- **Behavior change:** None visible for normal content; fixes edge-case rendering for user content containing `>` or `'`.
- **Verification:** Unit-test (or manual test) each affected renderer with a string containing all 5 special characters, confirm consistent escaping across all of them.

### X4 — "Could not load…" error-message phrasing has 13+ distinct variants **[confirmed, cataloged]**
- **Severity:** Low-Medium
- **User impact:** No functional issue — every variant is clear and on-topic — but the app reads as stitched-together rather than designed by one voice when a user encounters failures across different features in the same session (e.g., "Try again." vs "Try refreshing the page." vs "try refreshing." with inconsistent capitalization/punctuation of "try").
- **Proposed fix:** Standardize on one phrasing template (e.g., `"Could not load {noun}. {action}."` with a single consistent action clause) and update the ~15 call sites to match. This is copy-only, zero logic change.
- **Files affected:** `js/utils/listState.js`, `js/core/notificationBell.js`, `js/pages/dashboard/loadDashboard.js`, `js/pages/workshop/loadWorkshop.js`, `js/pages/build/loadBuild.js`, `js/pages/build/renderComments.js`, `js/pages/followList/renderFollowList.js`, `js/pages/workshop/renderWorkshop.js`, `js/pages/notifications/renderNotifications.js`, `js/pages/editor/renderGallerySection.js`, `js/pages/home/renderActivityFeed.js`, `js/pages/editor/app.js`, `js/pages/edit-revision/app.js`, `js/pages/settings/app.js`, `js/pages/explore/app.js`, `js/pages/search/app.js`.
- **Behavior change:** None — string literals only.
- **Verification:** Grep for the old strings after the change to confirm none remain; spot-check 3-4 pages' error states visually.

### X5 — Only 4 of ~10 failure-prone features have a real Retry button; the rest say "try refreshing the page" **[new]**
- **Severity:** Medium
- **User impact:** `js/utils/listState.js`'s shared `renderErrorState()` with a working Retry button is only wired into Dashboard, Workshop, Settings, and Build's revision history. Comments, Follow lists, Notifications, Activity Feed, and Gallery all still hand-roll their own error markup with no retry affordance, asking the user to reload the entire page instead. This is a real capability split, not just a wording difference — X4's phrasing catalog is a symptom of this deeper inconsistency.
- **Proposed fix:** Adopt `listState.js`'s `renderErrorState()` (with each caller's own already-correct, narrowly-scoped retry callback — same pattern already established for the 4 current adopters) in the remaining 5-6 hand-rolled locations, replacing their bespoke error markup.
- **Files affected:** `js/pages/build/renderComments.js`, `js/pages/followList/renderFollowList.js`, `js/pages/notifications/renderNotifications.js`, `js/pages/home/renderActivityFeed.js`, `js/pages/editor/renderGallerySection.js`.
- **Behavior change:** Yes, meaningfully: these 5 features gain a working in-place Retry button where previously the only recovery was a full page reload. This is a genuine (small, additive) capability improvement, not just a visual change — flagging since the user's constraints say "preserve existing product behavior," and this technically adds a new interactive affordance rather than purely fixing a11y/polish. Recommend treating this as approved-by-default since it's copying an already-approved 8B pattern into more places, but calling it out explicitly rather than bundling it silently into "consistency cleanup."
- **Verification:** Simulate a load failure in each of the 5 features, confirm a Retry button now appears and correctly re-fetches only that feature's data (matching the 8B-established "retry only what failed" principle).

### X6 — Loading-state text inconsistency across list features **[confirmed, cataloged]**
- **Severity:** Low-Medium
- **User impact:** "Loading comments...", "Loading notifications...", generic "Loading...", "Loading gallery...", "Searching..." — cosmetic inconsistency only, same class of issue as X4.
- **Proposed fix:** Standardize on a `"Loading {noun}…"` template where a noun is available, matching X4's approach.
- **Files affected:** Same feature set as X4 (loading strings live alongside the error strings in most of these files).
- **Behavior change:** None — string literals only.
- **Verification:** Same as X4.

### X7 — Empty-state tone/markup has 2 real outliers plus one structurally different feature **[confirmed, cataloged]**
- **Severity:** Low-Medium
- **User impact:** `renderTimeline.js`'s "Start Your Project Log" and `renderWorkshop.js`'s first-run "Start your first project" are Title-Case-without-period against an otherwise consistent sentence-case-with-period convention across ~10 other empty states. Separately, `renderComments.js`'s empty state is a bare `<p>` rather than the shared `.empty-state` div/`<h3>` markup every other feature uses.
- **Proposed fix:** Align the 2 outlier strings' casing/punctuation; migrate Comments' empty state to the shared `.empty-state` markup pattern.
- **Files affected:** `js/pages/build/renderTimeline.js`, `js/pages/workshop/renderWorkshop.js`, `js/pages/build/renderComments.js`.
- **Behavior change:** Minor visual: Comments' empty state gets the same heading/body-text visual treatment as every other feature's empty state (currently just plain paragraph text) — a small, additive visual consistency fix, not a redesign (reusing an existing, already-approved pattern).
- **Verification:** Visually compare Comments' new empty state against Follow-list's/Notifications' existing ones, confirm consistent look; confirm the 2 renamed strings read naturally in context.

### X8 — `formatCategory` duplicated in 3 files; `featured.js`'s copy is missing 2 of 6 categories **[confirmed, one gap newly identified]**
- **Severity:** Medium
- **User impact:** `js/features/featured.js`'s local category-label map only handles `pc_build`/`setup`/`arduino`/`3d_printer`, falling through to the raw category string for anything else — confirmed missing **both** `homelab` and `robotics` (the old audit only caught the `homelab` gap). A build in either category shown in the Featured Spotlight carousel displays as a raw internal category slug instead of a formatted label.
- **Proposed fix:** Either add the 2 missing cases to `featured.js`'s local map (minimal fix) or implement the long-empty `js/utils/formatCategory.js` stub once and have all 3 duplicating files (`BlueprintCard.js`, `featured.js`, `renderBuild.js`) import it (root-cause fix, recommended, bundles naturally with **D-cleanup**'s empty-utils-file work).
- **Files affected:** `js/features/featured.js` (minimal fix) or `js/features/featured.js` + `js/components/BlueprintCard.js` + `js/pages/build/renderBuild.js` + new `js/utils/formatCategory.js` (root-cause fix).
- **Behavior change:** Fixes a real display bug (raw slug shown instead of formatted label) for `homelab`/`robotics` builds in the carousel; no change for the 4 already-handled categories.
- **Verification:** Feature a `homelab` and a `robotics` build in the carousel (or simulate via test data), confirm both now show correctly formatted labels.

### X9 — `formatStatus` duplicated in 3 files **[confirmed, unchanged]**
- **Severity:** Medium
- **User impact:** No confirmed behavioral drift found between the 3 copies (unlike `formatCategory`), so this is a pure maintenance-risk/consistency item, not a currently-visible bug.
- **Proposed fix:** Implement the empty `js/utils/formatStatus.js` stub once, migrate all 3 call sites to import it.
- **Files affected:** `js/pages/dashboard/renderDashboard.js`, `js/pages/build/continue.js`, `js/pages/build/renderBuild.js`, new `js/utils/formatStatus.js`.
- **Behavior change:** None if the 3 existing implementations are truly identical (verify during implementation before consolidating, in case one has a subtle intentional difference).
- **Verification:** Compare all 3 existing implementations line-by-line before consolidating; after consolidating, confirm status labels render identically to before on Dashboard, Continue, and the build page.

### X10 — `formatDate`'s month format differs between Comments (short) and Timeline (long) **[confirmed, current lines]**
- **Severity:** Medium
- **User impact:** A visible, real inconsistency: a comment's timestamp on a build page ("Jul 25, 2026") won't match that same build's revision-log timestamp ("July 25, 2026") in the adjacent Timeline section on the same page.
- **Proposed fix:** Pick one format (recommend `"short"`, since it's more common across the rest of the app's date displays — verify against Notifications/Activity-Feed/Follow-list's date formatting to confirm which is actually dominant before deciding) and align both.
- **Files affected:** `js/pages/build/renderComments.js`, `js/pages/build/renderTimeline.js`.
- **Behavior change:** Yes, minor and visible: one of the two date displays on the build page changes its month format to match the other.
- **Verification:** View a build with both comments and revision history, confirm both sections' dates now use the same month format.

### X11 — `build.html` skips from `<h1>` to `<h3>` before any `<h2>` **[confirmed, unchanged]**
- **Severity:** Medium
- **User impact:** Screen-reader users navigating by heading level (a common AT navigation technique) encounter a broken outline — the Creator sidebar's `<h3>` name heading appears before the first real `<h2>` section heading ("Blueprint Overview").
- **Proposed fix:** Change the Creator name heading from `<h3>` to `<h2>`, or restructure so it's not positioned ahead of the first true `<h2>` in document order (verify visual styling isn't tied to the specific heading level via CSS `h3` selectors — if so, adjust the CSS selector alongside the HTML change, not just the tag).
- **Files affected:** `pages/build/build.html`, possibly `css/pages/build/hero.css`/`build.css` if heading-level-specific styles exist for that element.
- **Behavior change:** None visible if the CSS selector is updated alongside the tag change; purely a semantic/structural fix.
- **Verification:** Inspect the heading outline (browser devtools accessibility panel or a heading-navigation screen-reader pass) before/after, confirm a clean h1→h2→h3 progression with no visual change.

### X12 — Footer links: full remediation detail (cross-referenced from **K2**) 
This finding's full write-up lives under **K2** in the Keyboard section, since the core defect is "not a real, operable link." Listed here only for completeness of the Consistency category's cross-reference, since it's also the direct cause of the legal pages having zero live references anywhere (**D2**).

---

## 7. Dead UI

### D1 — `pages/categories/*.html` (5 files) are completely empty **[confirmed, unchanged, refined: dynamically reachable, not statically linked]**
- **Severity:** Critical
- **User impact:** Every "Explore Technologies" tile on the live homepage (rendered by `TechnologyCard.js`, which builds `href="pages/categories/${category.slug}.html"` at runtime) links to a genuinely blank page — 0 bytes, not even a `<!DOCTYPE>`. This is the single most visible dead-UI item in the app: a real, prominent, always-present homepage element leads nowhere.
- **Proposed fix:** Per the explicit "no new features" constraint, building real curated category-browse pages is out of scope for 8D (as the original audit already noted, deferring full category content to a separate content/product task). The additive, non-feature fix: give each of the 5 pages a minimal real shell — reuse the existing page chrome (navbar/footer) plus a short "Browse builds in {category}" message that links to Explore pre-filtered to that category (Explore already supports category filtering, so this is wiring, not new functionality) rather than a fully custom landing page.
- **Files affected:** `pages/categories/3d-printing.html`, `arduino.html`, `desk-setups.html`, `pc-builds.html`, `robotics.html` (all 5, same minimal template).
- **Behavior change:** Yes — these links currently 404-equivalent (blank page); after the fix they resolve to a real, minimal page. This is a bugfix (dead link → working link), consistent with "no new features" since it reuses Explore's existing filter capability rather than building new browse UI.
- **Verification:** Click each homepage category tile, confirm it now lands on a real page with working chrome and a working link into filtered Explore results.

### D2 — `pages/legal/*.html` (4 files) are completely empty and now fully unlinked **[confirmed, unchanged, worse than originally described]**
- **Severity:** Critical
- **User impact:** Same empty-file status as D1, but with zero live references anywhere in the current app (the footer's "Privacy"/"Terms" text isn't even a link — see K2/X12) — so unlike D1, this isn't yet user-visible as a broken click, only reachable by guessing/bookmarking a URL. Still critical for real launch readiness (privacy policy / terms of service pages are commonly a legal requirement, not just a UX nicety).
- **Proposed fix:** Same minimal-shell approach as D1 — real page chrome plus actual (even if brief, placeholder-but-real) policy text — paired with fixing K2 so the footer actually links to them. Content authorship itself (legal copy) is explicitly a content/product/legal task, not an engineering one; the architectural fix here is making the pages exist and be linked, not writing the legal text.
- **Files affected:** `pages/legal/affiliate-disclosure.html`, `community-guidelines.html`, `privacy.html`, `terms.html`, plus `js/core/layout.js` (footer links, shared with K2).
- **Behavior change:** Yes — footer links become real and lead somewhere real instead of nowhere.
- **Verification:** Click each footer legal link, confirm it now leads to a real page with correct chrome; flag to the user that the actual legal copy still needs non-engineering sign-off before a real launch.

### D3 — `continue.html`/`continue.js` orphaned but still directly reachable **[confirmed, unchanged]**
- **Severity:** Medium
- **User impact:** No in-app link reaches it (multiple in-code comments confirm the flow is deliberately retired in favor of the real editor), but it's still directly URL-accessible and fully executes if hit.
- **Proposed fix:** Delete the page and its JS/CSS, since the retirement is already confirmed intentional and documented in-code — this isn't a "maybe still needed" case.
- **Files affected:** `pages/build/continue.html`, `js/pages/build/continue.js`, `css/pages/build/continue.css` (if not shared with other pages — verify before deleting).
- **Behavior change:** The URL stops working entirely (currently: works but shouldn't be used; after: 404). Acceptable given zero in-app references and explicit in-code retirement comments.
- **Verification:** Grep for any reference to `continue.html`/`continue.js`/`continue.css` across the repo before deleting, confirm zero hits remain besides the files themselves; confirm no other page's CSS imports `continue.css` if it's deleted.

### D4 — `pages/dashboard.html` is an orphaned, actively-maintained duplicate of Workshop **[confirmed, unchanged]**
- **Severity:** Medium
- **User impact:** Zero in-app links reach it (confirmed via `docs/CHANGELOG.md`'s own note), yet its backing JS was still touched by 8B's reliability work (`listState.js` adoption) — meaning effort is being spent maintaining a page nobody can reach.
- **Proposed fix:** Product decision needed, not a pure engineering call: either (a) delete it entirely since Workshop supersedes it, or (b) if there's a reason it's being kept "just in case," at minimum stop it from silently accumulating maintenance debt by noting its orphan status prominently (e.g., a code comment) so future milestones don't keep touching it by accident. Recommend (a) given Workshop is the actively-used, actively-linked equivalent — but this is the one dead-UI item worth explicitly confirming with the user rather than assuming, since deleting a whole page+its dedicated renderer is a slightly bigger action than deleting truly-dead stub files.
- **Files affected:** `pages/dashboard.html`, `js/pages/dashboard/{app,loadDashboard,renderDashboard}.js` (and its CSS), if deleted. Note: deleting this page also resolves **X1** (the dashboard interpolation bug) by removing the buggy file entirely, rather than patching it — worth deciding these two together.
- **Behavior change:** URL stops working (currently: works but unreachable in-app). Acceptable if deletion is approved, same reasoning as D3.
- **Verification:** Confirm zero in-app links before deleting (already established); grep for any remaining references after deletion.

### D5 — 22 empty (0-byte) `.js` files with zero importers **[confirmed, unchanged]**
- **Severity:** Medium (aggregate)
- **User impact:** None directly (they're never loaded), but they create false signals — a future contributor might assume `js/utils/formatDate.js` etc. already has an implementation to import, or that `js/components/Modal.js` is a ready-to-use component (see K3).
- **Proposed fix:** For the 4 `js/utils/` format-helper stubs (`formatCategory.js`, `formatDate.js`, `formatStatus.js`, `slugify.js`): implement them for real as part of the X8/X9/X10 consolidation work, rather than deleting (they're the intended eventual home for that logic). For the remaining 18 (component stubs, config stubs, service stubs, home-section stubs): delete outright, since nothing in this audit found a near-term plan to use them.
- **Files affected:** Delete: `js/components/{avatar,exploreCard,Modal,profileBuildCard,revisionCard}.js`, `js/config/permissions.js`, `js/features/importer.js`, `js/repositories/searchRepository.js`, `js/services/{affiliateService,importService,moderationService,uploadService}.js`, `js/pages/home/sections/*.js` (7 files). Implement-in-place: `js/utils/{formatCategory,formatDate,formatStatus,slugify}.js`.
- **Behavior change:** None — confirmed zero importers for every deletion target.
- **Verification:** Grep for each filename (both as an import path and as a bare mention) across the entire repo immediately before deleting; confirm zero hits outside the file itself.

### D6 — 18 empty component-scaffold directories **[confirmed, unchanged]**
- **Severity:** Low
- **User impact:** None — pure repo-tidiness.
- **Proposed fix:** Delete all 18.
- **Files affected:** `js/components/{Avatar,Badge,button,Card,Dropdown,EmptyState,Form,Input,Modal,Navbar,Pagination,SearchBar,Skeleton,SpotlightSlide.js,Tabs,Tag,Toast,Tooltip,UploadZone}/`.
- **Behavior change:** None.
- **Verification:** Confirm each directory is genuinely empty (no hidden/nested files) before deleting.

### D7 — 4 empty, unimported CSS files **[confirmed, unchanged]**
- **Severity:** Low
- **User impact:** None.
- **Proposed fix:** Delete, unless kept intentionally per **C5**'s light/dark-theme documentation note (`dark.css` overlaps with that decision — resolve together).
- **Files affected:** `css/components/input.css`, `navbar.css`, `tab.css`, `css/themes/dark.css`.
- **Behavior change:** None.
- **Verification:** Confirm `styles.css` has no import for any of the 4 before deleting.

### D8 — `css/components/pagination.css` is imported but has zero real usage **[new]**
- **Severity:** Low-Medium
- **User impact:** None functionally — but it's dead weight, and its existence could mislead someone into thinking a numbered-pager pattern is the app's convention when every list actually uses "Load More" instead.
- **Proposed fix:** Delete the file and its import.
- **Files affected:** `css/components/pagination.css`, `css/styles.css` (import line).
- **Behavior change:** None (confirmed zero class-name usage anywhere in `.html`/`.js`).
- **Verification:** Grep for `pagination-button`/`pagination`-related class names across all `.html`/`.js` before deleting, confirm zero real (non-comment) hits.

### D9 — `css/components/tooltip.css` is imported but has zero real usage **[new]**
- **Severity:** Low
- **User impact:** None — no element anywhere sets a `data-tooltip` attribute.
- **Proposed fix:** Delete the file and its import.
- **Files affected:** `css/components/tooltip.css`, `css/styles.css` (import line).
- **Behavior change:** None.
- **Verification:** Grep for `data-tooltip` across all `.html`/`.js` before deleting, confirm zero hits.

### D10 — 5 unreferenced brand/placeholder assets; no favicon wired anywhere **[new]**
- **Severity:** Low (favicon: Low-Medium, since it's the one genuinely user-visible item in this group — every browser tab currently shows a generic icon)
- **User impact:** `default-avatar.svg`/`default-build.svg` (superseded by the text-initial avatar fallback and never wired up), `specbound-logo.svg`/`specbound-mark.svg` (navbar brand is rendered as styled text, not these files), and `favicon.svg` (no `<link rel="icon">` exists on any page) are all unreferenced.
- **Proposed fix:** Delete the 4 truly-unused placeholders/logos (`default-avatar.svg`, `default-build.svg`, `specbound-logo.svg`, `specbound-mark.svg`) since nothing currently plans to use them. Wire up the favicon — this is the one genuinely additive, user-visible fix in the Dead UI category: add `<link rel="icon" href="assets/brand/logo/favicon.svg">` to each page's `<head>` (or centralize via a shared head-partial if one exists).
- **Files affected:** Delete: `assets/placeholders/{default-avatar,default-build}.svg`, `assets/brand/logo/{specbound-logo,specbound-mark}.svg`. Add favicon link: every `pages/*.html` + `index.html` (or wherever `<head>` is shared/templated).
- **Behavior change:** Favicon: yes, visibly — every browser tab gets a real icon instead of a generic one (additive, not a redesign — using an asset that already exists in the repo). Deletions: none.
- **Verification:** Grep for each asset filename across the repo before deleting the 4 unused ones; load any page and confirm a real favicon now appears in the browser tab.

### D11 — `js/features/upload.js` (373 lines) is dead **[confirmed, unchanged]**
- **Severity:** Medium
- **User impact:** None directly — explicitly documented as dead in `docs/CHANGELOG.md`, zero importers.
- **Proposed fix:** Delete.
- **Files affected:** `js/features/upload.js`.
- **Behavior change:** None.
- **Verification:** Confirm zero importers via grep before deleting.

### D12 — `js/pages/edit-build/app.js` is dead and internally broken **[confirmed, unchanged — a landmine]**
- **Severity:** Medium
- **User impact:** None currently (never loaded by any page), but if ever accidentally relinked it would throw immediately — it imports `js/services/index.js` and `js/templates/pcBuild.js`, neither of which exist.
- **Proposed fix:** Delete outright rather than fix — the in-code comment confirms this flow is retired and superseded by the real editor, so there's no reason to repair its broken imports.
- **Files affected:** `js/pages/edit-build/app.js` (and its directory, if nothing else lives there).
- **Behavior change:** None.
- **Verification:** Confirm zero importers/HTML references via grep before deleting.

### D13 — `js/config/index.js` (broken self-import) and `routes.js`/`statuses.js`/`filters.js`/`socials.js` (unimported) **[confirmed, index.js changed-but-still-broken; others unchanged]**
- **Severity:** Low
- **User impact:** None — none of the 5 are imported anywhere. `index.js` grew some content since the old audit but still contains a broken self-referential import that would throw if ever actually imported.
- **Proposed fix:** Delete all 5, unless the team has a near-term plan to route pages through `routes.js` (the old audit noted every page currently hardcodes its own relative paths instead — a real but separate refactor, out of scope for 8D's "no broad refactoring" constraint).
- **Files affected:** `js/config/index.js`, `routes.js`, `statuses.js`, `filters.js`, `socials.js`.
- **Behavior change:** None.
- **Verification:** Confirm zero importers via grep before deleting each.

### D14 — `hero.css` self-import plus duplicate imports of already-imported files **[confirmed, unchanged]**
- **Severity:** Low-Medium
- **User impact:** None functionally (browsers break the self-import cycle safely, and re-importing an already-loaded stylesheet is idempotent), but confusing/misleading for anyone reading the file.
- **Proposed fix:** Remove the self-import and the 3 duplicate imports (`specifications.css`/`timeline.css`/`gallery.css`, already correctly imported one level up by `build.css`).
- **Files affected:** `css/pages/build/hero.css` (top of file).
- **Behavior change:** None (purely removing redundant, already-inert import statements).
- **Verification:** Visually diff the build page before/after to confirm zero style changes (expected, since the removed imports were fully redundant).

### D15 — Duplicate, conflicting `.creator-card`/`.creator-label` definitions **[confirmed, unchanged]**
- **Severity:** Medium
- **User impact:** None currently visible (the `build.css` versions win and are what actually renders), but it's a real maintenance hazard — editing the "wrong" (silently dead) copy in `hero.css` would appear to do nothing.
- **Proposed fix:** Delete the dead `hero.css` copy, keeping only `build.css`'s (the one that actually applies).
- **Files affected:** `css/pages/build/hero.css` (removing `.creator-card`/`.creator-avatar`/`.creator-label` rules), leaving `css/pages/build/build.css`'s copies untouched.
- **Behavior change:** None (the `hero.css` copies are confirmed currently inert — deleting inert rules can't change rendered output).
- **Verification:** Visually diff the build page's Creator sidebar before/after, confirm zero change.

---

## Proposed phasing

Given the volume (62 findings) and this project's established one-milestone-at-a-time workflow, recommend splitting 8D into sub-phases rather than one giant change, each independently shippable/reviewable:

**8D-1 — Screen reader & keyboard blockers (High/Critical, no visual changes).** K1, K2, K4, K5, S1–S9. All additive ARIA/label/link-type fixes with zero visual diff except K2 (footer links become clickable, same visual style).

**8D-2 — Focus management (High, one small shared-behavior change).** F1, F2, F3/M3. Requires the most design judgment (where should focus land?) — recommend reviewing the proposed focus-target choices before implementing.

**8D-3 — Mobile polish (Medium-High, small visual changes at mobile widths only).** M1, M2, M3 (shared with F3), M6, M7. M2 is a pure bugfix (restores already-written-but-shadowed intent); M1/M6/M7 have minor visible sizing/layout effects at mobile breakpoints only.

**8D-4 — Color/contrast token adjustments (needs explicit sign-off — touches visual appearance app-wide).** C1, C2, C3, C4. Recommend a single combined decision: approve all 4 as "necessary accessibility token nudges," defer C1 specifically to the eventual redesign, or some split — this is the one phase that isn't purely mechanical.

**8D-5 — Consistency cleanup (Low-Medium, mostly copy/logic-dedup, zero-to-minor visual change).** X1, X2 (both High — recommend pulling these two into 8D-1 given their severity, despite being categorized under Consistency), X3, X4, X5 (note: X5 adds a small new capability, flagged), X6, X7, X8, X9, X10, X11.

**8D-6 — Dead code removal (Low risk, mechanical, verify-then-delete each item).** D1, D2 (need product/content sign-off on the minimal-shell approach and legal copy), D3 through D15.

Recommend running **8D-1 and the X1/X2 escaping fixes first** (highest severity, zero design risk), then letting the user decide sequencing for the remaining phases based on appetite for the two phases that touch visual appearance (8D-3, 8D-4) versus the two that are purely mechanical (8D-2, 8D-6).

---

## Constraint compliance check

- **No redesign:** All fixes are additive (new attributes/files/deletions) except C1/C2/C3 (token value nudges, flagged for explicit sign-off) and M1 (minor padding increases on undersized touch targets, inherent to fixing the underlying issue).
- **No new features:** X5 (extending the existing Retry pattern to more features) and D1/D2 (giving empty pages minimal real content) are the two items that add capability beyond pure bugfixing — both flagged explicitly above rather than silently bundled in.
- **No broad refactoring:** D13's `routes.js` consolidation opportunity was explicitly identified and explicitly deferred as out-of-scope, consistent with this constraint.
- **Preserve existing product behavior:** Confirmed for every finding except the ones explicitly called out as behavior-changing above (all bugfixes restoring clearly-intended-but-broken behavior, or additive AT-only changes invisible to sighted/mouse users).

Stopping here for review, per the milestone workflow. Awaiting direction on phasing/sequencing and the sign-off items (C1–C3, X5, D1/D2/D4) before any implementation begins.
