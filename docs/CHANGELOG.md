## Unreleased — Milestone 24: Moderator Report Queue

Closes the trust-and-safety gap opened in Milestone 22: builders could submit content reports via `ReportButton.js`, but `resolve_report()` (migration `0028`) had zero callers anywhere in the codebase — moderators had no way to see or act on what had been reported. No migration needed; the existing `content_reports`/`moderation_actions` schema and `resolve_report()` RPC already supported everything this milestone required. New moderator/staff-only page, `pages/moderation.html` ("Reports"), gated client-side by the same `getProfileRoles()` pattern `renderProfile.js` already used, with RLS as the real authorization boundary underneath (`is_platform_moderator(auth.uid())`) — the page fails closed (both content and access-denied markup ship `hidden` in the raw HTML) rather than briefly rendering protected data while the role check resolves. Open reports show a human-readable target (never a raw UUID as the primary label), reason, reporter, and two resolution actions — "No violation" (maps to the existing `dismissed` status) and "Violation confirmed" (maps to the existing `reviewed` status) — each behind an explicit confirmation dialog stating exactly what will happen. Resolving a report records the decision only; it never unpublishes, removes, or otherwise acts on the reported content, and the UI says so directly. A read-only, newest-first Resolved history tab reuses the same data. Target context (build/comment/profile) is resolved via batched lookups grouped by type, not a per-row query; a target that no longer exists (deleted, unpublished, or made private) renders a clear "unavailable" state instead of crashing. Fixed two related latent bugs surfaced by giving `resolve_report()` its first real caller: `notificationFormat.js` had no case for the `report_resolved` notification type the RPC has always sent (fell through to a broken default that built a dead link), and `.badge[hidden]` had no `display: none` override (the same hidden-attribute/class-display specificity trap fixed elsewhere in this codebase), both now fixed. `resolve_report()` matches by report id alone with no guard against re-resolving an already-resolved report; mitigated client-side with a pre-resolve state check rather than a new migration, since the race is narrow (two moderators resolving the same report within seconds of each other) and the fix is UX-only (an honest "already resolved" message), not a security gap — `moderation_actions` still records every resolution attempt that succeeds.

## Unreleased — Milestone 22: Community Foundation

Discord account linking (OAuth via Supabase, `social_connections` table, connect/disconnect, visibility control, shown on Settings and the public Builder Archive); automatic role assignment (`community_builder`, `project_mentor`) plus manual `moderator`/`staff` grants via `grant_profile_role()`/`revoke_profile_role()`, surfaced with a `RoleBadge` component; content reporting (`content_reports`, `ReportButton.js`, wired into build pages and comments — the moderator-facing side of this shipped later as Milestone 24); a feedback system (`feedback` table, `FeedbackModal.js`, available from the navbar); beta invites; and a Community Guidelines page with versioned acceptance tracking (`guidelines_accepted_version`) gating comment/report submission until accepted. Schema landed across several migrations covering social connections, roles, moderation, feedback, and beta invites — all additive, no changes to existing tables' meaning. Fixed along the way: Discord manual-linking error handling, a `profiles.headline` query fanout on the Builder Archive page, and a `profile_roles` column-exposure issue restricting what's readable to role badges only.

## Unreleased — Milestone 21: First-Time Builder Experience

A Welcome dialog for new signups (two-step: intro, then technology chooser), a profile-completion checklist, and contextual hints in the editor for builders who haven't published yet — all gated by a new `profiles.onboarding_welcomed_at` timestamp (migration `0025`) so the flow shows once, not on every login. First-publish detection triggers a celebration dialog the first time a builder's first project goes live. Built on the existing native-`<dialog>` construction pattern (`confirmDialog()`/`modal.js`) rather than a new dialog primitive. Covered by tests across signed-out, existing-user, new-user, slow-network, failed-save, no-storage, keyboard-only, and reduced-motion cases.

## Unreleased — Milestone 20: Builder Portfolio

Redefined the public profile page (`profile.html`) as a Builder Portfolio: a hero composition with an editable headline and Follow button, a 4-metric overview strip, a side-by-side Featured Project section (creator-selected via a new Settings picker, migration `0024`), a Gallery using the same `BlueprintCard` component as everywhere else, a Technology Breakdown legend, and a Journey/About section. Settings gained the headline field and Featured Build picker. Fixed a `profiles.headline` query fanout found during this work and confirmed the Gallery section reuses the canonical `BlueprintCard` rather than a page-local duplicate.

## Unreleased — Milestone 19: Structured Parts Catalog

Replaced the flat, unstructured per-technology `specifications` string values with a catalog-backed shape (`{componentId, name}`) so components have stable identity instead of free text — the foundation for reliable search, compatibility, and future affiliate links. New `components` catalog table (moderator-approved entries only, via a `component_submissions` moderation queue and RPCs — not open write access, a deliberate tightening from the original proposal), `component_aliases` for alternate names matching to the same canonical entry, and inert `retailers`/`component_retail_variants`/`component_retailer_links` tables (schema only, no live retailer integration or affiliate provider — flagged explicitly as such, not an oversight). `ComponentAutocomplete.js` gained a real `onSelect` callback (previously set `dataset.componentId` but fired no event, so the editor's save path silently discarded every match). Paste-list import (`ImportSpecificationsModal.js`) parses pasted text into matched/needs-review/unrecognized buckets but never persists unconfirmed data directly — the builder always confirms through the same manual picker, so what's saved is always catalog-backed, never raw unvalidated paste text. All 6 category pages consolidated from byte-for-byte-identical hardcoded templates into one shared `data-category`-driven renderer. Existing render paths (public build page, `BlueprintCard`, Explore's filter/search/ranking) updated to read through a shared `js/utils/specifications.js` normalizer that accepts both the new structured shape and old flat-string rows — no backfill, both shapes coexist permanently. A full SQL security audit (`docs/milestones/MILESTONE_19_SQL_SECURITY_AUDIT.md`) covers RLS, `SECURITY DEFINER` grants, and race conditions across all four new migrations.

## Unreleased — Milestone 23: Setup Inventory, Search & Builder History

The final core-product milestone before closed beta. Five features, one migration (`0035`): (1) Setup Inventory — a structured, versioned `setup_inventory` jsonb column on `project_drafts`/`builds`/`build_revisions`, separate from the existing per-technology `specifications` field, letting Setup-technology builders organize products into reorderable categories (8 default names plus fully custom ones, optionally saved as private, reusable per-account templates in the new `saved_setup_categories` table) with keyboard-accessible move controls — drag-and-drop is never the only way to reorder. (2) Link-assisted product entry via a new Supabase Edge Function, `supabase/functions/product-metadata` — a deliberate, defense-in-depth SSRF-hardened metadata fetcher (scheme/port/credential checks, a DNS-resolved private/loopback/link-local/cloud-metadata IP blocklist, manual redirect revalidation, response-size and timeout caps, a retailer domain allowlist, no raw HTML ever returned) that suggests a title/retailer/listed price from a pasted URL without ever overwriting a field the builder already edited; manual entry with no URL always works, with or without the function deployed. (3) Money handled as integer cents throughout, with automatically derived (never manually editable) category and setup-wide totals that distinguish a genuine "Setup total" from a "Known total" when any product's price is unrecorded. (4) Scoped search — `all`/`build`/`creator`/`category` via `?scope=`, added to the existing shared navbar search rather than a second duplicate hero search, with "All" showing distinct Builders/Blueprints sections instead of one merged list. (5) Two new, deliberately separate Builder Portfolio facts: the existing "Joined" date (unchanged) and a new optional, creator-set "Building since {year}" stat (`profiles.building_since_year`) — while fixing a real pre-existing bug in `renderAboutBuilder.js`, which had been mislabeling the account's own join date as "Building since," duplicating what the Hero already showed. `publish_draft()`/`restore_revision_to_draft()` were rewritten in place from their true current bodies (confirmed by grepping every prior redefinition, not assumed) to copy/restore the new inventory field; no new SECURITY DEFINER function was needed anywhere in this milestone. Live-confirmed against the shared project (read-only): a pre-Milestone-23 Setup blueprint's public page correctly renders its legacy specifications with the new Setup Inventory section cleanly hidden, and a Builder Portfolio page load correctly fails with `42703 column does not exist` pre-migration — concrete evidence for why the documented deploy order (migration, then Edge Function, then website) is not optional.

## Unreleased — Milestone 18: Formal accessibility audit

An axe-core scan across every reachable public and non-auth-gated page, plus static source review of the five pages that require a signed-in session (Workshop, Upload, Settings, Notifications, the project editor — no test-account credentials exist for this environment, per the standing policy from Milestone 11B). Fixed: five instances of a translucent lavender tint composited over `--color-surface` measuring 4.05-4.25:1 instead of the required 4.5:1 (`.featured-label`, `.filter-pill.active`, `.journal-type`, all component-local rgba tints, not the shared `--color-primary-soft` token itself); three inline links (`.follow-hint a`, `.like-hint a`, `.save-hint a`) with only 1.07:1 contrast against their surrounding text and no non-color distinction, now underlined; four pages (`search.html`, `followers.html`, `following.html`, `notifications.html`) whose empty-state jumped from `<h1>` straight to an injected `<h3>` with no `<h2>` between; `404.html`'s only heading was an `<h3>`, promoted to the page's real `<h1>`; two `<aside>` elements nested inside another landmark (`explore.html`'s filter panel, `build.html`'s creator card), changed to `<div>` since neither was tag-selected by CSS/JS; a missing `prefers-reduced-motion` override on the app's only two motion rules without one. Also found and fixed, via a new static regression check (not live browser testing, since the page requires auth): `.editor-view-live-link[hidden]` had no display-none override, the same specificity trap already fixed elsewhere, silently keeping "View live project" visible before a project's first publish.

Added `tools/ci/check-a11y-regressions.js` (wired into CI): three static checks guarding against this codebase's three most-repeated regression classes — the `[hidden]`-vs-class-display specificity trap, light-fill components missing `--color-text-inverse` text, and reintroduced glow effects.

## Unreleased — Milestone 17: Minimal CI

Added a two-job GitHub Actions workflow: JS syntax validation (`node --check`) plus a regex-based broken-local-reference checker for every HTML `src`/`href`, CSS `url()`, and JS import specifier; a Playwright headless-Chromium runner driving all 24 `tests/*.test.html` files through their existing `window.__testResults` convention. No Supabase secrets needed anywhere — verified the two tests referencing the Supabase client both use the existing blob-URL module-mocking pattern, not a live network call. CI tooling lives in `tools/ci/`, with its own `package.json` kept out of the repo root so it doesn't change the site's build-step-free Cloudflare Pages deploy. `docs/CI.md` documents what's automated versus what still needs manual browser verification.

## Unreleased — Milestone 15: Workshop/Dashboard resolution

Removed the orphaned `pages/dashboard.html` (unreachable — zero inbound links, already flagged dead in this changelog's own Milestone 3 notes) after porting its one piece of functionality Workshop didn't already have — a Builds/Build Logs/Completed stats row — into `renderWorkshop.js`, using data `loadWorkshop.js` had already been fetching unused. `dashboardRepository.js` kept (shared with Workshop, not Dashboard-exclusive).

## Unreleased — Milestone 14: Brand implementation

Rolled out the approved warm-graphite + lavender palette, typography scale, spacing, radius, shadows, and logo mark — a token/asset swap only, no layout or navigation changes. WCAG AA reverification found the approved package's literal hex values failed badly in many places (unreadable text on the lightest surface tier, white text illegible on every fill, borders below the 3:1 non-text minimum); every fill color ships as approved, every surface and text color was corrected. Full before/after table and reasoning: `docs/BRAND.md`. All glow effects removed per the brand's explicit prohibition (solid focus rings replace them; the homepage's ambient gradient background is gone).

## Unreleased — Milestone 13: Database correctness

Removed `ensureProfile()`'s dead `.insert()` fallback (RLS has no INSERT policy on `profiles` at all, so it could never succeed) in favor of an honest existence check. Removed the three empty, non-authoritative `supabase/schema.sql`/`policies.sql`/`triggers.sql` placeholder files. Formalizing the live `profiles`/`auth.users` trigger into a tracked migration remains open — blocked on a manual, read-only introspection query this implementation environment has no path to run itself; tracked as a standing backlog item, not a blocking one.

## Unreleased — Milestone 12: Authentication completeness

Added the two required V1 auth flows that were fully missing: password recovery (`pages/forgotPassword.html` → email link → `pages/updatePassword.html`, using Supabase's `resetPasswordForEmail`/`PASSWORD_RECOVERY` event) and password change (Settings, re-authenticates the current password before calling `updateUser()`). The recovery-request page always shows the same message regardless of whether the email exists — no account-enumeration path. Found and fixed along the way: `.auth-form`'s `display: grid` was silently overriding the `hidden` attribute's `display: none` (same class-vs-`[hidden]` specificity trap already documented elsewhere in this codebase), never triggered before because no page had toggled that class's `hidden` state at runtime until this milestone.

## Unreleased — Milestone 11B: Confirmed database bug

Fixed `record_build_view()` (migration `0019`, new — `0010` was not edited in place): every real call had been failing with a Postgres ambiguous-column error since the feature shipped, caught client-side and only logged, never surfaced. Also closed a related information-disclosure gap found during the same investigation — a caller with no RLS-authorized visibility into a private build could still learn its view count via direct RPC call; the fixed function now returns `NULL`, not `0`, for that case.

## Unreleased — Milestone 11A: Documentation foundation reset

Consolidated `docs/` from 21 scattered, frequently self-contradictory files (7 of them empty) into a single non-contradictory set of authoritative documents — `VISION.md`, `TERMINOLOGY.md`, `SCOPE.md`, `PRODUCT_PRINCIPLES.md`, `BRAND.md`, `ARCHITECTURE.md`, `DATABASE.md`, `PRODUCT_ARCHITECTURE.md`, `ROADMAP.md` — replacing a fragmented planning history where five different documents used five different names for the same core concepts and three different color palettes were each still described as "current" somewhere. Superseded docs archived under `docs/archive/` (not deleted); milestone architecture docs moved under `docs/milestones/`.

## Unreleased — Milestone 10: Brand refresh

A complete visual design-system refresh (10 steps, each independently verified and committed): new design tokens (three-tier color model, 4px/8px spacing, one radius scale, a separated elevation/glow system), a shared stroke-icon system, every component's CSS rewritten to the new standard (buttons, cards, inputs, badges, dropdowns, navigation, toasts), a new modal component replacing every native `confirm()` call site, skeleton loading, branded empty states, consolidated responsive breakpoints, a restrained ambient-background system, and new brand assets (favicon, OG image, loading/empty-state iconography). Two follow-up refinements shipped after initial review: a palette rebalance from an indigo-leaning primary to "Deep Plum + Lavender Mist" (along with ~20 hardcoded pre-refresh color literals found still bypassing the token system), and a homepage ambient-lighting pass (later removed in Milestone 14, when the brand direction changed again).

## Unreleased — Milestone 9: Production cleanup & launch

Storage security repair (Migration A) and legacy media linkage backfill (Migration C, migration `0018`) closed real gaps found during the Milestone 8 audit; `docs/STORAGE_ARCHITECTURE.md` written as the resulting system's durable record. Phase 9C: dead-code removal, duplicate-utility consolidation, and production-asset fixes across the codebase. Phase 9D: Cloudflare Pages deployment configuration, production metadata on all real pages, a strict CSP with no `unsafe-inline`, `docs/DEPLOYMENT.md`/`docs/OPERATIONS.md`. Phase 9E: final security/functional/accessibility re-verification and a launch-readiness scorecard. Storage RLS hardening (migration `0017`) removed four `storage.objects` policies that predated migration tracking and let an anonymous session enumerate and read arbitrary upload paths.

## Unreleased — Milestone 8: Production hardening & full codebase audit

A full-repository audit (26 HTML pages, 122 JS files, 56 CSS files, 21 test files) found the codebase architecturally sound in the areas that matter most (every write path through a `SECURITY DEFINER` RPC reading `auth.uid()` internally, RLS everywhere, consistent batch-fetch patterns) but not launch-ready: two clusters of completely empty pages (5 category, 4 legal), a real privacy gap (unpublishing didn't revoke Storage-level access to already-generated image URLs), and a silently-broken test on a destructive action. Milestone 8A (migrations `0014`-`0016`) closed the storage-visibility gap, added two missing indexes, and fixed one `SECURITY DEFINER`/`INVOKER` misconfiguration found by a full audit of every custom function. Milestone 8C: eliminated duplicate `getCurrentUser()` auth round-trips firing twice on every single page load, site-wide. Milestone 8D: a 62-finding accessibility and polish pass (5 critical, 21 high, 25 medium, 11 low) across keyboard navigation, focus management, screen-reader support, color contrast, and mobile behavior.

## Unreleased — Milestones 7A–7D: View tracking, notifications, following, activity feed

`0010_build_view_tracking`: cooldown-deduped view counting (30-minute window per viewer, signed-in or anonymous), later found to have shipped broken and fixed in Milestone 11B. `0011_notifications`: private in-app notifications for comments, likes, and saves on a user's own projects. `0012_follows`: follow/unfollow builders with cached follower/following counts. `0013_activity_feed`: Following/Explore activity feeds computed live from the existing `build_revisions` log, no new table.

## Unreleased — Milestones 6A, 6D, 6E: Comments, likes, saved projects

`0007_comments`: comments on published projects. `0008_project_likes`: authenticated like/unlike on a public project. `0009_saved_builds`: authenticated users can privately save a public project to revisit later, surfaced in Workshop's Saved Projects section.

## Unreleased — Milestones 5A, 5C, 5D: Publishing, revision history, unpublish

`0002`-`0004`: transactional draft-to-build publishing via a `SECURITY DEFINER` `publish_draft()` function, plus an avatar-delivery follow-on and a column-naming correction. `0005_revision_history_and_restore`: an immutable content snapshot per revision and the ability to restore a build to an earlier one. `0006_unpublish`: `set_build_visibility()`, letting an owner take a published build back to private.

## Unreleased — draftValidation.js test matrix

### Added
- `tests/draftValidation.test.html` — a dependency-free, browser-run test suite for the shared validation module (no test runner or `package.json` exists in this project, and introducing one for a single pure-function module felt like the wrong tradeoff; a small self-contained harness matches how everything else here has been verified). Covers `isValidTitle` (empty, whitespace-only, below/at/above both length boundaries), `isValidDescription` (below/at the length boundary, whitespace trimming), and `getReadinessChecks`/`isDraftReady` across the full combination space — all four requirements missing, all four present, each one individually missing with the other three present, and a two-missing/two-present case. 32 assertions, run directly (not just written): 32/32 pass. Reopen `tests/draftValidation.test.html` in a browser anytime to re-verify.

## Unreleased — Milestone 4E: Validation & Recovery Polish

### Fixed
- **Recovery restore only ever covered Overview's three fields.** `maybeShowRecoveryBanner`'s Restore action called `overview.applyFields(buffer.fields)` exclusively — introduced in Milestone 4B, before Specifications/Resources existed. A recovered buffer containing `specifications` or `resources` would correctly *save* to the server (the whole buffer is always sent) but the Specifications/Resources tabs' visible fields and internal state never updated, and — more seriously — a subsequent edit in either tab would then overwrite the server with its own stale in-memory copy, silently discarding the just-restored data. `renderSpecificationsSection` and `renderResourcesSection` now each expose their own `applyFields` (no-op for keys they don't own), and `app.js` combines all three into one dispatcher passed to the recovery banner. Verified directly: restored title + specifications + resources all correctly appear in their respective fields, and — the actual regression case — a follow-up edit to an unrelated specification field no longer drops the just-restored ones from the next save.

### Added
- `js/services/draftValidation.js` — pure, shared readiness rules (title 3–100 chars, description ≥20 chars, technology selected, at least one gallery image), written to be the same function Milestone 5's eventual publish gate calls, not a second copy of the same logic.
- `js/pages/editor/renderReadinessChecklist.js` + `#editorReadiness` in the editor header — a live "N of 4 complete" checklist previewing what publishing will require. Purely informational; there is still no Publish button (Milestone 5). Updates on every keystroke via the existing autosave status callback (not just after a save completes) and after every Gallery mutation via a pushed media count, avoiding a duplicate fetch of media Gallery already holds in memory.

### Tests performed
No live backend (same constraint as every prior milestone). Verified directly: the recovery restore fix (above); the readiness checklist's four states transitioning correctly as fields are fixed one at a time, including the media-count-driven cover check; live update firing immediately on keystroke rather than waiting for the debounce; all editor pages loading with zero console errors and zero broken imports on a cache-cleared origin.

## Unreleased — Milestone 4D follow-up: orphaned-upload cleanup

### Fixed
- `js/pages/editor/renderGallerySection.js`: if `uploadGalleryImage` (Storage) succeeded but the following `addMedia` (database insert) failed, the uploaded file was left in Storage with no `project_media` row ever pointing back to it — a silent, permanent orphan. The upload loop now tracks whether the Storage upload completed, and on a subsequent failure calls the new `deleteGalleryImage()` to remove it before surfacing the error. If that cleanup itself fails, a distinct message says so explicitly rather than silently dropping it or showing a misleading duplicate toast.
- Same pass separated the auto-cover-assignment step (setting the first uploaded image as cover) from the upload/insert failure path — previously, if only the cover assignment failed, the user saw "could not upload image" even though the image had, in fact, uploaded and saved successfully. It now shows an accurate "uploaded, but couldn't be set as cover" warning instead, and does not delete the successfully-uploaded image.
- `js/services/imageService.js`: added `deleteGalleryImage(draftId, mediaId)`, the rollback counterpart to `uploadGalleryImage`, reusing the same path-construction logic (`galleryStoragePath`) so the two can never drift out of sync. Renamed `AVATAR_BUCKET` → `PROJECT_IMAGES_BUCKET` throughout the file, since the constant has served both avatars and gallery images since this milestone — the old name was no longer accurate.

### Tests performed
Verified all three failure paths directly against the real `renderGallerySection.js` and `imageService.js` (via the same Blob-URL dependency mocking used for 4D's original tests, not a reimplementation): (1) Storage succeeds, insert fails → `deleteGalleryImage` called with the exact same `draftId`/`mediaId` as the upload, grid stays empty, accurate error shown; (2) Storage succeeds, insert fails, cleanup *also* fails → exactly one toast, the specific double-failure message, no confusing duplicate; (3) Storage and insert both succeed, only cover-assignment fails → image is kept and shown in the grid (correctly *not* deleted), accurate distinct warning shown instead of a false "upload failed."

## Unreleased — Milestone 4D: Resources & Gallery

### Added
- `js/pages/editor/renderResourcesSection.js` — the Resources tab: a repeatable label/URL list stored in the draft's `resources` jsonb array, going through the same shared autosave/status pipeline as Overview and Specifications (same "always send the complete array" rule as specifications, for the same shallow-merge reason).
- `js/pages/editor/renderGallerySection.js` — the Gallery tab: upload zone (multiple files), thumbnail grid, per-image "Set as Cover" and "Delete" actions.
- `js/repositories/mediaRepository.js` — `getDraftMedia`, `addMedia`, `deleteMedia` (removes both the storage object and the database row — deleting only the row would leave an orphaned file forever), `getMediaPublicUrl`.
- `js/services/imageService.js`: `uploadGalleryImage` — validates, constrains to a max 2000px dimension while **preserving the original aspect ratio** (unlike the avatar pipeline's square crop — gallery lightboxes need real proportions), uploads to `projects/{draftId}/{mediaId}.jpg` in the existing `project-images` bucket, matching the path convention the Milestone 4A storage policy already expects.
- Resources and Gallery tabs enabled in `pages/build/edit.html` (both `disabled` since 4A). All four editor sections now functional.

### Changed
- Gallery is deliberately **not** part of the shared text-field autosave pipeline. Upload, delete, and cover-selection are discrete atomic actions — each either succeeds or fails immediately — not continuous typing that benefits from debouncing or a local-recovery buffer. Each gets its own toast instead of feeding the shared "Saving.../Last saved" status text.
- Uploading the first image to an empty gallery automatically sets it as the cover; later uploads don't change an existing cover. Deleting the current cover image reassigns the cover to another remaining image (or clears it if none remain).

### Tests performed
No live backend (same constraint as every prior milestone — no test account). Verified directly against the real modules: Resources — add/edit/remove correctly coalesce into single saves containing the complete array, phantom-event guard applies here too. Gallery — mocked its three dependencies (`mediaRepository`, `draftRepository`, `imageService`) via Blob-URL module rewriting so the actual shipped code could be exercised end-to-end without a real backend: initial grid renders from fetched media, "Set as Cover" correctly updates state and disables its own button, simulated file upload correctly calls the upload+insert pipeline and grows the grid, delete correctly removes an item and calls the storage+DB cleanup, first-upload-auto-cover and cover-reassignment-on-delete-of-cover both confirmed. Tab switching re-verified across all four tabs (previously two) with the real markup — exactly one panel visible at a time in every case.

## Unreleased — Component autocomplete lifecycle cleanup

### Fixed
- `js/components/ComponentAutocomplete.js` had no teardown — every call registered a document-level `click` listener with no way to remove it, so each editor technology re-render back to `pc_build` leaked another one, permanently, for the life of the page. `setupComponentAutocomplete()` now returns `{ destroy() }`, which removes the document click listener and the input's own listeners, and cancels any in-flight search request so its callback can't fire after teardown. `js/pages/editor/renderSpecificationsSection.js` now destroys the previous render's autocomplete instances before creating new ones. Verified by monkey-patching `document.addEventListener`/`removeEventListener` to count net `click`-listener growth across 5 full switch-away-and-back cycles: listener count stayed at 2 throughout (previously would have reached 12).

### Verified
- Cross-reload specification persistence: populated PC Build CPU/GPU, switched to Arduino (confirmed via a fake server object that switching category alone never touches the `specifications` column — only an explicit specification edit does), simulated a real reload with a completely fresh render context and fresh autosave controller (no reuse of in-memory state), switched back to PC Build, and confirmed the original values were exactly restored.

## Unreleased — Milestone 4C: Specifications & Technologies

### Added
- `js/pages/editor/renderSpecificationsSection.js` — the editor's Specifications tab, reusing the existing `js/config/technologies/*` field definitions and `ComponentAutocomplete.js`/`search_components` RPC (CPU/GPU lookup for PC builds) unchanged. Fields save into the draft's `specifications` jsonb through the same shared autosave controller and status indicator from Milestone 4B — no new save pipeline.
- Specifications tab enabled in `pages/build/edit.html` (was `disabled` since 4A); Resources and Gallery remain disabled.

### Changed
- Specifications re-render automatically when the technology changes in Overview (listens to the same `#fieldCategory` `change` event), regardless of which tab is active when that happens. Values entered for a technology the user switches away from are kept in memory (not displayed, not deleted) rather than discarded, so switching back restores them.

### Fixed (design correctness, not a regression)
- `specifications` is a single jsonb column, and autosave's field merge is shallow (`{...pendingFields, ...fields}`), so passing only the one changed key each time would have silently dropped previously-edited-but-unsaved fields in the same jsonb object (e.g. editing CPU then GPU before the debounce fires would have saved GPU only). The specifications renderer keeps a local copy of the full object and always sends the complete thing on every change. Verified directly: two rapid edits to different fields correctly coalesce into one save containing both.

## Unreleased — Bug fix: recovery banner showing on already-saved drafts

### Fixed
- **Actual root cause** (`css/pages/build/editor.css`): `.editor-recovery-banner { display: flex; ... }` had the same CSS specificity (a single class selector) as the browser's built-in `[hidden] { display: none; }` rule. Author styles beat user-agent styles on a specificity tie, so the banner's own class rule silently overrode the `hidden` attribute/property entirely — it was rendered every time regardless of what the JS recovery logic decided, which is why it kept reappearing after Discard/Restore even once the data-layer bug (below) was fixed and confirmed clean via a live diagnostic panel showing no buffer, `hasNewerLocalBuffer() === false`, and zero `scheduleSave` calls. Fixed with a `.editor-recovery-banner[hidden] { display: none; }` override (higher specificity, wins correctly). Also made `js/pages/editor/draftRecoveryBanner.js` explicitly set `banner.hidden = true` on the false path instead of relying solely on the HTML's default `hidden` attribute, as defense-in-depth against the same class of mistake recurring. Verified via computed-style checks: with the fix, `hidden` correctly resolves to `display: none` / zero height, and unhiding correctly resolves to `display: flex`. Diagnostic panel and its instrumentation hooks removed.
- **Fixed in an earlier pass, real but not the actual cause of what you were seeing** (`js/pages/editor/renderOverviewSection.js`): Chrome restores a `<textarea>`'s value on page reload independently of any JS, and dispatches a real `input` event when it does — with no user interaction at all. That phantom event reported the *same* value the field was just populated with from the server, but the field listener had no way to tell a real edit from a browser-triggered echo, so it scheduled a save (and wrote a local recovery buffer) every time. Diagnosed by adding temporary `[DRAFT-DEBUG]` logging with `console.trace()` on every buffer write, which showed three phantom saves firing immediately on load, all tracing back to the description field's `input` listener — before any real keystroke. Fixed by tracking the last-known value for each field and only scheduling a save when the reported value actually differs from it — this closes the bug regardless of what triggers a phantom event (browser restore, autofill, or anything else), not just this specific Chrome behavior. Also added `autocomplete="off"` to the editor's fields as a secondary mitigation. Verified by dispatching synthetic same-value `input`/`change` events after populating the form (confirmed no buffer written) and confirming genuine value changes still autosave correctly. All temporary debug logging has been removed.
- `js/pages/editor/draftRecoveryBanner.js`: separately, the Restore button called `autosave.flushNow()` without awaiting it, then immediately hid the banner. If the page was reloaded or navigated away from before that save round-trip actually finished, the local buffer was never cleared, and the banner would reappear on every subsequent load with no way out. Restore now `await`s the save, disables both buttons and shows "Restoring..." while in flight, and on failure re-enables them with a toast so the user can retry instead of the buffer silently sticking around.
- `js/services/draftAutosave.js`: the "saved" status now uses the server's actual `updated_at` (already returned by `updateDraft`) instead of guessing with the client's clock — more accurate "Last saved" display, no client/server clock-skew gap.
- `js/pages/editor/app.js`: removed the native `beforeunload` confirmation dialog (`event.preventDefault()`/`returnValue`) entirely. The recovery architecture is local-buffer-first — the network save during unload is best-effort only and recovery correctness never depended on it completing — so blocking navigation and warning the user their changes "might not be saved" was both unnecessary and slightly inaccurate once buffer-based recovery existed. A best-effort `flushNow()` is still attempted; it just no longer blocks or delays leaving the page. Re-verified buffer survival under this change with the same adversarial-timing test (save that cannot complete before reload) — unchanged, still survives.
- End-to-end recovery flow (write → reload → detect → banner → restore → autosave → no repeat banner) confirmed working in a real browser session. Diagnostic panel and all temporary instrumentation removed.

## Unreleased — Milestone 4B: Autosave, Recovery & Draft Discoverability

### Changed
- Refactored the autosave controller to be owned by `js/pages/editor/app.js` (one per draft) rather than created inside `renderOverviewSection.js` (one per section). Every current and future section now shares one save pipeline and drives the same header status indicator — nothing section-specific.
- `js/pages/editor/editorStatus.js` — extracted the status-text formatting so there's exactly one place that decides what the indicator says.

### Added
- `js/services/draftRecovery.js` — localStorage-backed safety net. Every `scheduleSave()` call mirrors pending fields to `localStorage` immediately (not debounced), so a crashed tab or closed browser between saves doesn't lose the edit. Cleared automatically once the server confirms it has the same data.
- `js/pages/editor/draftRecoveryBanner.js` — on editor load, if a local buffer is newer than the server's `updated_at`, shows a dismissible inline banner (not a modal) offering Restore or Discard.
- `js/repositories/draftRepository.js`: `getMyDrafts(userId)`.
- `js/components/DraftCard.js` — a small dedicated card for listing drafts, deliberately not routed through `BlueprintCard` (a draft isn't `builds`-shaped — no slug, no image yet, no publish status).
- Workshop: a new "Drafts" section between Continue Building and My Projects, listing in-progress drafts with a Continue Editing action. Hidden entirely (not shown as an empty state) when a user has no drafts, since it's a secondary convenience area, not primary content.
- `loadWorkshop.js`'s draft fetch is wrapped so a missing `project_drafts` table (migration not yet applied) degrades to "no drafts shown" rather than breaking the whole Workshop page.

### Tests performed (direct invocation, since there's still no live DB to test against)
Confirmed: local buffer writes happen synchronously on every field change, independent of the debounce timer; buffer clears on successful server save; recovery banner correctly appears only when the local buffer is genuinely newer than the server's `updated_at`; Restore applies buffered fields to the form and pushes them to the server; Discard clears the buffer without touching the form; `DraftCard` produces a correct edit link and category label; the Workshop drafts section shows with data and hides (not empty-states) with none.

## Unreleased — Milestone 4A: Editor Shell

### Added
- `project_drafts` and `project_media` tables proposed (not yet applied — no DB access from this environment). See migration notes in the Milestone 4A design/implementation discussion. Application code below assumes this schema exists; degrades with a clear error message until it does.
- `js/repositories/draftRepository.js` — `createDraft`, `getDraft`, `updateDraft`.
- `js/services/draftAutosave.js` — debounced (1.5s) autosave controller: coalesces rapid changes into one save, retries failed saves without dropping in-progress input, drives a status callback ("unsaved"/"saving"/"saved"/"error"). Verified with a mocked save function (debounce coalescing, failure-then-retry field preservation).
- `pages/upload.html` — replaced the old single-shot "fill everything out and publish immediately" form with a minimal "title + technology" draft-creation entry point.
- `pages/build/edit.html` + `js/pages/editor/{app,editorTabs,renderOverviewSection}.js` + `css/pages/build/{editor,overview}.css` — the project editor shell: section tab navigation (Overview live; Specifications/Resources/Gallery visibly present but disabled, not faked), a persistent "Draft" badge + "Last saved" indicator, and full autosave for the Overview fields (title, description, technology).
- No publishing controls anywhere in the editor, per your instruction — nothing to publish yet, so nothing is shown.

### Changed
- `js/pages/upload/app.js` rewritten around draft creation instead of direct-to-`builds` publishing.

### Superseded (left in place, not deleted, now unreferenced)
- `js/features/upload.js` — the old instant-publish logic. Nothing links to it anymore.
- `js/pages/edit-build/app.js` — the broken editor entry point from before this milestone. `pages/build/edit.html` now points at `js/pages/editor/app.js` instead.

## Unreleased — Milestone 3: Workspace

### Fixed
- `pages/workshop.html` referenced `js/pages/workshopPage.js`, which doesn't exist — the same class of bug found in Milestone 2 (login/settings). This is the page actually linked from the navbar and `js/config/routes.js`; it loaded zero JavaScript before this fix.

### Changed
- Removed a "Builder Stats" panel showing "Builder Level" and "XP" — gamification mechanics that conflict with the canonical spec's prohibited-features list (engagement/reward mechanics, "must not feel like a gaming launcher"). Replaced with real project data.
- Replaced dead `href="#"` quick-action links with working ones (Settings, public profile).
- Switched `.primary-btn`/`.workshop-action` to the shared `.btn` system.

### Added
- `js/pages/workshop/{app,loadWorkshop,renderWorkshop}.js` + `css/pages/workshop/workshop.css` (new — no prior CSS existed for this page).
- A "Continue Building" section surfacing the most recently updated project with its latest progress, linking into the existing continue-editing flow; empty state for first-time users.
- A "My Projects" grid using a new `variant: "workspace"` option on the shared `BlueprintCard` component (additive — existing callers unaffected), which shows a "Continue Editing" action instead of "View Blueprint".

### Notes
- `pages/dashboard.html` is a working but unlinked duplicate of this page (not in `js/config/routes.js`, not referenced by the navbar). Left as-is per "don't delete unless actively causing problems" — flagged for a future consolidation decision, not touched.

## Unreleased — post-Milestone-2 clarification

### Changed
- `js/services/imageService.js` now exports a single `uploadAvatar(userId, file)` covering the full pipeline (validate → resize → upload all variants → return canonical URL). The storage-upload loop that previously lived inline in `settings/app.js` moved into the service; `buildAvatarVariants` and the storage path helper are no longer exported, so nothing outside this file can touch canvas or `supabase.storage` for avatars. `settings/app.js` now only calls `uploadAvatar()` + `profileRepository.updateAvatarUrl()`.

## Unreleased — Milestone 2: Authentication & Profiles

### Fixed
- `pages/login.html` and `pages/settings.html` referenced `js/pages/loginPage.js` / `js/pages/settingsPage.js`, neither of which exists — both pages loaded zero JavaScript (no navbar, no form handling, no auth) in the real browser. Corrected to point at the actual page scripts.
- `login/app.js` called `showToast(...)` without importing it (would have thrown at runtime), and had a login-error handler that evaluated `(error.message)` without displaying or logging it, silently swallowing failed sign-ins.

### Added
- `pages/signup.html` + `js/pages/signup/app.js` — dedicated signup flow, split out of the login page's bolted-on signup button.
- `js/core/auth.js`-style profile bootstrapping: `profileRepository.ensureProfile()` creates a `profiles` row for a new user if one doesn't already exist (insert-only, never overwrites), called after signup (when a session exists immediately) and defensively after every login (covers email-confirmation delaying session creation until after signup completes).
- `js/services/imageService.js` — client-side avatar processing (crop-to-square, resize to 500/200/64/32px, JPEG encode) using the Canvas API, no new dependency.
- Avatar upload in Settings, storing variants under `avatars/{userId}/{size}.jpg` in the existing `project-images` storage bucket.
- `profileRepository.getPublicProfile()` — explicit-column read for the public profile page, replacing `select("*")`.

### Database
- Proposed (not yet applied — no DB access from this environment): `profiles.avatar_url text`, nullable, additive. See migration notes below.

## Unreleased — Milestone 1: Foundation

### Fixed
- Corrected three broken `@import` paths in `css/styles.css` that silently failed to load empty-state, upload-zone, and blueprint-card styles on live pages (upload, continue, design-system reference)
- Removed six dead `@import` statements in `css/pages/home/home.css` pointing to files that were never created (their intended styles already live inline in the same file, or in `css/components/spotlight.css`), eliminating 404s on every home page load
- Toast notifications no longer insert their message into the DOM unescaped

### Changed
- Replaced emoji status icons in the shared toast component with inline line-icons, and added per-type color coding (success/error/warning/info) so status is no longer conveyed by icon alone
- Moved `.btn-danger` out of the page-scoped design-system stylesheet and into the shared `button.css`, matching every other button variant
- Added an accessible mobile navigation toggle (hamburger menu) to the shared navbar for viewports at or below 900px
- Added `aria-expanded`, outside-click, and Escape-key handling to the account dropdown menu
- Centralized authentication checks into `js/core/auth.js` (`getCurrentUser`, `requireAuth`); replaced five duplicated inline `supabase.auth.getUser()` + redirect blocks (navbar, settings, dashboard, continue, publish) with calls to the shared helper, with no change in per-page redirect behavior

### Added
- `--color-danger-hover` / `--danger-hover` design tokens, completing the hover-state set alongside `--color-primary-hover`

## v0.8.2

### Added
- Build Journey page
- Creator card
- Hardware Blueprint section

### Changed
- Redesigned build hero
- Improved build routing

### Fixed
- Unknown Creator lookup
- Featured build links