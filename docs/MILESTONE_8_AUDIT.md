# Milestone 8 — Production Hardening & Full Codebase Audit

Audit date: 2026-07-25. Scope: entire repository (26 HTML pages, 122 JS files, 56 CSS files, 21 test files, 13 migration pairs). This is an **audit-only** deliverable — nothing in this document has been implemented. It combines a direct first-hand review of the Supabase/SQL layer with four parallel research passes over the JS architecture, HTML/CSS accessibility & responsiveness, performance & UX consistency, and the test suite.

---

## A. Executive Summary

Specbound is a mature, 13-milestone build with a genuinely consistent architectural spine in the areas that matter most: every write path goes through a `SECURITY DEFINER` RPC that reads `auth.uid()` internally (never a client-supplied identity), RLS is enabled on every table, the batch-fetch-then-map pattern for avoiding N+1 profile/build lookups is followed correctly almost everywhere, and the optimistic-update pattern (Like/Save/Follow) is implemented identically and correctly across all three features. This is a strong foundation — the hardening work below is real but mostly mechanical, localized, and consolidation-shaped, not a rewrite.

That said, the project is **not launch-ready as-is**. The most important findings:

1. **Two clusters of pages are completely empty** — 5 category pages and 4 legal pages (Privacy, Terms, Community Guidelines, Affiliate Disclosure) are 0-byte files, linked from the homepage and (presumably) required for any real public launch.
2. **A real security/privacy gap**: unpublishing a project does not revoke access to its already-generated image URLs at the Storage RLS layer — only the database rows become hidden.
3. **A currently-broken test** (`restoreButton.test.html`) silently reports nothing while looking like it passes, on an ownership-gated, semi-destructive action.
4. **Missing indexes** on `builds.slug` (the single most common query in the app, with no DB-level uniqueness guarantee either — a real race condition) and on `build_revisions` entirely (zero indexes beyond the primary key), which directly threatens the newly-shipped Activity Feed's scalability.
5. **~40 empty scaffold files/directories** (stub components, services, utils, config, home-page sections) left over from initial project setup, never cleaned up, now large enough to actively confuse future work.
6. **Two authenticated landing pages (Dashboard, Workshop) have no error handling at all** — a single failed request leaves the user on a permanently blank or stuck-"Loading..." page with zero feedback.
7. Duplicated logic (`escapeHtml`, format helpers, avatar-fallback initials) has drifted in places — three files' `escapeAttribute` implementations are measurably weaker than the rest, and category/status labels differ slightly between copies.

None of this requires architectural rework. The plan in section H is scoped to fix, consolidate, and harden what's already here.

---

## B. File-by-file findings (index)

Given the scale (200+ files touched by this audit), findings are organized by category in sections C–F below rather than repeated as one flat per-file list. The files with the most significant, concrete findings are:

| File | Primary issue(s) | Section |
|---|---|---|
| `supabase/migrations/*` (all) | Missing indexes on `builds.slug`, `build_revisions`; one redundant index | C |
| `supabase/migrations/0002_publish_draft_and_visibility.sql` | Storage RLS doesn't check build visibility | C |
| `pages/categories/*.html` (5 files), `pages/legal/*.html` (4 files) | 0-byte, completely empty, linked from the homepage | D, G |
| `js/core/layout.js` | Footer links are inert `<p>` tags; navbar `aria-label` inconsistent | D |
| `js/core/auth.js`, `js/core/notificationBell.js`, every `load*.js` | `getCurrentUser()` called 2+ times per page load | E |
| `js/repositories/mediaRepository.js` | `resolveBuildImageUrls` fires N parallel signed-URL requests, not 1 batched call | E |
| `js/pages/build/loadBuild.js`, `js/pages/profile/loadProfile.js` | One failed secondary fetch clobbers already-rendered primary content | E |
| `js/pages/dashboard/loadDashboard.js`, `js/pages/workshop/loadWorkshop.js` | No top-level error handling (Dashboard); partial (Workshop) | E |
| `js/repositories/commentRepository.js` | Flat 50-comment cap, no pagination, no "showing N of M" UI | E |
| `js/services/imageService.js`, `js/pages/editor/renderGallerySection.js` | `uploadGalleryImage`'s return value unused; storage path duplicated inline instead of reusing `galleryStoragePath()` | F |
| 17 files redefining `escapeHtml` (3 with weaker `escapeAttribute`) | Duplication, minor behavioral drift | F |
| 22 empty `.js` files, 18 empty component directories | Dead scaffold | F |
| `tests/restoreButton.test.html` | Silently broken — produces zero results | D (tests) |
| `tests/followList.test.html`, `tests/notifications.test.html` | Listener-stacking race condition (one active false-positive, one latent) | D (tests) |
| `js/pages/edit-build/app.js` | Orphaned, imports files that don't exist — would crash if ever re-linked | F |

---

## C. Database and security findings

*(This section is from direct first-hand review — I wrote every migration in this schema across this project's history, and re-verified each one fresh for this audit rather than relying on memory.)*

### Index coverage — audited against actual query patterns

Every index created across all 13 migrations, in full:

1. `project_drafts (user_id, updated_at desc)`
2. `project_media (draft_id, display_order)`
3. `revision_media (revision_id, display_order)`
4. `revision_media (revision_id)` unique where `is_cover`
5. `project_drafts (published_build_id)` unique where not null
6. `comments (build_id, created_at)`
7. `saved_builds (user_id, created_at desc)`
8. `notifications (recipient_id, created_at desc)`
9. `notifications (recipient_id)` where `read_at is null`
10. `follows (follower_id)`
11. `follows (following_id)`

**Missing (Critical):**
- **`builds.slug` has no unique index or constraint anywhere.** This is the primary lookup key for `getBuildBySlug()` — every single project-page view — and is also checked in a loop during `publish_draft()`'s first-publish slug-uniqueness logic (`while exists (select 1 from builds where slug = v_slug) loop ...`). With no index, this is a sequential scan on every project page load; with no unique constraint, the uniqueness guarantee is purely application-level and racy (two concurrent first-publishes with colliding slugs could theoretically both pass the `exists` check before either inserts). **Recommend**: `create unique index builds_slug_unique_idx on builds (slug);` — this also closes the race, since a second concurrent insert would now fail atomically instead of silently succeeding with a duplicate.
- **`build_revisions` has zero indexes beyond its primary key.** This is used by: `getBuildRevisions(buildId)` (every build page load, ordered by `created_at`), `publish_draft()`'s republish version-bump lookup (`where build_id = ... order by created_at desc limit 1`), and — most severely — the new `get_activity_feed()` (0013), which both needs `order by created_at desc, id desc` across the *entire table* for its main pagination query, and runs a correlated subquery filtered by `build_id` and ordered by `(created_at, id)` once per candidate row for activity-type classification. This table is the direct content source for the home page. **Recommend**: `create index build_revisions_build_id_created_at_id_idx on build_revisions (build_id, created_at, id);` (serves per-build lookups and the correlated subquery) plus `create index build_revisions_created_at_id_idx on build_revisions (created_at desc, id desc);` (serves the feed's global ordering/pagination).
- **`builds.user_id`** — no dedicated index found; used by `getMyBuilds()` and `getProfileBuilds()`. Lower urgency than the two above (both queries are already scoped to one user), but worth adding: `create index builds_user_id_idx on builds (user_id);`
- **`profiles.username`** — no unique constraint/index found in any tracked migration. Since `profiles` predates this migration history (like `builds`), this *may* already exist from the original bootstrap outside version control — **this needs live verification, not an assumption either way** (see Phase 0 below).

**Redundant (Low):**
- `follows_follower_id_idx` (0012) is redundant with the implicit index the table's own `unique (follower_id, following_id)` constraint already provides (a unique index on `(follower_id, following_id)` already serves any `follower_id`-only lookup via leftmost-prefix matching). Safe to drop — saves write overhead on every follow/unfollow with no read-side cost. `follows_following_id_idx` is *not* redundant (following_id is the second column of the composite unique index, not usable via leftmost-prefix alone) and should stay.

**Caveat**: I have no live database introspection access from this environment (confirmed by this project's own `supabase/migrations.md` convention). The findings above are what the *tracked migrations* create — `builds` and `profiles` both predate migration tracking, so it's possible (though I found no evidence of it) that a `builds.slug` or `profiles.username` index/constraint already exists from the original, untracked bootstrap. **Phase 0 must start with a live `SELECT indexname, indexdef FROM pg_indexes WHERE schemaname='public'` query in the Supabase SQL editor** before any index migration is written, to avoid creating a duplicate or acting on stale assumptions.

### Security: Storage RLS gap (Critical)

`supabase/migrations/0002_publish_draft_and_visibility.sql`, the policy `"Anyone can read files referenced by a published revision"`:

```sql
create policy "Anyone can read files referenced by a published revision" on storage.objects
    for select using (
        bucket_id = 'project-images'
        and exists (
            select 1 from public.revision_media rm
            where rm.storage_path = storage.objects.name
        )
    );
```

This policy checks only that a `revision_media` row references the path — **it never checks the parent build's `visibility`.** Compare this to every *database-row* read path (`builds`, `build_revisions`, `revision_media` SELECT policies), which all correctly gate on `visibility = 'public' or user_id = auth.uid()`. The practical consequence: when an owner unpublishes a project via `set_build_visibility()`, the build/revision *rows* correctly become invisible to everyone else, but the underlying *image files* remain signable and fetchable by anyone who already has (or can guess/record) the storage path — including via a brand-new signed-URL request made *after* unpublishing. This is a real privacy gap for anyone who unpublishes a project expecting it to become fully private.

**Recommend**: rewrite this storage policy to join through to `builds.visibility`, e.g.:
```sql
using (
    bucket_id = 'project-images'
    and exists (
        select 1 from public.revision_media rm
        join public.build_revisions br on br.id = rm.revision_id
        join public.builds b on b.id = br.build_id
        where rm.storage_path = storage.objects.name
          and (b.visibility = 'public' or b.user_id = auth.uid())
    )
);
```

### SECURITY DEFINER / INVOKER audit — all 14 custom functions reviewed

Every function was checked for: `search_path` pinned, `revoke all from public`, correct grant target, and ownership/authorization validation. **All 14 are correctly configured** — this is worth stating plainly as a strength, not just an absence of findings:

| Function | Security mode | Grant | Ownership check | Notes |
|---|---|---|---|---|
| `set_updated_at()` | INVOKER | (trigger only) | N/A | Correctly not elevated — only touches the row already being written |
| `publish_draft()` | DEFINER | authenticated | ✅ draft owner | |
| `set_build_visibility()` | DEFINER | authenticated | ✅ build owner | |
| `create_comment()` | DEFINER | authenticated | N/A (self-service) | Visibility-gated |
| `delete_comment()` | DEFINER | authenticated | ✅ author or build owner | |
| `bump_likes_count()` | DEFINER | (trigger only, revoked from PUBLIC) | N/A | Needs DEFINER to bypass builds' RLS write lockdown |
| `set_build_like()` | DEFINER | authenticated | N/A (self-service) | Strict public-only visibility gate |
| `set_build_saved()` | DEFINER | authenticated | N/A (self-service) | Deliberately asymmetric visibility gate |
| `record_build_view()` | DEFINER | **anon + authenticated** | N/A (self-service) | Correctly the only RPC needing anon access |
| `create_notification()` | DEFINER | **no grant at all** | N/A | Correctly callable only from other DEFINER functions |
| `mark_notification_read()` | DEFINER | authenticated | ✅ recipient | |
| `mark_all_notifications_read()` | DEFINER | authenticated | ✅ recipient (via WHERE) | |
| `bump_follow_counts()` | DEFINER | (trigger only, revoked from PUBLIC) | N/A | Same as bump_likes_count |
| `set_follow()` | DEFINER | authenticated | N/A (self-service) | Self-follow blocked at both app + CHECK-constraint level |
| `get_activity_feed()` | **INVOKER** | anon + authenticated | N/A (read-only) | Correctly the only function needing no elevated privilege — everything it reads is already RLS-visible to the caller |

**Positive pattern worth preserving**: every single write function reads `auth.uid()` internally and never accepts a caller-supplied identity parameter for authorization purposes — this is a consistent, load-bearing security property across the entire schema and should be enforced as a hard rule for any future RPC.

**One operational caveat worth documenting** (not a bug): `create_notification()`'s zero-grant design relies on `create_comment()`/`set_build_like()`/`set_build_saved()` sharing the same owning role as `create_notification()` itself (a `DEFINER` function's internal calls run with its own owner's implicit privilege). This is true by default when every migration is run via the same Supabase SQL editor session/role, but would break silently if a future migration were ever run under a different owning role. Worth a one-line comment in the schema, not a code change.

### Migration/rollback hygiene

- All 13 migrations have a matching, present rollback file (confirmed via directory listing) — full 1:1 hygiene, no gaps.
- `supabase/migrations.md`'s status tracking (`Proposed — not yet applied`) is **likely stale** for most migrations from 0007 onward — six further milestones were built successfully assuming those migrations were applied, but the log was never updated to `Applied` (per this project's own convention, that flip only happens on an explicit real-backend confirmation logged in conversation, which didn't happen for 0007–0013 in a way that updated the doc). **Recommend**: reconcile `migrations.md` against the live database's actual applied state (Phase 0) before Milestone 8 proceeds, since accurate status matters for assessing launch readiness.
- `0002`'s known, already-documented `publish_draft()` bug (fixed by `0004`) is correctly left as-applied/unedited per the project's own "don't rewrite applied migrations" convention — this is being followed correctly and should continue to be.

### Positive findings worth calling out

- RLS is enabled on every single table in the schema, with no exceptions found.
- The "private-to-self vs. fully-public" RLS shape is applied deliberately and correctly per table's actual privacy requirement (likes/saves/notifications/build_view_cooldowns = private-to-self or zero-access; follows = deliberately fully public, explicitly documented as a departure).
- Trigger-maintained counters (`likes_count`, `views`, `followers_count`, `following_count`) consistently use `coalesce(..., 0)` and `greatest(0, ...)` guards against null/negative drift.
- `js/core/config.js`'s Supabase key is confirmed to be the `sb_publishable_...` anon key, not a service-role key — correct and safe to expose client-side.

### One supply-chain hardening item

`js/core/supabase.js` imports `@supabase/supabase-js` from `https://cdn.jsdelivr.net/npm/@supabase/supabase-js/+esm` with **no version pin**. This is a single, centralized import (only one file references it, which makes fixing it trivial), but as written it means a breaking upstream release — or a compromised CDN — silently ships to production with no warning. **Recommend**: pin to an exact version (e.g. `@supabase/supabase-js@2.45.0/+esm`) at minimum before launch.

---

## D. Accessibility and responsive findings

*(From the dedicated HTML/CSS audit pass, cross-checked against JS-generated markup.)*

### Accessibility

- **Footer links are not real links** (`js/core/layout.js`, `loadFooter()`): "Explore", "Publish", "Categories", "Workshop", "Profiles", "Privacy", "Terms" all render as plain `<p>` tags, styled to look like navigation but completely inert — unfocusable, unclickable. Site-wide, since every page shares this footer. **High.**
- **7 of 8 form fields on `pages/settings.html`** (Display Name, Username, Bio, Location, Website, GitHub, YouTube) have `<label>` elements with no `for` attribute and no wrapping — zero programmatic label association, despite matching `id`s existing on the inputs. **High.**
- **Toasts have no `role`/`aria-live`** anywhere in `js/core/toast.js` or the container in `js/core/layout.js` — the app's primary async-feedback mechanism (used by ~60 call sites: likes, saves, follows, comments, uploads, settings) is entirely invisible to screen reader users. **High.**
- **No global `prefers-reduced-motion` override** in `css/base/animations.css`, which applies a blanket `transition` to nearly every element plus a `.fade-in` transform/opacity animation. Only `css/components/skeleton.css` handles reduced motion, and only for its own shimmer. **High.**
- **`js/components/ComponentAutocomplete.js`** (used in the editor's Specifications tab, a primary, form-heavy interaction) implements a partial, incomplete ARIA combobox pattern: `role="combobox"` and `aria-expanded` are present, but the results list never gets `role="listbox"`, there's no `aria-controls`, and arrow-key navigation never sets `aria-activedescendant` — a screen reader user gets no announcement of which option is highlighted while navigating. **High.**
- Activity feed tabs (`index.html`) are real `<button>`s but have no `role="tablist"`/`role="tab"`/`aria-selected`, unlike the editor's tabs (`pages/build/edit.html`), which correctly implement the full pattern. **Medium.**
- Explore's filter pills / lifecycle buttons toggle a visual `.active` class but never set `aria-pressed`, unlike Like/Save/Follow buttons, which do. **Medium.**
- Heading hierarchy skip on `pages/build/build.html`: `<h1>` is followed by an `<h3>` (creator name) before any `<h2>` appears. **Medium.**
- Hint/validation text elements (`#commentFormHint`, `#likeHint`, `#saveHint`, `#followHint`) correctly use visible text (never `title` attributes — confirmed zero `title=` occurrences anywhere in the codebase, a real project-wide strength), but none have `aria-live`, so screen reader users aren't notified when they appear. **Medium.**
- Modals (`css/components/modal.css`) have no corresponding focus-trap/focus-return JS anywhere — modal a11y is entirely unimplemented, not just incomplete (no `js/components/Modal.js` exists; it's one of the empty stub files). **Medium.**
- Color-contrast risk (flagged, not measured precisely): `--color-text-muted: rgba(255,255,255,0.46)` is used for real readable content (timestamps, labels) in multiple places and is likely borderline/failing WCAG AA at that opacity against the near-black background. `--color-border: rgba(255,255,255,0.08)` may fail the 3:1 non-text-contrast requirement for form-input boundaries. **Flag for the redesign's color pass, not urgent now.**
- Genuine strengths confirmed: zero `onclick=`/div-as-button patterns anywhere; every interactive element is a real `<button>`/`<a>`; the notification bell and builder-menu dropdowns both correctly implement click-outside-to-close, Escape-to-close, and focus-return; every `<img>` tag (static and JS-generated) has non-empty, descriptive `alt` text.

### Responsive / mobile

- **Real, verified cascade bug**: the builder/account dropdown does **not** actually go static/full-width on mobile, despite `css/layout/navbar.css`'s media query appearing to set exactly that. `css/components/dropdown.css` is `@import`ed *after* `navbar.css` in `css/styles.css` and declares `.builder-dropdown { position: absolute; ... }` unconditionally — later source order wins the cascade at equal specificity, so the mobile override is silently shadowed. The notification-bell dropdown (styled entirely within its own file) doesn't have this problem. **High** — affects every signed-in page's account menu on mobile. **Recommend**: move the mobile override into `dropdown.css` itself, or reorder the imports.
- Breakpoint values are inconsistent project-wide: the dominant set (500/600/700/720/900/960/1100px) is joined by unexplained one-off values (800px in dashboard/footer, 980px in explore, 650px in continue/blueprint-feed) with no evident reason for the divergence. **Medium.**
- `.follow-row` (Followers/Following pages) has no narrow-viewport stacking at all, unlike the structurally identical `.notification-row`, which correctly stacks under 600px — at 375px, avatar + username + Follow button are squeezed with no truncation on long usernames. **Medium.**
- Several icon-only touch targets are below the ~44×44px guidance: notification bell (40×40), modal close (40×40), `.btn-small` (~30-32px tall, used for Follow/Unfollow buttons in list rows). The nav toggle hamburger is correctly 44×44px, showing the team already knows the target size elsewhere. **Medium.**
- Two duplicate, *conflicting* CSS class definitions found: `.creator-card`/`.creator-label` are defined once in `css/pages/build/hero.css` and again (with different values) in `css/pages/build/build.css`, which imports `hero.css` and then re-declares the same selectors later — the `hero.css` versions are silently dead. **Medium**, real maintenance hazard.
- `css/pages/build/hero.css` begins with a **self-import** (`@import url("./hero.css")`) followed by duplicate imports of `specifications.css`/`timeline.css`/`gallery.css`, all three of which are already correctly imported by the parent `build.css` one file up. Harmless in effect (browsers break the cycle, rules are idempotent) but confusing dead code. **Low-Medium**, recommend cleaning up.
- The best-tiered responsive component found in the whole audit: `.blueprint-overview-grid` (build page) steps 5→3→2→1 columns cleanly at 1100/720/600px — worth using as the reference pattern for other grids being fixed.

---

## E. Performance findings

*(Combines the performance/media/UX audit and the JS query-efficiency audit.)*

### Client query efficiency

- **`getCurrentUser()` is called at least twice, concurrently, on every authenticated page load** — once inside `loadNavbar()` (`js/core/layout.js`), once again inside the page's own load flow (confirmed on `loadBuild.js`, `loadProfile.js`, `loadFollowList.js`, `home/app.js`, and via `requireAuth()` on `loadDashboard.js`, `loadWorkshop.js`, `settings/app.js`, `upload/app.js`, `notifications/loadNotifications.js`, `editor/app.js`, `continue.js`). `getCurrentUser()` calls `supabase.auth.getUser()`, a real server round-trip (not a local session read) — this doubles a real network cost on every single page view in the app. **High**, trivial and low-risk to fix. **Recommend**: memoize the in-flight/resolved promise in `auth.js` for the lifetime of a page load, reset only on sign-out/auth-state-change.
- The current user's own **profile row is separately re-fetched** on top of the above on Dashboard, Workshop, and Settings (once narrowly for the navbar's username label, once fully for page content). **Medium.**
- **`resolveBuildImageUrls()` (`js/repositories/mediaRepository.js`) is the app's designated "batch" image-resolution helper but is actually N parallel per-item Storage requests**, not one batched call — `Promise.all(builds.map(async build => ({ ...build, image_url: await resolveImageUrl(build.image_url) })))`. Supabase Storage supports a genuine batch `createSignedUrls` endpoint that isn't used. Since Explore fetches up to 100 builds (`getNewestBuilds(100)`), a single Explore page load can fire **up to 100 concurrent signed-URL requests**. **High** — this is the one function everyone trusts as "the batch helper," and it doesn't actually batch at the network level. **Recommend**: switch to Storage's `createSignedUrls(paths, expiry)` batch endpoint.
- `renderComments.js`'s avatar-URL resolution batches the *profile* lookup correctly but not the *signing* step — the same author's avatar gets re-signed once per comment they've posted in a thread, with no dedup by `profile.id`. Bounded by the 50-comment cap, so **Medium**, not urgent.
- One sequential (not parallelized) upload loop found: `imageService.js`'s `uploadAvatar()` uploads its 4 size variants one at a time instead of via `Promise.all`. **Low.**
- No unused-fetched-data or unused-import issues found beyond the above — the batch-fetch-then-map convention (`getProfilesByIds`, `attachBuildProfiles`, `getBuildsByIds`, `enrichNotifications`) is correctly and consistently applied at every other call site checked.

### Graceful degradation on secondary-request failure

- `js/pages/workshop/loadWorkshop.js` is the correct reference pattern: `getMyDrafts()` and the saved-builds loader are each independently `.catch()`-wrapped with a fallback, and `renderWorkshop.js` distinguishes a genuine failure (`null`) from a genuine empty state (`[]`).
- **`js/pages/build/loadBuild.js` and `js/pages/profile/loadProfile.js` both violate this pattern** — a single outer try/catch wraps *everything*, including secondary/cosmetic data (revision list, comment count). If a secondary fetch throws after the primary content has already successfully rendered, the outer catch overwrites already-shown content with a generic "unavailable" error message. **High**, on the app's two highest-traffic page types. **Recommend**: split each into primary (keep current catch-and-error-message behavior) and secondary (wrap individually, fallback + `console.error`, matching `loadWorkshop.js`).
- **`js/pages/dashboard/loadDashboard.js` has *no* try/catch at all.** A single throw anywhere in its `Promise.all` leaves the user on a permanently blank dashboard (the static HTML has no placeholder text) with zero indication anything failed. **High** — this is the account's primary post-login landing page.
- **`js/pages/workshop/loadWorkshop.js`'s own top-level `Promise.all` still has 3 of its 5 entries unguarded** (`getProfile`, `getMyBuilds`, `getMyRevisionCount`) — if any of those three throws, the whole page is stuck on its static "Loading..." text forever, despite the file's own drafts/saved-builds entries being correctly hardened. **High**, same page class as Dashboard.

### Pagination and unbounded lists

- **Comments have a flat, undocumented-to-the-user 50-row cap with zero pagination** — `commentRepository.js`'s limit is a deliberate, documented product decision, but there is no "showing 50 of N" indicator and no way to reach comment #51 onward; on a build with more than 50 comments, older ones become permanently invisible to everyone except the original poster's own session. **High**, given comments is explicitly one of the higher-write-volume tables.
- **Workshop's three list sections (My Projects, Drafts, Saved Projects) have zero pagination or limit of any kind** — unlike every feature shipped since (notifications/followers/following/activity-feed, all correctly keyset-paginated at 20/page). A prolific builder would have every Workshop page load fetch and render their entire history unconditionally. **Medium** pre-launch (low current user count), but a clear, easy-to-predict growth risk worth fixing proactively rather than reactively.
- List re-renders on "Load More" (activity feed, notifications, follow lists) rebuild the *entire accumulated list* via `innerHTML =` rather than appending only the new page — real but assessed as an acceptable simplicity tradeoff at this app's realistic scale (a genuine problem only past ~100+ loaded items). **Medium**, not urgent. Single-item mutations (marking one notification read, one follow toggle) are correctly *not* subject to this — they patch just the one affected node.

### Images

- `BlueprintCard.js`'s cover image correctly has `loading="lazy"`; `decoding="async"` is used **zero times anywhere in the codebase**. Mechanical, low-risk, worth doing everywhere in one pass. **Low-Medium.**
- No `srcset`/responsive images anywhere — confirmed, flagged for the redesign, not urgent now per the stated constraint.
- `js/pages/dashboard/renderDashboard.js`'s build-card image is the one card renderer that doesn't reuse `BlueprintCard` and has neither lazy-loading nor output escaping on interpolated values. **Medium.**

---

## F. Dead code and duplication list

### Duplicated logic

| Pattern | Duplicated in | Severity | Notes |
|---|---|---|---|
| `escapeHtml` | 17 files (full list in appendix below) | Medium | Character-for-character identical in 14; genuinely worth consolidating into `js/utils/` |
| `escapeAttribute` | 14 files | Medium-High | **3 files** (`renderGallerySection.js`, `renderResourcesSection.js`, `settings/app.js`) only escape `&` and `"`, not `<`/`>`/`'` — a real, if narrow, behavioral inconsistency in a security-relevant function |
| `formatCategory` | `BlueprintCard.js`, `featured.js`, `renderBuild.js` | Medium | Three slightly different category-label maps — `featured.js` is missing the `homelab` case entirely, falling through to a raw category string |
| `formatStatus` | `continue.js`, `renderBuild.js`, `renderDashboard.js` | Medium | |
| `formatDate` (relative) | `renderComments.js`, `renderTimeline.js` | Medium | One uses `month: "long"`, the other `month: "short"` — a real, visible inconsistency |
| Avatar-initial fallback (`username.charAt(0).toUpperCase()`) | 5 files | Medium | |
| `formatUpdatedDate` | `BlueprintCard.js`, `renderWorkshop.js`, `DraftCard.js` | Low-Medium | |
| `clampProgress` | `BlueprintCard.js`, `renderBuild.js`, `renderWorkshop.js` | Low | |
| Hand-rolled empty-state HTML | ~10 files | Medium | `BlueprintFeed.js` already centralizes this correctly for build lists; other list types don't reuse it |
| Gallery storage-path construction | `imageService.js` exports `galleryStoragePath()`, but `renderGallerySection.js:61` reconstructs the same path inline via a template literal instead of calling it | Low-Medium | Found during this audit's own direct review — `uploadGalleryImage()`'s return value (a public URL) is also never consumed by its only caller, dead output |

**The root cause for most of the above**: `js/utils/formatCategory.js`, `formatDate.js`, `formatStatus.js`, and `slugify.js` all exist as **0-byte empty files**, apparently intended to hold exactly this shared logic and never filled in. This is worth fixing as "implement once, delete the duplicates," not just "delete the empty files."

### Dead / unused files (confirmed zero importers)

**22 empty (0-byte) `.js` files:**
`js/components/avatar.js`, `exploreCard.js`, `Modal.js`, `profileBuildCard.js`, `revisionCard.js` · `js/config/permissions.js` · `js/features/importer.js` · `js/repositories/searchRepository.js` · `js/services/affiliateService.js`, `importService.js`, `moderationService.js`, `uploadService.js` · `js/utils/formatCategory.js`, `formatDate.js`, `formatStatus.js`, `slugify.js` · `js/pages/home/sections/community.js`, `featuredCreator.js`, `featuredGuides.js`, `hero.js`, `recentlyUpdated.js`, `technologies.js`, `trending.js`

**18 empty component-scaffold directories** under `js/components/`: `Avatar/`, `Badge/`, `button/`, `Card/`, `Dropdown/`, `EmptyState/`, `Form/`, `Input/`, `Modal/`, `Navbar/`, `Pagination/`, `SearchBar/`, `Skeleton/`, `SpotlightSlide.js/` (a directory literally named with a `.js` extension), `Tabs/`, `Tag/`, `Toast/`, `Tooltip/`, `UploadZone/`.

**4 empty CSS files**: `css/components/input.css`, `navbar.css`, `tab.css`, `css/themes/dark.css` — none are `@import`ed anywhere; the real styles for each concern live in a different, correctly-used file.

**Non-empty but dead:**
- `js/features/upload.js` (373 lines) — explicitly documented as dead in `docs/CHANGELOG.md`.
- `js/pages/edit-build/app.js` (157 lines) — no HTML page loads it, **and it's internally broken**: imports `js/services/index.js` and `js/templates/pcBuild.js`, neither of which exist. Would throw a module-resolution error if ever re-linked.
- `js/config/index.js` — unimported barrel file with its own broken self-referential import (`../../config/index.js`, resolving outside the project).
- `js/config/routes.js`, `statuses.js`, `filters.js`, `socials.js` — unimported (routes.js in particular is a missed-reuse case: every page hardcodes its own relative path strings instead).

**Orphaned but still reachable (needs a product decision, not just deletion):**
- `pages/build/continue.html` / `js/pages/build/continue.js` — no in-app link reaches it anymore (multiple in-code comments confirm the flow is retired), but it's still directly URL-accessible and does execute.
- `pages/dashboard.html` — already flagged in `docs/CHANGELOG.md` as an intentionally-unlinked duplicate of Workshop.

---

## G. Risk-ranked issues

### Critical

1. **`pages/categories/*.html` (5 files) and `pages/legal/*.html` (4 files) are completely empty**, linked from the homepage and (for the legal pages) required for a real public launch.
2. **Storage RLS gap**: unpublishing a project doesn't revoke image-file access at the Storage layer (`0002`'s "Anyone can read files referenced by a published revision" policy).
3. **`tests/restoreButton.test.html` is silently broken** — produces zero results while looking like a passing test, on an ownership-gated draft-overwriting action.
4. **No unique index/constraint on `builds.slug`** — a real TOCTOU race at publish time plus unindexed lookups on the single most common query in the app.
5. **`build_revisions` has zero indexes** — directly threatens the newly-shipped Activity Feed and every build-page load as data grows.

### High

6. `getCurrentUser()` double-fetched on every authenticated page load.
7. `resolveBuildImageUrls()` fires N parallel (not batched) signed-URL requests — up to 100 concurrent on Explore.
8. `loadBuild.js`/`loadProfile.js`: a failed secondary fetch clobbers already-rendered primary content.
9. Dashboard has no error handling at all; Workshop's `Promise.all` is only partially hardened — both can leave the user on a permanently blank/stuck page.
10. Comments have a silent, undisclosed 50-row cap with no pagination — content beyond it is permanently invisible.
11. `tests/followList.test.html` (currently produces a false-positive pass via a listener-stacking race) and `tests/notifications.test.html` (same latent bug, not yet triggered).
12. Zero test coverage for login/signup, upload, and any server-side authorization-rejection path (e.g., a non-owner attempting `deleteRevision`).
13. `escapeHtml`/`escapeAttribute` duplicated in 17 files; 3 have measurably weaker escaping behavior than the rest.
14. 7 of 8 Settings form fields have no programmatic label association.
15. Toasts have no `aria-live`/`role` — the app's primary feedback mechanism is invisible to screen readers.
16. No global `prefers-reduced-motion` support.
17. Footer navigation links are inert, unclickable `<p>` tags, site-wide.
18. Builder/account dropdown doesn't actually go responsive on mobile (CSS import-order cascade bug).
19. `ComponentAutocomplete`'s ARIA combobox pattern is incomplete on a primary editor interaction.
20. `js/pages/edit-build/app.js` is dead but internally broken — a landmine if ever accidentally re-linked.
21. Notifications' "Mark all read" shows no error toast on failure, unlike every other mutating action in the app.

### Medium

~25 findings, spanning: the ~40-file dead-scaffold cluster (in aggregate, not individually); format-helper duplication with real behavioral drift; unbounded Workshop lists; the `hero.css` self-import + conflicting duplicate `.creator-card` definitions; build.html's heading-hierarchy skip; inconsistent `loading="lazy"`/`decoding="async"` application; growing-full-list-rerender on Load More (assessed as acceptable-for-now); breakpoint inconsistency across pages; sub-44px touch targets on several icon buttons; `gallery20.test.html`'s thin-margin timing assertion; shallow pagination-cursor assertions in two tests; sequential avatar-variant uploads; un-deduped avatar re-signing in comments; color-contrast risk on muted text/borders (flagged for redesign); `js/features/` folder-boundary confusion; the 504-line `explore/app.js` monolith; several pages bypassing the repository layer to call Supabase directly; the notification bell's harmless-but-real `document`-listener leak in tests; the orphaned `continue.html` page; unpinned Supabase CDN import version; stale `migrations.md` status tracking; redundant `follows_follower_id_idx`.

### Low

Inconsistent navbar `aria-label` presence; inconsistent "Could not load..." message phrasing across ~8 features (cataloged verbatim in the source audit); missing `decoding="async"` (mechanical, low-risk fix); no `srcset`/responsive images (explicitly deferred); empty PascalCase component-scaffold folders; `js/config/index.js`'s broken-but-unreachable self-import; the Unpublish confirm() dialog on a technically-reversible action (borderline, defensible either way).

---

## H. Proposed Milestone 8 implementation phases

Ordered for dependency and risk — each phase is independently shippable and reviewable, matching this project's established one-milestone-at-a-time workflow. Phase 0 is verification-only (no code changes) and must happen first since it resolves two open unknowns that later phases depend on.

**Phase 0 — Ground truth verification (no code changes)**
Run live introspection against the actual Supabase database (`pg_indexes`, `pg_constraint`) to confirm the true current state of `builds.slug`/`profiles.username` indexing before writing any index migration, and reconcile `migrations.md`'s status tracking against which migrations are actually applied.

**Phase 1 — Critical fixes**
The empty category/legal pages (build minimal real content, or a documented interim redirect to Explore for categories); the Storage RLS visibility gap; fix `restoreButton.test.html`; the two index gaps (`builds.slug`, `build_revisions`) via a new migration.

**Phase 2 — Dead code and duplication cleanup**
Delete the ~40 confirmed dead files/directories; implement the 3 empty `js/utils/` format helpers and delete their duplicated copies; consolidate `escapeHtml`/`escapeAttribute` into one shared module and fix the 3 weaker copies; fix the gallery-upload dead-return-value/duplicated-path issue.

**Phase 3 — Query efficiency and error-handling hardening**
Memoize `getCurrentUser()` per page load; batch `resolveBuildImageUrls()` via Storage's real batch endpoint; split `loadBuild.js`/`loadProfile.js` into primary/secondary error handling; add error handling to `loadDashboard.js` and finish hardening `loadWorkshop.js`'s remaining unguarded fetches.

**Phase 4 — Accessibility pass**
Fix Settings' 7 unlabeled fields; add `aria-live`/`role` to toasts and hint elements; add a global `prefers-reduced-motion` override; make footer links real `<a>` tags; complete `ComponentAutocomplete`'s ARIA pattern; add `role="tablist"`/`aria-pressed` to the activity-feed tabs and Explore's filter pills; fix the build.html heading skip.

**Phase 5 — Responsive/mobile fixes**
Fix the builder-dropdown mobile cascade bug; add mobile stacking to `.follow-row`; consolidate breakpoints toward the dominant set; bump sub-44px touch targets on icon-only controls.

**Phase 6 — Pagination gaps**
Add real pagination (or at minimum a "showing N of M" affordance) to comments; add keyset pagination to Workshop's three list sections, matching the established pattern.

**Phase 7 — Test suite hardening**
Fix the listener-stacking race in `followList.test.html`/`notifications.test.html`; add coverage for login/signup, upload, and at least one authorization-rejection path (`deleteRevision.js` and/or a non-owner RPC call); re-verify `searchPage.test.html` in a foregrounded browser.

**Phase 8 — Remaining medium items**
`hero.css` self-import/duplicate-selector cleanup; format-label consistency (`formatDate`'s month format); pin the Supabase CDN import version; split the `explore/app.js` monolith into `load`/`render`; route the pages still bypassing the repository layer through it.

---

## I. Exact files expected to change, by phase

**Phase 0**: none (SQL introspection only) — `supabase/migrations.md` (status reconciliation, doc-only).

**Phase 1**: `pages/categories/*.html` (5), `pages/legal/*.html` (4), new `supabase/migrations/0014_storage_visibility_fix.sql` + rollback, new `supabase/migrations/0015_index_hardening.sql` + rollback, `tests/restoreButton.test.html`.

**Phase 2**: delete list — `js/components/{avatar,exploreCard,Modal,profileBuildCard,revisionCard}.js`, `js/config/{permissions,index,routes,statuses,filters,socials}.js`, `js/features/{importer,upload}.js`, `js/repositories/searchRepository.js`, `js/services/{affiliateService,importService,moderationService,uploadService}.js`, `js/pages/home/sections/*.js` (7), `js/pages/edit-build/app.js`, 18 empty `js/components/*/` directories, `css/components/{input,navbar,tab}.css`, `css/themes/dark.css`. Implement + consolidate: `js/utils/{formatCategory,formatDate,formatStatus}.js`, new `js/utils/escapeHtml.js`. Update every one of the ~20 files currently redefining these locally to import instead. `js/services/imageService.js`, `js/pages/editor/renderGallerySection.js`.

**Phase 3**: `js/core/auth.js`, `js/core/layout.js`, `js/repositories/mediaRepository.js`, `js/pages/build/loadBuild.js`, `js/pages/profile/loadProfile.js`, `js/pages/dashboard/loadDashboard.js`, `js/pages/workshop/loadWorkshop.js`.

**Phase 4**: `pages/settings.html`, `js/core/toast.js`, `css/components/toast.css`, `css/base/animations.css`, `js/core/layout.js` (footer), `js/components/ComponentAutocomplete.js`, `index.html` + `js/pages/home/renderActivityFeed.js`, `pages/explore.html` + `js/pages/explore/app.js`, `pages/build/build.html`.

**Phase 5**: `css/components/dropdown.css`, `css/layout/navbar.css`, `css/pages/followlist/followlist.css`, various `css/components/*.css` touch-target sizing.

**Phase 6**: `js/repositories/commentRepository.js`, `js/pages/build/renderComments.js`, `js/repositories/dashboardRepository.js`, `js/repositories/savedRepository.js`, `js/repositories/draftRepository.js`, `js/pages/workshop/loadWorkshop.js`, `js/pages/workshop/renderWorkshop.js`.

**Phase 7**: `tests/followList.test.html`, `tests/notifications.test.html`, new `tests/login.test.html`, `tests/upload.test.html`, `tests/deleteRevision.test.html` (or equivalent), `tests/searchPage.test.html` (re-verify only).

**Phase 8**: `css/pages/build/hero.css`, `css/pages/build/build.css`, `js/pages/build/renderComments.js`, `js/pages/build/renderTimeline.js`, `js/core/supabase.js`, `js/pages/explore/app.js` (split into `loadExplore.js`/`renderExplore.js`), `js/pages/edit-revision/app.js`, `js/pages/settings/app.js`.

---

## J. Intentionally deferred to Milestone 9 or after launch

- **The full visual redesign** — explicitly out of scope for this audit per the stated constraint; the color-contrast risks flagged in section D are meant to inform that pass, not be fixed piecemeal now.
- **`srcset`/responsive image variants** — confirmed absent, real but low-urgency; bundle with the redesign since it's naturally a design-system-level change (multiple image sizes need to exist first).
- **Full category browse-page content** (curated per-category project listings, imagery, copy) beyond the minimal Phase-1 fix — building genuinely good category landing pages is a content/product task, not a hardening task.
- **`build_revisions` "completed" activity type / a real project-status-management feature** — explicitly excluded from Milestone 7D on the same grounds (nothing in the app currently sets `builds.status` beyond `'planning'`); still true, still a separate future feature.
- **`pages/build/continue.html` / `pages/dashboard.html` disposition** — flagged as orphaned/duplicate respectively; deleting either is a product decision (confirm nothing depends on direct URL access) not a pure hardening task, worth a quick explicit go/no-go rather than silent deletion.
- **Full component-by-component list-virtualization or append-only DOM patching** for growing lists (Load More rebuilding the full list) — assessed as an acceptable tradeoff at current and near-term scale; revisit only if real usage data shows it's actually a problem.
- **Rate limiting / abuse protection** across write RPCs — already explicitly deferred at every milestone since 6D as a "reasonable, not adversary-proof" posture; still the right call, still not addressed here.
- **New social features of any kind** — explicitly excluded from this milestone's constraints.
- **A dedicated test file for every `load*.js` orchestration file** — Phase 7 covers the highest-risk gaps (auth, authorization); full parity across every load file is a larger, lower-urgency undertaking worth its own follow-up pass.
