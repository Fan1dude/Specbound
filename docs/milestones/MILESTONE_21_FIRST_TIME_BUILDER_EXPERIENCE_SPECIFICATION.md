# Milestone 21: First-Time Builder Experience — Specification

Status: **Decisions locked 2026-08-01.** §12 records the seven decisions that closed the previous draft's open-decision list, including the exact global trigger point, schema, copy, localStorage key scheme, technology-picker accessibility contract, and first-publish detection flow. Nothing in this document has been implemented. The proposed migration (§4) has not been applied to any database. **Specification only — do not implement yet**, per the original request.

Objective: *"A new builder should feel confident enough to publish their first project."*

---

## 1. Scope

Six onboarding phases, all for a brand-new builder between account creation and their first published project:

1. Welcome screen after first verified sign-in.
2. Profile completion checklist (username, display name, avatar, headline, bio).
3. Project type chooser.
4. Contextual editor hints (no long tutorial).
5. First publish celebration.
6. Improved empty states across relevant pages.

Standing constraints:

- Reuse existing shared components and design tokens wherever possible.
- Additive and backward-compatible — no behavior change for existing users beyond the one-time migration backfill (§4).
- No Discord, achievements, reputation, moderation, analytics, or schema changes unrelated to "show once" onboarding state.
- Data model changes only where essential to "show once" behavior.
- Specification only. No code in this pass.

---

## 2. Current-State Findings

Facts this spec is built on, confirmed by reading the actual code:

- **Signup requires email confirmation.** [signup/app.js](js/pages/signup/app.js) calls `supabase.auth.signUp()`; if `data.session` is absent (the normal case), no profile row is created client-side yet and the user is sent to `login.html`. The `profiles` row is actually created by the `handle_new_user()` trigger ([0000_baseline_pre_tracked_tables.sql:176](supabase/migrations/0000_baseline_pre_tracked_tables.sql:176)), which fires on `auth.users` insert regardless of confirmation state — the row exists before the first login, but the first *session* doesn't exist until the confirmation link is clicked and [login.html](pages/login.html)'s form is submitted successfully. **"First verified sign-in" = the first time `supabase.auth.signInWithPassword()` succeeds for this account.** Email+password is the only auth method in this codebase — no OAuth/magic-link path to also account for.
- **`loadNavbar()` runs on every single page, always, immediately.** [layout.js](js/core/layout.js) is called as `loadNavbar(pathPrefix)` at the top of literally every page's own `app.js` (signup, login, settings, editor, workshop, profile, legal pages, build pages — confirmed by grep across the whole `js/pages/` tree). It already does `const user = await getCurrentUser()` and, when signed in, already fetches the profile row (`select("username")`) to render the builder menu. **This is the one true global, post-session-resolution hook point** — see §6.1.
- **Login redirects to Home** ([login/app.js:43](js/pages/login/app.js:43)) after calling `ensureProfile()`, but this is no longer the relevant hook — §6.1 uses `loadNavbar()` instead, which fires regardless of which page the session lands on first.
- **Settings already has every profile-checklist field.** [settings/app.js](js/pages/settings/app.js) already reads/writes `display_name`, `username`, `headline`, `bio`, plus avatar upload. Nothing new needs to be built to *complete* a profile — only to surface completeness.
- **`project_drafts.title` is `not null default ''`** ([0001_project_drafts_and_media.sql:26](supabase/migrations/0001_project_drafts_and_media.sql:26)), and [upload/app.js](js/pages/upload/app.js) never validates title non-empty (only category) — an empty-title draft is already a supported state today.
- **`upload.html`'s current technology control** ([pages/upload.html:62-70](pages/upload.html:62)) is a plain `<select id="category" required>` with 6 hardcoded `<option>` values (`pc_build`, `setup`, `arduino`, `robotics`, `3d_printer`, `homelab`) that duplicate, rather than read from, `js/config/technologies/index.js`'s `TECHNOLOGIES` array. [upload/app.js](js/pages/upload/app.js) reads `document.getElementById("category").value` and separately re-checks it's non-empty before submit (native `required` already blocks empty submission; the JS check is defense-in-depth, not the primary guard). §7.1 replaces the control, not the validation model.
- **`TechnologyCard.js` renders an `<a>`** that navigates to a category browse page — right visual language (technology-card.css, per-category accent/icon hydration via `hydrateTechnologyCards()`), wrong interaction model for "pick one to act on." §7.1 defines two new sibling components instead of repurposing this one.
- **The editor readiness checklist ([draftValidation.js](js/services/draftValidation.js) → `getReadinessChecks()`) is a pure, no-I/O, re-run-on-every-render pattern** — the direct model for §5's profile checklist.
- **`draftRecoveryBanner.js`** shows/hides from a *computed* condition, not a persisted DB flag — the interaction model reused for §7.3's hints.
- **`localStorage` is already used for exactly this class of low-stakes, device-local state**: [anonViewerId.js](js/core/anonViewerId.js), [draftRecovery.js](js/services/draftRecovery.js). Neither is wrapped in try/catch today — §10 introduces the first such wrapper in this codebase, since onboarding dismissal state must not throw in private-browsing/storage-disabled contexts.
- **`confirmDialog()` ([modal.js](js/utils/modal.js)) is the accepted `<dialog>` construction pattern** — native `<dialog>`, focus handling and Esc/backdrop dismissal come from the browser, `.modal`/`.modal-body` CSS, `requestAnimationFrame`-deferred open transition. Native `showModal()`/`close()` also handles returning focus to the previously-focused element automatically — relied on directly in §11, not reimplemented.
- **`.empty-state`/`emptystate.css` is already the sitewide empty-state component**, used in 13+ files already. Home's Following-feed empty state ([renderActivityFeed.js:168-176](js/pages/home/renderActivityFeed.js:168)) — *"Your Following feed is empty."* / *"Follow some builders to see their latest projects and updates here."* / **Explore Projects** button — is the concrete "new-user Home state" referenced in §9; a brand-new account's Following feed is unconditionally empty on first visit.
- **`builds` rows are only ever created by `publish_draft()`, and unpublishing never deletes the row** — `setBuildVisibility(id, "private")` (used by the editor's Unpublish action) only flips `visibility`, confirmed by reading [editor/app.js](js/pages/editor/app.js)'s unpublish handler. This is why §8's first-publish check counts *all* of a user's `builds` rows regardless of current `visibility`, not just currently-public ones — grounding for §8.1.

---

## 3. Design Position

Matches the brand principle already established in Milestone 20 ("calm enough for long work sessions," no engagement-chrome theatrics): onboarding here removes friction, it doesn't add gamified flourish. No confetti library, no XP/progress-ring framing. The Welcome screen is two short lines and one button. The profile checklist is the same quiet, text-first pattern as the editor readiness checklist. The publish celebration is one on-brand dialog with a link to the live project, not a full-screen animation.

---

## 4. Data Model — Schema (final)

### 4.1 What persists, and why

Of the six phases, only **Phase 1 (Welcome)** needs durable, cross-device, cross-session state — it must show exactly once per account, ever, on whichever device/browser the account is first used from after this ships. Everything else is either computed live from data that already exists (§5, §7.3's "has this user ever published" gate, §8's first-publish check) or kept in versioned, namespaced `localStorage` (§10) — deliberately low-stakes, device-local, and never authoritative for anything that must be correct across devices.

One new nullable column. No new tables, no JSON blob of onboarding flags, no event log.

### 4.2 Migration — `0025_profile_onboarding_welcomed.sql`

Next available number is `0025` (last tracked is `0024`, Milestone 20).

```sql
-- Migration: 0025_profile_onboarding_welcomed
-- Milestone: 21 (First-Time Builder Experience)
-- Status: PROPOSED — not yet applied. Depends on 0000-0024 being applied
-- first.
--
-- Purpose: one nullable timestamp recording when a profile was shown (or
-- exited) the first-sign-in Welcome screen. The only Milestone 21 state
-- that must be durable and cross-device — see
-- docs/milestones/MILESTONE_21_FIRST_TIME_BUILDER_EXPERIENCE_SPECIFICATION.md
-- §4, §6.
--
-- Touches: public.profiles (1 new nullable column). No RLS change: the
-- existing "Users can update their own profile" policy (0000) already
-- covers writes to this column — same reasoning as 0024's headline/
-- featured_build_id addition.
--
-- Backfill — decided: every existing row is set to its own created_at,
-- not left null. Left null, every pre-existing user would see the Welcome
-- screen once after this ships, misrepresenting it to established
-- builders as if they were new. created_at is the truthful "this account
-- predates onboarding" signal and needs no invented "now" timestamp for
-- rows this migration didn't create.
--
-- Rollback: see 0025_profile_onboarding_welcomed_rollback.sql in
-- supabase/rollbacks/. Drops the column; backfilled values are not
-- recoverable after rollback — a re-applied migration re-backfills from
-- created_at again, which is fine, since created_at itself is untouched.

begin;

alter table public.profiles
    add column onboarding_welcomed_at timestamptz;

update public.profiles
    set onboarding_welcomed_at = created_at
    where onboarding_welcomed_at is null;

commit;
```

```sql
-- Rollback for 0025_profile_onboarding_welcomed.

begin;

alter table public.profiles
    drop column if exists onboarding_welcomed_at;

commit;
```

Semantics: `null` = never shown, eligible to show on next authenticated page load anywhere. Any non-null value (backfilled `created_at`, or a real sign-in timestamp going forward) = never show again.

### 4.3 What is deliberately *not* added

- No `profile_completed_at` — §5's checklist is fully derivable from existing columns on every render.
- No `first_publish_celebrated_at` — §8's "was this the user's first publish" is a point-in-time check; the precondition (`published build count was 0`) can never be true again for that account once it's been published once, so the DB naturally makes this idempotent with no flag.
- No `hints_dismissed`/`checklist_dismissed` column — kept in `localStorage` (§10), matching the existing `draftRecovery.js` pattern. Device-local re-appearance is an acceptable, low-stakes outcome, unlike the Welcome screen.
- No onboarding "step"/"progress" table — nothing here requires resuming a multi-step wizard across sessions.

---

## 5. Phase 2: Profile Completion Checklist

Unchanged from the prior draft — no decision affected this phase.

### 5.1 Rule set

New file `js/services/profileCompletion.js`, mirroring [draftValidation.js](js/services/draftValidation.js)'s `getReadinessChecks()` contract exactly:

```js
export function getProfileCompletionChecks(profile) {
    return [
        { key: "username", label: "Username", passed: Boolean(profile.username) },
        { key: "display_name", label: "Display name", passed: Boolean((profile.display_name || "").trim()) },
        { key: "avatar", label: "Avatar", passed: Boolean(profile.avatar_path || profile.avatar_url) },
        { key: "headline", label: "Headline", passed: Boolean((profile.headline || "").trim()) },
        { key: "bio", label: "Bio", passed: Boolean((profile.bio || "").trim()) }
    ];
}

export function isProfileComplete(checks) {
    return checks.every(check => check.passed);
}
```

Per decision §12.6, this function takes only `profile` and does no storage lookups of any kind — it must produce a correct result identically whether or not `localStorage` exists, is disabled, or is full. The *dismiss* affordance on the card wrapping it (§5.2) is the only part of this feature that touches `localStorage`, and its unavailability only affects whether the card can be hidden early — never whether the checklist itself is correct.

### 5.2 Where it renders

A new dismissible card on [workshop.html](pages/workshop.html), above the existing stats/drafts sections, owner-view only. Visual pattern: same list-with-checkmarks treatment as `.editor-readiness`.

- Auto-hides once `isProfileComplete()` is true.
- Manually dismissible while incomplete, via the namespaced `localStorage` key defined in §10 — falls back to "always shown" if storage is unavailable (fail open: a checklist that can't remember being dismissed is a minor annoyance, not a correctness bug, so it defaults to visible rather than defaulting to permanently hidden).
- Each incomplete item links to the relevant Settings field.

### 5.3 New component

`js/pages/workshop/renderProfileChecklist.js` — reads `profile` (already fetched by `loadWorkshop.js`), calls `getProfileCompletionChecks`, renders the list + dismiss control. No new repository query.

---

## 6. Phase 1: Welcome Screen

### 6.1 Global trigger location — exact

**Hook point: [`js/core/layout.js`](js/core/layout.js)'s `loadNavbar()`, inside its existing `if (user) { ... }` branch**, immediately after the existing profile fetch. This is the one place in the codebase that already runs on every authenticated page load, already resolves the session, and already fetches the profile row — satisfying decision §12.1 ("first authenticated page load anywhere in the application") without adding a new check to every page individually.

`loadNavbar()`'s existing query is extended from `select("username")` to `select("username, onboarding_welcomed_at")`. `layout.js` itself stays thin — it delegates to a new dedicated module rather than growing dialog logic inline:

```js
// inside loadNavbar(), within the existing `if (user) { ... }` branch,
// right after the existing profile fetch:
const { data: profile } = await supabase
    .from("profiles")
    .select("username, onboarding_welcomed_at")
    .eq("id", user.id)
    .single();

// ...existing username/authLinks logic, unchanged...

if (profile && !profile.onboarding_welcomed_at) {
    maybeShowWelcome(user, profile, pathPrefix);
}
```

New file `js/core/onboarding.js` owns `maybeShowWelcome()` and the dialog wiring — kept out of `layout.js` itself so `layout.js` stays focused on chrome, not onboarding logic.

**Consequence of "anywhere in the application," made explicit**: this fires on every page type — legal pages, build detail pages, the editor, Explore, search results — not just Home/Workshop. This is the intended behavior per decision §12.1, not an edge case to special-case away. `login.html`/`signup.html` are naturally excluded without any extra logic, since `getCurrentUser()` resolves to no user there.

**Ordering note**: pages that also call `requireAuth()` (Settings, Workshop, the editor) call it *after* `loadNavbar()` in their existing bootstrap order (confirmed across every `app.js` read this session) — so the Welcome check and any subsequent auth-redirect never race; by the time `requireAuth()` could redirect an unauthenticated visitor away, `loadNavbar()`'s own independent `getCurrentUser()` call has already determined there's no user, and `maybeShowWelcome` never fires for that case anyway.

### 6.2 Content — final copy

Single-screen-then-chooser, exactly two labeled actions total across the whole flow (no secondary "skip to Settings" button — profile completion is handled separately and continuously by §5's Workshop checklist, not as a competing CTA here):

**Welcome step:**
- Title: **"Welcome to Specbound"**
- Body: **"Document each stage of what you build—from the first idea to the finished project."**
- Primary action: **"Continue"**
- Implicit dismiss: ×, Esc, backdrop click (same affordances as `confirmDialog()`, unlabeled, standard dialog convention).

**Chooser step** (replaces the Welcome step's content in the same dialog element on Continue):
- Title: **"What are you documenting?"**
- Grid of technology cards (§7.1's button variant) — selecting one creates a draft and navigates to the editor (§6.4).
- Same dismiss affordances as the Welcome step.

### 6.3 Component

New `js/components/WelcomeDialog.js`, built on the same native-`<dialog>` construction as `confirmDialog()` — focus handling, Esc, backdrop-click, `requestAnimationFrame`-deferred open transition, `--duration-fast` close, `prefers-reduced-motion` respected — but its own content shape (two internal steps, no yes/no confirmation), so it's a sibling component, not a `confirmDialog()` variant. The two steps swap `.modal-body` innerHTML within one dialog element, so focus-trap/backdrop wiring is written once, not duplicated per step.

**Exact write timing for `onboarding_welcomed_at`** (resolves the ambiguity in the previous draft): marked exactly once, on the **first exit from the Welcome step**, by whichever path happens first:
- Clicking **Continue** (transitions to the chooser step) — marks immediately at that click, *not* deferred until the chooser step itself is exited. Having continued past the Welcome step already constitutes "shown," regardless of whether the user goes on to pick a technology or closes the chooser without choosing.
- Closing the Welcome step directly via ×/Esc/backdrop, without clicking Continue — marks immediately at that close.

This means the chooser step's own dismissal (×/Esc/backdrop, or selecting a card) never triggers a second write — the flag is already set by the time the chooser step is reachable at all.

```js
export async function markOnboardingWelcomed(id) {
    const { error } = await supabase
        .from("profiles")
        .update({ onboarding_welcomed_at: new Date().toISOString() })
        .eq("id", id);

    if (error) throw error;
}
```

**Known accepted edge case**: if the write itself fails (network error) or the tab is closed before the click handler's `await` resolves, the flag stays null and the Welcome screen shows again on the next authenticated page load. This is treated as correct degraded behavior (they didn't durably finish exiting it), not a bug requiring retry logic.

### 6.4 Chooser → draft creation

Selecting a technology card in the chooser step calls the same `createDraft({ userId, title: "", category })` already used by [upload/app.js](js/pages/upload/app.js) (§2 confirms an empty title is already valid) and navigates to `pages/build/edit.html?draft={id}` — skipping the title-entry step for this specific entry point only. `upload.html` itself is unchanged in *behavior*, only in its technology control's markup (§7.1) — it remains the standalone "start a project" entry point for every subsequent project.

---

## 7. Phase 3 & 4: Project Type Chooser + Contextual Editor Hints

### 7.1 Technology picker — two sibling components, one shared source of truth

Two different interaction models require two different components, sharing the same visual styling and the same config source — not one component reused two incompatible ways:

**(a) `js/components/TechnologyRadioCard.js` — for `upload.html`'s form.**
Renders a real `<input type="radio" name="category" required>` visually hidden (clipped, not `display:none` — clipping keeps it in the accessibility tree, keyboard-focusable, and subject to native constraint validation; `display:none` would remove it from all three), paired with a `<label>` wrapping the full visual card:

```js
export function TechnologyRadioCard(technology, { checked = false } = {}) {
    return `
        <label class="technology-picker-card" data-category-accent="${technology.accent}">
            <input
                type="radio"
                name="category"
                value="${technology.id}"
                class="sr-only-input"
                required
                ${checked ? "checked" : ""}
            >
            <div class="technology-picker-icon" aria-hidden="true">
                <span class="technology-picker-symbol"></span>
            </div>
            <div class="technology-picker-body">
                <h3>${technology.title}</h3>
                <p>${technology.subtitle}</p>
            </div>
        </label>
    `;
}
```

This preserves the **exact current validation contract**: a native `required` radio group blocks form submission and focuses the group on invalid submit, exactly as `<select required>` does today — no new JS validation logic needed, `upload/app.js`'s existing defensive `if (!category)` check stays as-is. It preserves the **exact current stored-value contract**: `value="${technology.id}"` is sourced directly from `TECHNOLOGIES[].id` in `js/config/technologies/index.js` (§2's single source of truth, replacing the hardcoded `<option>` list), so `createDraft()`'s `category` argument is byte-identical to what it receives today. The one adaptation required in `upload/app.js`: reading the value changes from `document.getElementById("category").value` to `document.querySelector('input[name="category"]:checked')?.value || ""` — a mechanical read-path change, not a behavior change.

**Accessibility**: native `<input type="radio">` + shared `name` gives a real radiogroup for free — screen readers announce "N of 6," arrow keys move selection within the group, Tab enters/exits the group once, Space/click selects. The `<label>` wraps the entire visual card, so the whole card (not just a small native radio dot) is the tap/click target — satisfies mobile accessibility without custom touch-target CSS. No custom ARIA is needed anywhere in this component; the semantics come entirely from native HTML.

**(b) `js/components/TechnologyChooserButton.js` — for the Welcome dialog's chooser step (§6.4).**
A `<button>` per card, not a radio — selection here is an immediate one-click action (create-and-navigate), not a value held until a separate form submit, so button semantics are the correct native fit, not radio semantics:

```js
export function TechnologyChooserButton(technology) {
    return `
        <button type="button" class="technology-picker-card" data-category-accent="${technology.accent}" data-category-id="${technology.id}">
            <div class="technology-picker-icon" aria-hidden="true">
                <span class="technology-picker-symbol"></span>
            </div>
            <div class="technology-picker-body">
                <h3>${technology.title}</h3>
                <p>${technology.subtitle}</p>
            </div>
        </button>
    `;
}
```

**Accessibility**: native `<button>` — Tab moves between buttons, Enter/Space activates, no custom ARIA needed (visible title+subtitle text already labels each button, matching the existing icon-pairs-with-text convention). Inside the Welcome dialog's native `<dialog>`, focus is already trapped by the browser; no additional focus-management code needed for the grid itself.

Both components share the same `technology-picker-card` CSS classes and the same `--category-accent`/`--category-icon` CSSOM-hydration mechanism `TechnologyCard.js` already established (§2) — a shared `hydrateTechnologyPickerCards(container)` helper, structurally identical to the existing `hydrateTechnologyCards()`. Both are generated by mapping over `TECHNOLOGIES` from `js/config/technologies/index.js` — no hardcoded option/category lists anywhere in either call site, resolving the existing `upload.html` duplication noted in §2.

### 7.2 `upload.html` changes

The `<select id="category" required>` block is replaced with a `<fieldset>` containing a `<legend>Technology</legend>` and the `TechnologyRadioCard` grid, mapped from `TECHNOLOGIES`. Title field and submit button are unchanged. No change to `createDraft()`, `draftRepository.js`, or the `project_drafts` schema — this is purely an input-widget swap.

### 7.3 Contextual editor hints (Phase 4) — unchanged from prior draft

Small, dismissible inline hint text near specific editor fields, reusing the small-text/`--color-text-secondary` treatment already established by Milestone 20's readiness-checklist label fix:

- Near Title: "A clear, specific title helps people find your build."
- Near Description: no separate hint — the readiness checklist's existing "Description (20+ characters)" label already carries this signal; a duplicate hint would be redundant UI.
- Near the Gallery/cover-image upload zone: "Your first image becomes the cover photo shown across the site."

Gated by **two** conditions, matching §4.3's reasoning (no schema needed for either):
1. The signed-in user has never published (`getMyPublishedBuildCount(userId) === 0` — new function, §7.4).
2. Not locally dismissed (§10's namespaced key scheme).

Once condition 1 becomes false, hints stop rendering permanently for that account — no dismiss-tracking needed for that transition.

### 7.4 New/modified files

- `js/components/TechnologyRadioCard.js`
- `js/components/TechnologyChooserButton.js`
- `js/utils/hydrateTechnologyPickerCards.js` (or colocated with one of the two components above — exact placement is an implementation detail, not a spec decision)
- `js/pages/editor/renderContextualHints.js` — called once from `initEditor()` alongside the existing section renderers.
- `js/repositories/dashboardRepository.js` — add `getMyPublishedBuildCount(userId)`, a `count: "exact", head: true` query (row count only, no data fetch) against `builds` filtered by `user_id`, **not** filtered by `visibility` — see §8.1 for why.

---

## 8. Phase 5: First Publish Celebration

### 8.1 Exact detection flow

The failure mode this section exists to prevent: **querying the published-build count only after `publishDraft()` has already succeeded always returns ≥1 for the account that just published, making "was this the first publish?" permanently unanswerable that way.** The count must be captured *before* the mutation, not derived from its result.

Exact sequence, inside the existing `publishBtn` click handler in [editor/app.js:186](js/pages/editor/app.js:186):

1. On click, before anything else in the existing handler changes: `const publishedCountBeforePublish = await getMyPublishedBuildCount(user.id).catch(() => null);` — captured strictly before the mutation, using the same `user` already in scope from `initEditor(id)`.
   - If this query throws, `publishedCountBeforePublish` is `null`, not `0` — the distinction matters in step 4.
2. The existing flow proceeds unchanged: `isPublishing = true`, `updatePublishBtn()`, `await autosave.flushNow()`, `const build = await publishDraft(draft.id)`.
3. On success (existing `showPublished(build)` call, unchanged): compute `const isFirstPublish = publishedCountBeforePublish === 0;` — note this is strictly `=== 0`, not falsy, so the `null` (query failed) case does **not** count as first-publish.
4. If `isFirstPublish`, show `FirstPublishDialog` (§8.2) after `showPublished(build)` runs. If the pre-count query failed (`null`) or the count was already ≥1, no dialog — **fail closed**: an uncertain first-publish signal must never show a false celebration, since a wrong "your first project is live!" is worse than a missed celebration on an already-successful publish.
5. Any error in steps 1–4 is caught and logged only — it must never block, delay, or alter the actual publish action itself (`publishDraft()`'s own success/failure handling, already in `editor/app.js`, is completely unchanged and untouched by this feature).

**Count definition** (§7.4, restated with reasoning): `getMyPublishedBuildCount` counts every row in `builds` for `user_id = $1`, with **no `visibility` filter**. `builds` rows are only ever created by `publish_draft()` (§2) and unpublishing never deletes them — so a user who published once, then unpublished, has a count of 1 forever, correctly never re-triggering the first-publish celebration on a later re-publish. Filtering to `visibility = 'public'` would incorrectly make an unpublish-then-republish look like a first publish again.

**Accepted concurrency edge case**: two tabs publishing near-simultaneously could both read a pre-count of 0 and both show the celebration once each. Treated as rare, low-stakes, cosmetic duplication — not a defect requiring a DB lock or a persisted "celebrated" flag, consistent with §4.3.

### 8.2 Content and component — final copy

New `js/components/FirstPublishDialog.js`, same native-`<dialog>` construction as `WelcomeDialog`/`confirmDialog`:

- Title: **"Your first project is live"**
- Body: **"You can keep updating it as the build changes."**
- Primary action: **"View Project"** → the just-published build's live URL.
- Secondary action: **"Return to Workshop"** → `pages/workshop.html`.
- Close (×/Esc/backdrop) — no state to persist; §8.1's precondition can't recur for this account.

Respects `prefers-reduced-motion`, matching every other dialog in the system.

---

## 9. Phase 6: Improved Empty States — scope narrowed

Per decision §12.4, in scope for this milestone is **only**:

| Page/section | Current state | Change |
|---|---|---|
| `workshop.html` — zero drafts/projects | Existing `.empty-state` | CTA routes through the same chooser experience as §6.4/§7.1 |
| Profile page, zero-projects owner view (Milestone 20 §7) | Already has "Publish Your First Build" → `upload.html` | Update CTA target for consistency with §7.1's new picker-based `upload.html`; one-line change, not a redesign |
| `upload.html` (publish entry flow itself) | Hero copy ("Give it a name and a technology to begin...") | Reviewed alongside the §7.1/§7.2 control swap — copy only changes if the new fieldset/legend structure requires it for correct labeling; no content redesign |
| Home, signed-in Following-feed empty state ([renderActivityFeed.js:168-176](js/pages/home/renderActivityFeed.js:168)) — *"Your Following feed is empty."* | Already has a CTA ("Explore Projects" → `explore.html`) | Reviewed as the concrete "new-user Home state"; no functional change proposed unless implementation-time review finds the existing CTA insufficient for a zero-build new account specifically |

**Explicitly excluded from this milestone** (decision §12.4): `pages/followers.html`, `pages/following.html`, `pages/notifications.html`, `pages/search.html` (zero-results state) — no changes of any kind, even copy, to these four in Milestone 21.

---

## 10. `localStorage` — namespaced, versioned key scheme

Per decision §12.6: all dismiss/hint state uses one shared, defensive helper — the first `localStorage` wrapper in this codebase with explicit availability handling (§2 notes the two existing call sites have none today).

New file `js/utils/onboardingLocalState.js`:

```js
const NAMESPACE = "specbound:onboarding:v1";

export function isOnboardingFlagSet(key) {
    try {
        return localStorage.getItem(`${NAMESPACE}:${key}`) === "1";
    } catch {
        // Unavailable (private browsing, quota, disabled) — always
        // report "not dismissed." Never throws, never blocks rendering.
        return false;
    }
}

export function setOnboardingFlag(key) {
    try {
        localStorage.setItem(`${NAMESPACE}:${key}`, "1");
    } catch {
        // Best-effort only — the dismissal simply won't persist this
        // session if storage is unavailable.
    }
}
```

**Key namespace**: `specbound:onboarding:v1` — the `v1` suffix means any future change to what a key means (not just its dismissal semantics, but e.g. adding more granular per-hint tracking) can bump to `v2` and every prior dismissal is naturally, harmlessly abandoned rather than misread under new semantics — no migration/cleanup code needed for that case.

**Keys used, both scoped by `userId`** (so one account's dismissal never silently suppresses another account's first-time experience on a shared browser — a real, if rare, correctness gap in the original draft's design):

- `profileChecklistDismissed:{userId}` — §5.2.
- `hint:{hintId}:{userId}:dismissed` — §7.3, one key per hint id (`title`, `gallery`), so dismissing one hint doesn't dismiss the others.

**Explicit non-use**: §5.1 and §8.1 never call into this module — profile completion and first-publish detection are always computed from live server data, exactly per decision §12.6, so both work correctly even with `localStorage` fully unavailable.

---

## 11. Accessibility Behavior — consolidated

- **`WelcomeDialog` and `FirstPublishDialog`** (§6.3, §8.2): native `<dialog>` via `showModal()` — focus moves into the dialog automatically on open (browser default: first focusable element), Esc fires the native `cancel` event (already the dismiss path, matching `confirmDialog()`), backdrop click dismisses (`event.target === dialog` check, same as `confirmDialog()`), and `close()` automatically returns focus to whatever had focus before the dialog opened — this is native `<dialog>` behavior, relied on directly, not reimplemented. Both respect `prefers-reduced-motion` for their open/close transition, matching every other dialog in the system (§3).
- **`TechnologyRadioCard` grid** (§7.1a, `upload.html`): native radiogroup via `<input type="radio" name="category">` — screen readers announce group size/position, Tab enters/exits the group once, Arrow keys move selection within it, Space/click selects, native `required` blocks submission and focuses the group on an invalid submit attempt. The `<label>` wraps the entire visual card, not just the (visually hidden) input, so the full card is the click/tap target on both desktop and mobile — no custom touch-target sizing needed since the whole card area is already the target.
- **`TechnologyChooserButton` grid** (§7.1b, Welcome dialog): native `<button>` — Tab/Enter/Space, no custom ARIA, visible title+subtitle text already serves as the accessible name. Focus containment comes from the enclosing `<dialog>`'s native focus trap.
- **Profile completion checklist** (§5.2): same accessible pattern already verified for the editor readiness checklist in Milestone 20 — real text content per item (not icon-only/color-only), reused directly rather than re-derived.
- **Contextual hints** (§7.3): plain text adjacent to their field, not tooltips/popovers — no focus-management or ARIA-describedby wiring needed, since nothing is hidden-until-hover.
- **Color contrast**: every new surface reuses existing token pairs already verified for WCAG AA elsewhere (dialog body text, card labels, hint text) — reconfirm with axe-core at implementation time per this project's standard process, not a new pairing to design.

---

## 12. Decisions — locked 2026-08-01

1. **Global trigger, not Home-only.** Welcome checks on every authenticated page load via `loadNavbar()` (§6.1), not just `index.html`. Supersedes the prior draft's Home-only design.
2. **Backfill = `created_at`.** Confirmed (§4.2) — matches the prior draft's recommendation, now final.
3. **`upload.html`'s `<select>` → shared technology-card grid — approved**, with three explicit preservation requirements, all satisfied by §7.1/§7.2: (a) stored value unchanged (`TECHNOLOGIES[].id` values, byte-identical to today's hardcoded options), (b) validation contract unchanged (native `required`, same defensive JS check, same submit-blocking behavior), (c) keyboard/mobile accessibility via native radio-group semantics, not custom ARIA.
4. **Empty-state scope narrowed** to Workshop, the Milestone 20 profile/portfolio zero-projects state, `upload.html` itself, and Home's signed-in Following-feed empty state (§9). Followers, Following, Notifications, and Search are explicitly excluded from this milestone — no changes of any kind.
5. **Final copy locked** (§6.2, §8.2) — no more placeholder text for the Welcome screen, chooser title, or first-publish dialog. Remaining placeholder: the three contextual-hint sentences (§7.3) and any label text needed for `upload.html`'s new `<fieldset>`/`<legend>` structure (§7.2) — neither was specified in the copy list this decision covers, and neither is architecturally significant enough to block implementation on.
6. **`localStorage` keys namespaced and versioned** (§10) — `specbound:onboarding:v1:*`, all wrapped in try/catch, all failing open (never dismissed) rather than throwing. Profile completion (§5.1) and first-publish detection (§8.1) never depend on `localStorage` at all, confirmed by construction, not just by intent.
7. **First-publish detection flow fixed** (§8.1) — count captured strictly *before* `publishDraft()` is called, never after; fails closed (no celebration) if the pre-count query fails or returns non-zero; counts all `builds` rows regardless of `visibility` so an unpublish/republish cycle never re-triggers it.

All seven items are closed. No further sign-off is being sought on these seven specifically before implementation begins — remaining open items, if any, are limited to the placeholder copy noted in §12.5.

---

## 13. Explicitly Out of Scope

- Discord, achievements, reputation, moderation tooling, or analytics/telemetry of any kind.
- A multi-step guided product tour or spotlight/walkthrough library.
- Any change to `tokens.css`, the color palette, or `foundation.css`.
- Backfilling or migrating any data beyond the one `onboarding_welcomed_at` column.
- OAuth/social sign-in onboarding paths — not present in this codebase.
- `followers.html`, `following.html`, `notifications.html`, `search.html` — explicitly excluded per §9/§12.4.

---

## 14. Implementation Phases

Matching this repo's established small-commit convention:

1. **Schema.** Apply `0025` to a dev Supabase project only, per the standing dev-application procedure — never applied to production from this environment. Verify the backfill sets `onboarding_welcomed_at = created_at` for all pre-existing rows and that a fresh signup's row is `null`. *Commit: schema.*
2. **`localStorage` helper (§10).** `js/utils/onboardingLocalState.js`, independently testable with a mocked/disabled `localStorage`. *Commit: shared utility.*
3. **Profile completion checklist (§5).** Pure function + Workshop card. No dependency on any other phase. *Commit: profile checklist.*
4. **Technology picker components (§7.1) + `upload.html` migration (§7.2).** Both sibling components, the shared hydration helper, and the `upload.html`/`upload/app.js` read-path change — shippable and testable independently of the Welcome dialog, since `upload.html` is used regardless of onboarding state. *Commit: technology picker.*
5. **Welcome screen (§6).** `WelcomeDialog`, `js/core/onboarding.js`, the `layout.js` hook, `markOnboardingWelcomed`. Depends on phase 4's `TechnologyChooserButton`. *Commit: Welcome screen.*
6. **Contextual editor hints (§7.3–§7.4).** `getMyPublishedBuildCount`, `renderContextualHints`, editor wiring. *Commit: editor hints.*
7. **First publish celebration (§8).** `FirstPublishDialog`, the exact `editor/app.js` publish-handler sequencing from §8.1. *Commit: publish celebration.*
8. **Empty-state pass (§9).** Copy/CTA-target updates only, scoped exactly per §9's table. *Commit: empty states.*
9. **Tests.** Fixture-driven coverage for: `getProfileCompletionChecks`/`isProfileComplete` (all-empty, all-filled, each field independently missing, whitespace-only text fields); `onboardingLocalState.js` with `localStorage` mocked as throwing on every call (must never throw itself); `WelcomeDialog`'s exact single-write-per-exit-path behavior from §6.3 (Continue, ×, Esc, backdrop — each exercised once, `markOnboardingWelcomed` asserted called exactly once per test, never twice); the technology-picker's native-radio validation behavior in `upload.html` (submit blocked with none selected, unblocked once one is); `getMyPublishedBuildCount`/first-publish detection's before/after ordering from §8.1 (fixture asserting the count is read before the mutation, and that a failed pre-count query results in no celebration, per the fail-closed rule). *Commit: tests.*
10. **Verification.** Live-browser pass (desktop + mobile, matching every prior milestone's standard) confirming: the Welcome dialog fires on a non-Home first authenticated page load (not just Home); the technology-picker grid has no horizontal overflow at mobile widths and is fully keyboard-navigable; `prefers-reduced-motion` is respected across all three new dialogs; axe-core clean on `workshop.html`, `upload.html`, and `pages/build/edit.html`; regression confirmation that Milestone 20's existing `tests/profile.test.html` and `tests/editorReadinessDescription.test.html` still pass unmodified.

**Next step**: this specification is ready for implementation to begin at phase 1, pending final go-ahead. Nothing has been implemented yet.
