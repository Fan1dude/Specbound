# Milestone 27B — Legal Readiness Specification

Status: PR1 (this document) — inventory and decision-framing only. No legal document has been drafted, edited, or published as part of this PR. Public signup remains held in its existing invite-gated posture (see §2). No production setting, database, or data was changed to produce this document.

---

## 1. Purpose and non-legal-advice disclaimer

This document exists to give an adult owner — and, where the adult owner decides it's warranted, a licensed attorney — an accurate, source-cited picture of what Specbound's codebase and infrastructure actually do today, so that real legal documents (Terms of Service, Privacy Policy, Cookie disclosure, age policy, copyright/DMCA process) can eventually be drafted on fact rather than assumption.

**This document is not legal advice.** It does not state which laws apply to Specbound, does not draft or propose legal text, and does not reach a conclusion about compliance with any law or regulation. Every "official source" cited in §17 is linked so an adult owner or attorney can read the primary material directly — this document paraphrases those sources only to frame questions for review, never as a substitute for reading them or for professional legal judgment.

The author of this document is not a lawyer and is not authorized to make legal determinations on Specbound's behalf. Every decision that requires legal, business, or parental/guardian judgment is deferred explicitly to the companion document, `docs/milestones/MILESTONE_27B_ADULT_OWNER_DECISION_PACKET.md`, and is not answered here.

**A note on how this document was produced**: every factual claim about the codebase below was traced to a specific file, migration, RLS policy, RPC, or configuration value by direct reading of the current repository (branch `27b-legal-readiness-spec`, based on `origin/main` at merge commit `fdce9d2c275498f68306be707d61dc888d6e458d`) — not inferred from older milestone specifications, which can and do go stale (see §3's note on `supabase/migrations.md`'s per-entry status labels, a concrete example of exactly this kind of staleness found during this audit).

---

## 2. Current launch posture

- **Milestone 27A PR5** (accessibility/performance/skip-link fixes) is merged to `main` and deployed to production as of merge commit `fdce9d2c275498f68306be707d61dc888d6e458d`. PR #27 is closed and merged.
- **27A as a whole is not complete.** 27A PR1 (public-signup posture) remains explicitly blocked pending this milestone (27B) — see `docs/ROADMAP.md`'s 27A row prior to this PR's update.
- **Public signup is not hard-blocked at the database or network level.** It is gated by a single client-side boolean, `BETA_INVITE_REQUIRED = true`, in `js/pages/signup/app.js:15`, which the file's own comment (lines 10-15) describes as "the one gate closed-beta signup needs, kept as a single local flag rather than a schema-level requirement... turning this off for public launch is a one-line code change, not a migration." Anyone holding a valid, unexpired, not-fully-redeemed invite code can create a real account today, on production, right now — `pages/signup.html:85-92` tells visitors "an invite code from a builder or Discord is required to sign up right now," meaning invite codes are already in the hands of people outside the development team. This is the accurate current posture — not "signup is closed," but "signup is invite-gated, with no code-level barrier stronger than that gate."
- **No age-verification mechanism of any kind exists anywhere in the product.** `pages/signup.html` collects only username, email, password, and (conditionally) an invite code — no birthdate field, no age checkbox, no minimum-age attestation. A full-repository search for age-gate/birthdate/COPPA/minor-related terms in application code (as opposed to documentation) returned no hits. This is a verified fact, not an assumption, and is the central input to §7.
- **No legal document has been published.** `pages/legal/privacy.html`, `pages/legal/terms.html`, and `pages/legal/affiliate-disclosure.html` are all explicit "Coming Soon" placeholders (verified by reading each file directly — see §6). `pages/legal/community-guidelines.html` is a real, finalized, versioned community-conduct policy — but it is not a Privacy Policy, Terms of Service, or any other formal legal document, and does not claim to be one.
- The product's owner is a minor. `docs/OPERATIONS.md` already states this directly (line 5: "Specbound's owner is a minor. Legal publication, age-policy decisions, external-account ownership, production moderator bootstrap, and handling of account-deletion requests all require an adult owner/guardian's direct action or explicit authorization"). This document does not change that; every decision requiring legal or business judgment is routed to the companion decision packet.

---

## 3. Verified product/data-flow inventory

Everything in this section was traced to a specific file, migration, or config value in the current repository. Two important accuracy notes surfaced during this audit:

**`supabase/migrations.md` per-entry status labels are stale for migrations `0007`–`0032`.** Each of those migrations' own "Status" line reads "Proposed — not yet applied" — but this is contradicted by (a) `docs/ROADMAP.md`'s own claims that Milestones 22 through 26, which functionally require those tables (comments, likes, follows, notifications, content_reports, feedback_submissions, beta_invites, social_connections, profile_roles) to exist, are "Complete — merged to main" or "merged and deployed to production," and (b) migration `0033_restrict_function_execute_permissions.sql`'s own status line, which reads "Applied to production" and which by its own function-privilege-restriction purpose could only run after the functions defined in `0007`–`0032` already existed. The most defensible reading is that migrations `0000` through at least `0041` are functionally live in production, and the individual "Proposed" labels on `0007`–`0032` are a documentation-maintenance gap (the per-entry status line was never updated after those migrations actually shipped), not a literal current state. **This was not independently re-confirmed via live database introspection** — no linked Supabase CLI/database access was available in this environment (see the preflight note in this PR's final report). An adult owner with real database access should treat this as worth a one-time confirming query, not as a blocking uncertainty.

**Signup/auth flow** (`js/pages/signup/app.js`, `js/pages/login/app.js`, `js/core/auth.js`, `js/pages/forgotPassword/app.js`): plain Supabase Auth email/password (`supabase.auth.signUp`, `signInWithPassword`, `resetPasswordForEmail`). Email confirmation is required before a session exists (signup/app.js:73-88). No third-party login provider is offered for authentication itself — Discord is a post-signup *account-linking* feature only (§3's Discord entry below), never a signup/login method. `requireAuth()` (`js/core/auth.js:27-36`) is the single gate used by every authenticated page; it calls `supabase.auth.getUser()` (a server-revalidated check, not just a cached local token) and redirects to `login.html` if there's no user.

**Beta invites** (`beta_invites` table, `redeem_beta_invite()` RPC, migration `0030_beta_invites.sql`): a code is redeemed at first login (not at signup, since signup usually has no session yet — `js/pages/login/app.js:44-61`). The table has zero RLS policies of any kind, including SELECT — a code's validity is checked exclusively through the RPC, never by a client listing codes. Codes are minted manually outside the app (no INSERT policy). `used_by` records the redeeming user's real auth id.

**Profiles** (`profiles` table): public-by-default. RLS is `for select using (true)` — every column on every row is readable by anyone, including anonymous requests directly against the Supabase REST API (not just through the app's own UI) (migration `0000_baseline_pre_tracked_tables.sql:160-167`, confirmed never modified by any later migration). Columns: `username`, `display_name`, `bio`, `location`, `website`, `github`, `youtube`, `avatar_url`/`avatar_path`, `headline`, `featured_build_id`, `building_since_year`, follower/following counts, plus internal-only `onboarding_welcomed_at` and `guidelines_accepted_at`/`guidelines_accepted_version`. **No email column exists on `profiles`** — but the production `handle_new_user()` trigger (migration `0040_harden_handle_new_user_search_path.sql:78-91`) falls back to the local part of a user's email address (the text before `@`) as their public `username`/`display_name` if they don't supply one at signup — meaning some users' real email-derived text may already be their public, queryable display name. This is a verified, current, production behavior, not a hypothetical.

**Builds and their content** (`builds`, `project_drafts`, `build_revisions`, `project_media`, `revision_media`): drafts are always private (owner-only RLS on `project_drafts`). Published builds carry an explicit `visibility` column (`public`/`private`); public builds and their revisions/specifications/media are readable by anyone via RLS, private ones only by their owner. All writes to `builds`/`build_revisions` go through the `publish_draft()` `SECURITY DEFINER` function — there is no direct client INSERT/UPDATE path to these tables.

**Comments, likes, follows, saves**: `comments` are soft-deleted (`deleted_at`, never physically removed by the app) and publicly readable when their parent build is public. `likes` and `saved_builds` are visible only to the user who performed the action (nobody, including a build's own owner, can see who liked or saved it — migrations `0008`/`0009`). `follows` is a deliberate, explicit exception — fully publicly readable (migration `0012_follows.sql:73-74`, "Private accounts are explicitly out of scope").

**Notifications** (`notifications` table): stores no message text — only `type` plus foreign-key references to the acting user/build/comment, rendered live at read time by joining to current data (migration `0011_notifications.sql:17-22`). Visible only to the recipient. As of migration `0039_feedback_status_workflow.sql`, `actor_id` is nullable specifically so a feedback-status-change notification can be sent with the reviewing moderator's identity genuinely absent from the row — not merely hidden by the UI, but actually not present in the data the client can query (`0039:41-59`, quoted directly in that migration's own header).

**Moderation, reporting, and feedback**: `content_reports` (who filed it, what/who it targets, a moderator's resolution) is visible to the reporter and to moderators only; no retention/purge logic exists. `moderation_actions` is an append-only audit log, moderator-visible only, written exclusively by `SECURITY DEFINER` functions, with no client write path and (per migration `0041`'s own reasoning) treated as something that should never be destroyed once a record exists. `feedback_submissions` is explicitly designed to *survive* account deletion — `user_id` is nullable with `on delete set null`, not cascade, specifically because "feedback is product signal that should outlive the account that submitted it" (migration `0029_feedback_submissions.sql:15-19`).

**Community roles** (`profile_roles`): four roles (`community_builder`, `project_mentor`, `moderator`, `staff`), granted only via a `SECURITY DEFINER` RPC gated by an existing moderator/staff, never self-granted. An earlier version of this table's RLS was publicly readable on every column, including a moderator's internal notes on why a role was granted — this was found and fixed in migration `0032_restrict_profile_roles_visibility.sql`, which is itself a useful, concrete example of the kind of data-exposure gap this legal-readiness review is meant to surface systematically rather than by accident.

**Discord identity linking** (`social_connections` table, migration `0026_social_connections.sql`): stores Discord numeric user id, display username, and avatar URL — **no OAuth token of any kind**. OAuth itself is handled entirely by Supabase Auth's built-in `linkIdentity()` API; there is no Discord-specific server or edge function in this repository, and the migration's own header states plainly that "this application ever storing an OAuth token" was a deliberate thing to avoid (`0026:9-17`). A user-controlled `is_public` toggle (default `false`) independently governs whether the connection is shown on their public profile at all — connecting the account does not automatically make it visible.

**Account deletion: no self-service flow, no automated procedure exists.** This is the single most important fact in this inventory for privacy-policy drafting. `docs/OPERATIONS.md` §10 is an extremely detailed, staff-run, adult-operator-gated manual procedure — but it has "never been executed against production" (§10, opening disclaimer) and requires separate adult-owner authorization for every individual case. There is no `delete_account()` RPC, no self-service "Delete my account" button, and no automated anonymization routine anywhere in the codebase. The manual procedure's own documented per-table behavior (verified directly against production schema via read-only introspection on 2026-08-15, per `docs/OPERATIONS.md:113`) is:

| Behavior | Tables |
|---|---|
| Hard-deleted | `builds`, `profiles` (manual, explicit `DELETE` — no FK enforces this) |
| Cascade-deleted (via Supabase Auth's own `deleteUser()` call) | `project_drafts`→`project_media`, `comments`, `likes`, `saved_builds`, `follows` (both directions), `social_connections`, `profile_roles`, `content_reports.reporter_id` (reports *filed by* the user), `catalog_moderators`, `component_submissions.submitted_by`, `saved_setup_categories`, `notifications` (both directions), `moderation_actions.actor_id` |
| Cleared but row survives (`SET NULL`, anonymized) | `content_reports.reviewed_by`, `feedback_submissions.user_id`, `beta_invites.created_by`/`used_by`, `components.created_by`, `catalog_moderators.granted_by`, `component_submissions.moderator_id`, `profile_roles.granted_by`, `build_revisions.user_id` |
| Manual, separate, irreversible step | Storage objects (avatar, project/revision images) — not transactional with the database delete; must be removed in a distinct step using paths captured beforehand |

Two things worth flagging explicitly for legal review: (1) `moderation_actions.actor_id` cascading means the audit trail of actions a departing user *authored as a moderator* is destroyed along with their account — `docs/OPERATIONS.md` treats this as a mandatory abort/escalation condition requiring explicit adult-owner acknowledgment, not something silently allowed to happen; (2) the current *approved decision* (per `docs/OPERATIONS.md:111`) is to hard-delete a departing user's published builds along with their account, not soft-delete or anonymize them — this is a real product decision already made, not an open question, but it is exactly the kind of fact a Privacy Policy needs to state accurately.

**Storage** (`js/services/imageService.js`, `js/repositories/mediaRepository.js`, `docs/STORAGE_ARCHITECTURE.md`): one bucket, `project-images`, private (not public) since migration `0017_storage_rls_hardening.sql`. Avatars live at `avatars/{userId}/{size}.jpg`; gallery images at `projects/{draftId}/{mediaId}.jpg`. All reads go through signed URLs with a 7-day expiry. A documented, disclosed, unfixed limitation: if a build's visibility flips from public to private after a signed URL was already issued, that specific URL remains fetchable until it naturally expires (up to 7 days) — new URLs cannot be generated for the now-private content, but an already-issued one isn't retroactively revoked (`docs/STORAGE_ARCHITECTURE.md` §6). A small number of orphaned legacy Storage objects (pre-dating the current bucket-privacy model) exist with no owning database row and no cleanup code targeting them; they are unreadable to any user (RLS returns "not found") and rendered as a placeholder client-side (`docs/STORAGE_ARCHITECTURE.md` §9).

**Client-side storage** (full grep of `js/` for `localStorage`, `sessionStorage`, `document.cookie`): **no cookies are used anywhere in the codebase.** Four `localStorage`/`sessionStorage` keys exist, none of which store personal data:
- `specbound:anon-viewer-id` (`js/core/anonViewerId.js`) — a random `crypto.randomUUID()`, generated client-side, used only as an opaque key so the same anonymous browser doesn't inflate a build's view count on repeated visits. The file's own comment states it is "never treated as a real identity, never sent anywhere else." Persists indefinitely until the browser's storage is cleared; not tied to any account.
- `specbound:draft:{draftId}` (`js/services/draftRecovery.js`) — a local autosave safety-net of in-progress, unsaved draft edits, cleared once the server confirms the same content.
- `specbound:onboarding:v1:*` (`js/utils/onboardingLocalState.js`) — dismiss flags for onboarding UI, one persistent (localStorage), one session-only (sessionStorage).
- Supabase's own Auth session token — the app does not override Supabase JS's default session-persistence behavior (`js/core/supabase.js` passes no `auth` options), so the SDK's documented default applies: `localStorage`, not a cookie.

**Public vs. authenticated page exposure** — this is CI-enforced, not just documented, by `tools/ci/check-crawl-policy.js`, which fails the build if any page's script graph reaches `requireAuth()` without being explicitly classified. Gated (redirect-on-load, `noindex`, `robots.txt`-disallowed): Workshop, Feedback queue, My Feedback, Moderation queue, Notifications, Settings, the build editor. Action-gated-but-publicly-viewable: the upload/create-project page (viewable signed out, gated only at form submission). Public and crawlable: Home, Explore, Search, public profiles, Followers/Following lists, public build pages, category pages, and all four `pages/legal/*.html` pages.

**Cloudflare edge behavior not controlled by this repository**: Cloudflare Pages injects its own Web Analytics beacon (`static.cloudflareinsights.com/beacon.min.js`) into every served HTML response — this script does not exist in any repository-tracked HTML file; it is added at Cloudflare's edge, and the repo's `_headers` CSP simply permits it to load (confirmed by grep: zero matches for `beacon.min.js`/`cloudflareinsights` in any tracked HTML file). Similarly, Cloudflare's Bot Management/challenge-platform script (recognizable by the `__CF$cv$params` snippet, observed directly on the live custom domain during this PR's own production-release verification) does not appear anywhere in this repository — confirmed by the same grep returning zero matches. Both are Cloudflare account/zone-level features, not something this codebase enables, configures, or can disable from within the repo. **See §11 for what this Bot Management system means specifically for cookie disclosure** — it is not purely a script-injection matter; Cloudflare's own documentation confirms it can set a real cookie on a challenged visitor.

**Third parties that receive data**, with what flows to each:

| Third party | What flows |
|---|---|
| Supabase (`xpxjqyraizntbtijzoyp.supabase.co` — this is the project's public API endpoint, not a secret; it already appears in the production CSP header served to every visitor) | All application data: auth, database, storage. The primary data processor. |
| Cloudflare | Hosts and serves the site (Cloudflare Pages); edge-injects Web Analytics and Bot Management scripts (see above) independent of app code. |
| `cdn.jsdelivr.net` | Serves the Supabase JS SDK library file to the browser — sees the requesting IP/user agent for that one file fetch, standard CDN behavior. |
| Google Fonts (`fonts.googleapis.com`/`fonts.gstatic.com`) | Fonts are **not self-hosted** — every page's `<head>` loads Inter directly from Google's servers at page-load time; Google's standard font-serving behavior applies (Google sees the requesting IP/UA for the font request). |
| Discord | Only via a plain outbound `<a href="https://discord.com/users/...">` link on a public profile, when a builder has opted their connection to be publicly visible — no automatic request from Specbound's own code to Discord's servers. |
| Retailer domains (Amazon, Best Buy, Target, Walmart, Newegg, IKEA, Wayfair, Home Depot, Staples, Office Depot, B&H, Micro Center) | A Supabase Edge Function (`product-metadata`) fetches a user-supplied retailer product URL server-side to scrape display metadata for the Setup Inventory feature; the retailer sees the edge function's own server IP, not the visitor's. |

**Payments, advertising, data sales, automated decision-making**: a repository-wide search (patterns: `stripe|paypal|payment|checkout`, `advertis|tracking pixel|data broker`, `\bsell(s|ing)?\b`, and a further search for common third-party analytics/tracking SDK names — Google Analytics, Sentry, Mixpanel, Segment, Amplitude, Hotjar, FullStory, PostHog) returned no matches in application code. **Not found, verified by search, not merely assumed.** There is no payment/checkout feature, no advertising code, and no profiling, personalized-advertising, eligibility-decision, recommendation-engine, or comparable automated business-decision logic anywhere in Specbound's own application code. Separately — and outside this application's own code — Cloudflare's own bot-detection system assigns each incoming request a score and, per Cloudflare's documentation, can use that score to automatically challenge or restrict traffic (see §11). This is a vendor network-security process operating at the edge, not a business decision Specbound makes about any individual user, and this document does not characterize it as regulated "automated decision-making" in a legal sense — whether it should be treated or disclosed as such is a question for the adult owner and counsel, not a conclusion reached here. An "Affiliate Disclosure" page exists as a placeholder, and a retailer-link database schema exists specifically marked "schema-only groundwork... no affiliate tag, no real retailer data" (migration `0023_retailers_and_retail_variants.sql:7-11,40`) — affiliate monetization is not implemented, only reserved schema space for a possible future feature.

**Email delivery**: no custom email-sending code exists anywhere in the repository (searched for `sendEmail|smtp|resend|sendgrid|postmark|nodemailer|mailgun` — no hits in code). Transactional email (signup confirmation, password reset) is handled by Supabase Auth's built-in email service. Whether a custom SMTP provider has been configured in the Supabase project dashboard (as opposed to in this repository) **cannot be determined from the codebase** — this is explicitly flagged as an open/unverified item in `docs/DEPLOYMENT.md:205` and `docs/OPERATIONS.md` themselves, not a new gap found by this audit.

**Geographic targeting**: none. Searched for geo/country/region-lock/IP-restriction logic across the app, `_headers`, and `supabase/` — no country or region-based access restriction of any kind exists. The only "geolocation" reference in the entire codebase is the CSP's `Permissions-Policy: geolocation=(), microphone=(), camera=()`, which *blocks* the browser's device-location API entirely (a privacy restriction, not a geographic access control).

---

## 4. Data-category matrix

| Data / category | Source | Purpose | Public visibility | Storage / processor | Current deletion/retention behavior | Unresolved decision | Source reference |
|---|---|---|---|---|---|---|---|
| Account credentials (email, password hash) | Signup form | Authentication | Not public | Supabase Auth (`auth.users`), processor: Supabase | Cascade-deleted on Auth admin `deleteUser()` call (manual procedure only) | Retention period for an inactive/never-verified account | `js/pages/signup/app.js`; `docs/OPERATIONS.md` §10.7 |
| Username / display name (may be email-derived) | User input, or auto-derived from email local-part if not supplied | Public identity | **Fully public** (`profiles` RLS `using (true)`) | `public.profiles.username`/`display_name` | Hard-deleted with the profile row (manual procedure) | Whether email-derived usernames need a distinct disclosure | `supabase/migrations/0000...sql:160-167`; `0040_harden_handle_new_user_search_path.sql:78-91` |
| Bio, location, website, GitHub/YouTube handles, headline | Settings form, user-supplied | Public profile display | Fully public | `public.profiles` | Hard-deleted with profile | Whether "location" free-text needs a minimum-disclosure warning (user could enter a real address) | `0024_profile_headline_and_featured_build.sql` |
| Avatar image | Upload | Public profile display | Fully public (avatar bucket path is publicly readable) | Supabase Storage, `project-images` bucket, `avatars/{userId}/*` | Deleted with associated DB cleanup; legacy orphans may persist unreferenced | Orphaned legacy avatar handling process | `js/services/imageService.js`; `docs/STORAGE_ARCHITECTURE.md` §9 |
| Published build content (title, description, specifications, images) | Editor → publish | Public sharing / portfolio | Public if `visibility = 'public'`, else owner-only | `public.builds`/`build_revisions`/`revision_media`; Storage | Hard-deleted (current approved decision, not soft-delete) with the account, per manual procedure | Whether a departing user can request build removal without full account deletion | `docs/OPERATIONS.md` §10, blast-radius table |
| Draft (unpublished) build content | Editor, autosave | Personal drafting | Private, owner-only | `public.project_drafts`/`project_media` | Cascade-deleted automatically on Auth deletion | None identified | `0001_project_drafts_and_media.sql` |
| Comments | Comment form | Public discussion | Public (when parent build is public) | `public.comments` | Soft-deleted by user/owner action (`deleted_at`); hard-deleted only via full account deletion | Whether soft-deleted comment text is ever purged, or retained indefinitely | `0007_comments.sql` |
| Likes | Like action | Engagement signal, aggregate count shown | **Private** — visible only to the liker, never to others or the build owner | `public.likes` | Cascade-deleted with account | None identified | `0008_project_likes.sql` |
| Saved (bookmarked) builds | Save action | Personal bookmarking | Private, owner-only | `public.saved_builds` | Cascade-deleted with account | None identified | `0009_saved_builds.sql` |
| Follows | Follow action | Social graph | **Fully public**, both directions | `public.follows` | Cascade-deleted (both directions) with account | Whether public-by-default following should be disclosed prominently | `0012_follows.sql:73-74` |
| Notifications | System-generated on others' actions | In-app alerts | Private, recipient-only; contains no stored message text, only foreign-key references resolved live | `public.notifications` | Cascade-deleted (both as recipient and as the triggering actor) with account | None identified | `0011_notifications.sql`; `0039_feedback_status_workflow.sql` |
| Content reports (filed) | Report button | Moderation | Reporter + moderators only | `public.content_reports` | Cascade-deleted (reports the user filed are deleted, not retained) with account; no TTL otherwise | Retention period for open/unresolved reports generally | `0028_moderation.sql` |
| Content reports (reviewed, as moderator) | Moderator action | Moderation record | Moderators only | `public.content_reports.reviewed_by` | `SET NULL` (anonymized) on account deletion — record survives, attribution removed | None identified | `docs/OPERATIONS.md` §10.3 blast-radius table |
| Moderation action audit log | Automated, on moderator/staff actions | Accountability/audit trail | Moderators/staff only | `public.moderation_actions` | **Cascade-deleted** with the acting moderator's account — audit history can be destroyed; flagged as a mandatory abort/escalation condition in the manual deletion procedure | Whether audit-trail preservation should override account-deletion cascade | `0028_moderation.sql`; `0041_add_account_deleted_action_type.sql` |
| Feedback submissions | Feedback form | Product improvement signal | Submitter + moderators only | `public.feedback_submissions` | **Survives account deletion** — `user_id` set to null, row retained indefinitely by design | Maximum retention period, if any, for anonymized feedback | `0029_feedback_submissions.sql:15-19` |
| Community role grants | Moderator/staff action | Access control, public role badges | `role` value only is public (via a dedicated function); full row (including internal grant notes) restricted to the holder + moderators | `public.profile_roles` | Cascade-deleted with account | None identified | `0027_profile_roles.sql`; `0032_restrict_profile_roles_visibility.sql` |
| Beta invite codes | Manually minted | Closed-beta access control | Not publicly listable | `public.beta_invites` | `created_by`/`used_by` set to null on account deletion; code row itself persists | None identified | `0030_beta_invites.sql` |
| Discord identity (numeric id, username, avatar URL) | Discord OAuth via Supabase `linkIdentity()` | Optional public "Connected Accounts" display | Owner-only by default; public only if the user opts in (`is_public` toggle) | `public.social_connections` | Cascade-deleted with account; user can also disconnect independently at any time | None identified — no token is stored, which resolves the most sensitive version of this question already | `0026_social_connections.sql` |
| Anonymous view-count identifier | Client-generated UUID | Prevent view-count inflation from repeat visits | Not exposed to other users; not tied to any account | Browser `localStorage` only, never sent to any third party beyond Specbound's own backend as an opaque key | Persists until the browser's local storage is cleared by the visitor; no server-side record of the identifier itself beyond a per-build cooldown timestamp | Whether this needs disclosure as a "necessary" local-storage use in a cookie/local-storage notice | `js/core/anonViewerId.js` |
| Supabase Auth session token | Supabase JS SDK, default behavior | Keep the user signed in | N/A — access-control artifact, not displayed | Browser `localStorage` (SDK default; not explicitly configured by this app) | Cleared on sign-out; otherwise persists per Supabase's own default session lifetime | None identified | `js/core/supabase.js` |
| Parts-catalog entries (canonical component name, manufacturer, technology/field) | Created directly by a catalog moderator, or auto-created from an approved user submission | Shared reference data powering component autocomplete/matching across all users' builds | **Fully public** (`components` RLS `for select using (true)`) | `public.components` | `created_by` set to null on that creator's account deletion; the catalog row itself is retained indefinitely (shared reference data, not personal content) | Whether `created_by` attribution needs disclosure, even though the catalog entry's own content (a part name/manufacturer) is not personal data | `0020_components_catalog.sql:156-178,303-305` |
| Catalog-moderator role membership | Manually granted (no self-grant path; a manual operation, per the migration's own comment) | Access control — gates who may create canonical catalog entries or approve/reject submissions | **Not readable by any client role at all** — RLS enabled with zero policies of any kind; only queryable indirectly via `is_catalog_moderator()`, which returns a boolean, never the row | `public.catalog_moderators` | `user_id` cascade-deleted with account; `granted_by` set to null on the granting moderator's own account deletion | None identified — already the most restrictive access pattern in the schema | `0020_components_catalog.sql:110-122` |
| Parts-catalog submissions (proposed new component or alias) | Submitted by any authenticated user via the editor's "no match found" flow; capped at 20 pending per account | Propose a new canonical catalog entry or an alternate name for moderator review | Submitter's own submissions plus catalog moderators only — never public | `public.component_submissions` | `submitted_by` **cascade-deleted** with the submitter's account (the submission itself is removed, not retained) — a materially different retention posture from `feedback_submissions`, which is deliberately anonymized and kept; `moderator_id` set to null on the reviewing moderator's own account deletion, leaving an already-resolved submission's decision on record with reviewer attribution stripped; a submitter may self-delete their own still-pending submission at any time via RLS | Whether cascade-deleting a user's resolved catalog submissions on account deletion (as opposed to anonymizing and retaining them, the pattern already used for feedback) is the intended, deliberate retention posture, or an inconsistency worth reconciling | `0022_component_submissions.sql:82-166` |
| Saved (private) Setup-category templates | User-created in the build editor, Setup-technology builds only | Personal, reusable category-name templates for organizing a Setup build's inventory | **Private, owner-only** — explicitly no public/select-all policy on any operation | `public.saved_setup_categories` | Cascade-deleted with account; no TTL otherwise | None identified | `0035_setup_inventory_and_builder_dates.sql:82-138` |

---

## 5. Third-party processor/integration inventory

See §3's third-party table for the full technical list. Summarized for policy-drafting purposes:

- **Supabase** (database, authentication, file storage) — the primary data processor. Official DPA: https://supabase.com/legal/dpa. Official Privacy Policy: https://supabase.com/privacy.
- **Cloudflare** (hosting/CDN, edge security headers, Web Analytics, Bot Management) — infrastructure processor; also independently injects its own analytics/bot-detection scripts at the edge, outside this repository's control. Official DPA: https://www.cloudflare.com/cloudflare-customer-dpa/.
- **Discord** — only via Supabase Auth's identity-linking; Specbound never directly receives a token from Discord, but Discord is still a data source for the display fields it hands to Supabase during that OAuth flow. Official Privacy Policy: https://discord.com/privacy.
- **Google Fonts** — font files loaded directly from Google's servers, not self-hosted; no account/API relationship, but still a third-party request made by every visitor's browser.
- **jsdelivr (cdn.jsdelivr.net)** — serves the Supabase JS SDK library file.
- **A defined allowlist of retailer domains** — contacted only by a server-side edge function, only when a user supplies that retailer's product URL, for Setup Inventory metadata scraping.

No other processor, sub-processor, or integration exists in the current product. Whether formal Data Processing Agreements need to be executed (as opposed to relying on each vendor's standard/click-through terms) is a decision for the adult owner and, if engaged, counsel — see the decision packet.

---

## 6. Existing legal-page gap analysis

| Page | Route | Current status (verified by reading the file directly) | Linked from footer? |
|---|---|---|---|
| Privacy Policy | `pages/legal/privacy.html` | Placeholder — title "Privacy Policy — Coming Soon", body states "Specbound does not yet have a published Privacy Policy — nothing on this page should be treated as one." | Yes (`js/core/layout.js:304`) |
| Terms of Service | `pages/legal/terms.html` | Placeholder — same pattern, "does not yet have published Terms of Service." | Yes (`js/core/layout.js:305`) |
| Community Guidelines | `pages/legal/community-guidelines.html` | **Not a placeholder.** Finalized, versioned community-conduct policy, last updated 2026-08-11, gated by an acceptance flow (`js/components/GuidelinesGate.js`, migration `0034`) before a builder's first publish or first comment. This is a real, live content-policy document — but it is a conduct code, not a Privacy Policy, Terms of Service, Cookie Policy, or Copyright/DMCA policy, and never claims to be one. It already contains legally-relevant language worth noting for review: it describes Specbound as intended for "a general audience that includes teenagers" (§04, Content boundaries) and states there is currently no formal appeals process for enforcement decisions (§10). | Yes (`js/core/layout.js:306`) |
| Affiliate Disclosure | `pages/legal/affiliate-disclosure.html` | Placeholder — same "Coming Soon" pattern. Not currently linked from the footer or any other page; reachable only via direct URL and listed in `sitemap.xml`. | No |
| Cookie Policy | *(does not exist as a distinct page)* | Not built yet. Specbound's own application code sets no cookie (§3, §11), but Cloudflare's edge — outside this repository's control — independently runs a cookieless Web Analytics feature and, on at least the custom production domain, a Bot Management challenge system that can conditionally set a `cf_clearance` cookie (§11). A future Cookie Policy needs to describe this precisely rather than claim the site never sets any cookie. If the adult owner decides analytics/local-storage usage should also be disclosed regardless, this would need to be created or folded into the Privacy Policy. | — |
| Copyright/DMCA page | *(does not exist as a distinct page)* | Not built. `docs/LEGAL.md` (dated 2026-07-28) is aware these four legal pages exist as placeholders but does not mention a copyright/DMCA-specific page at all — this is a genuine gap not previously tracked anywhere. | — |

`docs/LEGAL.md` itself is dated 2026-07-28 and should be treated as a starting index, not a current-state source — it predates the Community Guidelines finalization (2026-08-11) and does not distinguish that page's real, published status from the other three pages' placeholder status. This document (MILESTONE_27B) supersedes `docs/LEGAL.md` as the current reference; `docs/LEGAL.md` is not edited by this PR (per the task's explicit prohibition on editing existing legal pages), but an adult owner may want to update or retire it in a later PR once real drafting work begins.

---

## 7. Age/minor-user risk and decision area

**Verified facts, not assumptions:**
- No age-verification, birthdate collection, or minimum-age attestation exists anywhere in the signup flow or elsewhere in the product (§2, §3).
- Signup is invite-gated but not identity- or age-restricted — an invite code only proves someone else chose to share it, not that the recipient meets any age threshold.
- The existing Community Guidelines page already describes the intended audience as including teenagers and prohibits sexual content and content "primarily intended to shock or disturb" — this reflects an implicit product assumption about a general-plus-teen audience, but it is not a COPPA-compliance mechanism and doesn't claim to be one.
- The product owner is a minor, and every relevant internal document (`docs/OPERATIONS.md`) already defers age-policy decisions to an adult owner/guardian.

**Why this matters**: COPPA (16 CFR Part 312, enforced by the FTC) imposes specific, serious obligations — including verifiable parental consent — on any operator that collects personal information from children under 13, either because the service is directed to children or because the operator has actual knowledge a user is under 13. A recent FTC Rule amendment (effective June 23, 2025, compliance deadline April 22, 2026 per the Federal Register notice cited in §17) expanded what counts as covered personal information and tightened consent requirements. Separately, the FTC has published non-COPPA guidance expressing concern about teen (13-17) privacy specifically, even though COPPA itself does not reach that age group. **This document does not determine whether COPPA applies to Specbound** — that requires an actual legal judgment about the product's audience and actual/constructive knowledge of users' ages, which is exactly the kind of determination reserved for the adult owner and counsel in the decision packet.

**What remains blocked until this is answered**: any age-related product copy (a minimum-age statement in Terms), any parental-consent flow (if under-13 users are to be supported at all), and the final wording of any Privacy Policy section describing children's data handling.

---

## 8. Geographic-scope decision area

No geographic restriction exists in the product today (§3). This means, as currently built, anyone anywhere with an invite code can create an account, regardless of jurisdiction. Virginia's Consumer Data Protection Act (VCDPA) is flagged specifically because the product's origin/operator context is Virginia-connected (see the decision packet for the operator question) and because Virginia's Attorney General has been actively enforcing VCDPA provisions, including ones specific to minors, as recently as February 2026 (see §17 sources). California's CCPA/CPRA and its regulator (the California Privacy Protection Agency) are flagged only as a **possible** review item if the adult owner intends to serve California residents at any meaningful scale — this document draws no conclusion that CCPA applies. The same applies to the EU/UK materials cited in §17: they are included only in case the adult owner intends to serve those locations, not as an indication that GDPR or the UK's Age Appropriate Design Code currently applies to Specbound. **What remains blocked until this is answered**: which jurisdictions' laws get reviewed at all, and whether any interim geographic restriction is wanted before public launch.

---

## 9. User-generated-content and copyright decision area

**Verified facts**: Specbound's Terms of Service (where UGC ownership/license terms would normally live) do not exist yet — only a placeholder. The Community Guidelines page (§6) already contains informal norms about authenticity and crediting others' work ("If a project builds on someone else's design, code, writing, or other material, say so and credit them... do not upload content you do not have the right to share" — §06) and a reporting mechanism for projects/comments (§08-09) — but this is a conduct expectation, not a license grant, ownership statement, or formal copyright/DMCA process. No DMCA designated agent has been registered (the U.S. Copyright Office's official directory, linked in §17, is where that registration would happen), and no copyright takedown contact or process exists anywhere in the product. **What remains blocked until this is answered**: what license (if any) Specbound needs from users to display/host their content, what happens to that license on account/content deletion, and who serves as the designated DMCA agent.

---

## 10. Account deletion, retention, moderation, and legal-hold decision area

Fully covered factually in §3 and the data-category matrix (§4); this section frames the open decisions only. The current *approved* product decision is to hard-delete a departing user's builds along with their account (not anonymize or soft-delete them) — that part is settled. What is not settled: (1) whether the `moderation_actions` audit-trail cascade-deletion (destroying a departing moderator's own action history) is acceptable, needs a schema change, or needs a documented exception process; (2) what "legal hold" means for Specbound at all — no such concept exists anywhere in the schema or documentation today, so if litigation-hold or law-enforcement-request obligations ever arise, there is currently no mechanism to pause deletion for a specific account; (3) whether the current fully-manual, staff-run deletion procedure is an acceptable long-term posture or whether a self-service deletion flow needs to be built before/at public launch; (4) acceptable retention periods generally (open reports, closed feedback, audit logs) beyond "indefinite, no TTL coded anywhere" as the current factual default.

---

## 11. Cookie/analytics/session inventory

Fully covered in §3 and the data-category matrix (§4). This section states the distinctions precisely rather than as one blanket claim, because an unqualified "no cookies" statement would be inaccurate once Cloudflare's own edge behavior is accounted for:

- **Specbound's own application code sets no cookie of any kind.** No `document.cookie` write exists anywhere in the JavaScript source — verified by a full-repository search, not assumed. The application's own client-side state is limited to `localStorage`/`sessionStorage`: Supabase's Auth session token, one anonymous view-tracking UUID (`js/core/anonViewerId.js`), and two further keys for draft-autosave and onboarding-dismiss state, none containing personal data.
- **Supabase Auth's session persistence** follows the Supabase JS SDK's documented default (`localStorage`-based, not a cookie) under this application's current, unmodified client configuration — `js/core/supabase.js` passes no custom `auth` options that would change this. This describes the verified current client configuration only; it is not a claim of full visibility into every possible Supabase account- or dashboard-level setting, which exists outside this repository and was not checked.
- **Cloudflare Web Analytics is cookieless, scoped specifically to Web Analytics.** Cloudflare's own documentation states it uses no client-side state — no cookies, no `localStorage` — for Web Analytics. This claim is Cloudflare's own and applies only to that one feature, not to every Cloudflare edge feature active on the site.
- **Cloudflare's Bot Management/challenge system is a separate edge feature, confirmed active on at least the custom production domain** (the `__CF$cv$params` JS-detection snippet, §3). Cloudflare documents `cf_clearance` as a cookie required for JavaScript detections, used to store proof a challenge was passed so a visitor is not re-challenged, and confirms it is set with the `SameSite=None; Secure; Partitioned` attributes and — by Cloudflare's own stated default, adjustable per zone by the site owner — a 30-minute lifetime. Cloudflare's page describes this partitioned behavior specifically for the case where the cookie is issued inside a third-party embedded context; it does not use the words "first-party" anywhere. **This specification treats a `cf_clearance` cookie issued during a visitor's direct interaction with the Specbound custom domain — not embedded in another site — as operating in a first-party browsing context for that visit.** That classification is this document's own technical inference from the deployment (Cloudflare terminates `specboundapp.com` directly, so a visit there is not a third-party embed) and from ordinary browser-cookie context, not Cloudflare's own wording and not a legal conclusion — an adult owner or counsel may reach a different characterization if relevant. **This is not something this repository's code sets, configures, or can disable, and it does not happen to every visitor — only one Cloudflare's own risk-scoring selects for a challenge.** But it means the factually supportable claim is "no cookie is set by this application's own code," never an unqualified "visitors to this site can never receive a cookie." See §17 for the official Cloudflare source.
- No third-party advertising or tracking-pixel cookie/script of any kind exists in the application's own code.

---

## 12. Security and incident-notice facts relevant to policy drafting

Production security headers, verified directly against the live site during this PR's own preflight (see this PR's final report for the exact request/response used):

- `Strict-Transport-Security: max-age=300` — a deliberately staged, short value (Stage 1 of a documented multi-stage rollout in `_headers`); no `includeSubDomains`, no `preload` yet.
- `Content-Security-Policy`: `default-src 'self'` with a narrow, explicit allowlist (`cdn.jsdelivr.net`, `static.cloudflareinsights.com`, `fonts.googleapis.com`/`fonts.gstatic.com`, the Supabase project domain) — no `unsafe-inline`, no `unsafe-eval`, no wildcard origins, `object-src 'none'`, `frame-ancestors 'none'`.
- `X-Content-Type-Options: nosniff`, `Referrer-Policy: strict-origin-when-cross-origin`, `Permissions-Policy: geolocation=(), microphone=(), camera=()`.
- Supabase Storage encrypts data at rest (per Supabase's own published security posture, cited in §17) and enforces row-level security on every table referenced in this document.
- **No incident-notification process, breach-notice template, or security-contact address exists anywhere in the product or its documentation today.** This is a genuine gap, not a decision already made — most state breach-notification laws (and VCDPA specifically) impose notice obligations if personal data is exposed; Specbound currently has no defined process for that scenario. This is listed as a decision item in the companion packet.

---

## 13. Proposed 27B PR sequence

This is a proposal for how remaining 27B work could be sequenced, offered for the adult owner to accept, reorder, or reject — not a commitment this document makes on anyone's behalf.

1. **PR1 (this PR)**: inventory + decision packet. No legal text, no signup change.
2. **PR2 (blocked on adult-owner decisions from this packet)**: draft real Privacy Policy and Terms of Service text, incorporating whatever answers the adult owner (and counsel, if engaged) gives to the decision packet. Still not published — drafted for review.
3. **PR3 (blocked on PR2 + explicit adult-owner sign-off)**: publish the reviewed, approved Privacy Policy and Terms of Service; add whatever age-gate or consent mechanism the decisions require; add a Cookie Policy if the adult owner decides one is warranted even with the current minimal footprint.
4. **PR4 (blocked on PR2/PR3 decisions)**: build or formally accept the account-deletion posture decided in the packet (self-service flow, or keep the manual procedure as the permanent design) and any legal-hold mechanism, if one is decided to be needed.
5. **27A PR1 (signup posture)**: only after the above, flip `BETA_INVITE_REQUIRED` and any newly-added age/consent gates for real public launch — this is 27A's own remaining item, sequenced after 27B's legal work by the existing roadmap dependency, not renumbered here.

---

## 14. Test/review gates

Before any future 27B PR in this sequence publishes real legal text or changes signup behavior, it should pass: all 8 existing static checks (`tools/ci/`), the full browser regression suite, a fresh accessibility pass on any new/changed page (axe-core + real keyboard verification, consistent with the standard established in Milestone 27A PR5), explicit adult-owner sign-off recorded in that PR's own description, and — for anything the adult owner decides needs it — attorney review recorded the same way. No PR in this sequence should mark itself "Ready" or merge without that sign-off being visible in the PR itself, not just implied.

---

## 15. Launch-blocking checklist

- [ ] Adult operator identified and decision packet completed (§ all of the companion document)
- [ ] Privacy Policy and Terms of Service drafted and reviewed (PR2 above)
- [ ] Privacy Policy and Terms of Service published, with explicit adult-owner approval on record (PR3 above)
- [ ] Age-related product decision implemented (minimum age statement, and/or a reviewed parental-consent mechanism if under-13 users are to be supported)
- [ ] Account-deletion posture finalized (self-service build, or manual procedure formally accepted as permanent) and any legal-hold mechanism built if decided necessary
- [ ] Copyright/DMCA contact and process established, including U.S. Copyright Office designated-agent registration if counsel advises it's needed
- [ ] Incident/breach-notification process defined
- [ ] `BETA_INVITE_REQUIRED` flipped and public signup opened (27A PR1) — only after every item above

None of these are checked off by this PR. This PR's only deliverable is the inventory and the decision packet that makes checking them off possible.

---

## 16. Explicit prohibited assumptions

To be unambiguous about what this document does *not* do, consistent with the task that produced it:

- This document does not assume Specbound is or is not subject to COPPA, VCDPA, CCPA/CPRA, GDPR, the UK Children's Code, or any other specific law. It identifies these as review questions.
- This document does not assume any minimum user age. "General audience that includes teenagers," the existing Community Guidelines' own phrase, is quoted as a fact about existing product copy, not adopted here as a policy conclusion.
- This document does not assume public signup should remain closed, nor that it should open on any particular timeline.
- This document does not assume the current data-retention defaults (mostly "indefinite, no TTL") are acceptable or unacceptable.
- This document does not assume an attorney review is or is not necessary — that choice belongs entirely to the adult owner.
- This document does not represent, anywhere, that any Specbound legal document is attorney-approved. None exist yet.
- This document does not claim that visitors to Specbound can never receive any cookie. It states precisely that this application's own code sets none, while Cloudflare's edge — outside this repository's control — may conditionally set its own `cf_clearance` cookie during a Bot Management challenge (§11).
- This document does not characterize Cloudflare's automated request-scoring/challenge system as legally regulated "automated decision-making." It describes what that vendor system does and leaves the legal characterization, if any, to the adult owner and counsel (§3, §11).
- This document does not reproduce lengthy text from any external official source verbatim — sources in §17 are paraphrased and linked, never substituted for reading the primary material directly.

---

## 17. Official sources, with retrieval date

All retrieved 2026-08-18. All are primary/official regulator, government, or vendor sources — no blog, law-firm-marketing, or secondary-commentary source is cited as authority anywhere in this document (secondary sources surfaced during research were used only to locate the primary link, never cited as the source of a claim).

**U.S. federal — children's/teen privacy (FTC / COPPA)**
- FTC — Children's Online Privacy Protection Rule ("COPPA"): https://www.ftc.gov/legal-library/browse/rules/childrens-online-privacy-protection-rule-coppa
- FTC — Kids' Privacy (COPPA) topic page: https://www.ftc.gov/news-events/topics/protecting-consumer-privacy-security/kids-privacy-coppa
- FTC — Children's Privacy (business guidance): https://www.ftc.gov/business-guidance/privacy-security/childrens-privacy
- FTC — Complying with COPPA: Frequently Asked Questions: https://www.ftc.gov/business-guidance/resources/complying-coppa-frequently-asked-questions
- FTC — Children's Online Privacy Protection Rule: A Six-Step Compliance Plan for Your Business: https://www.ftc.gov/business-guidance/resources/childrens-online-privacy-protection-rule-six-step-compliance-plan-your-business
- FTC — Verifiable Parental Consent and the Children's Online Privacy Rule: https://www.ftc.gov/business-guidance/privacy-security/verifiable-parental-consent-childrens-online-privacy-rule
- eCFR — 16 CFR Part 312, the COPPA Rule's full current regulatory text: https://www.ecfr.gov/current/title-16/chapter-I/subchapter-C/part-312
- Federal Register — Children's Online Privacy Protection Rule (2025 amendments): https://www.federalregister.gov/documents/2025/04/22/2025-05904/childrens-online-privacy-protection-rule

**U.S. federal — general privacy/security representations**
- FTC — Privacy and Security (business guidance hub): https://www.ftc.gov/business-guidance/privacy-security

**State — Virginia**
- Virginia Attorney General — Consumer Data Protection Act resources: https://www.oag.state.va.us
- Virginia AG — The Virginia Consumer Data Protection Act (official summary PDF): https://www.oag.state.va.us/consumer-protection/files/tips-and-info/Virginia-Consumer-Data-Protection-Act-Summary-2-2-23.pdf

**State — California (review item only, not an applicability conclusion)**
- California Privacy Protection Agency (CPPA), official site: https://cppa.ca.gov/
- California Attorney General — CCPA: https://oag.ca.gov/privacy/ccpa

**EU/UK (review items only, relevant solely if the adult owner intends to serve those locations)**
- UK ICO — Age appropriate design: a code of practice for online services (Children's Code): https://ico.org.uk/for-organisations/uk-gdpr-guidance-and-resources/childrens-information/childrens-code-guidance-and-resources/age-appropriate-design-a-code-of-practice-for-online-services/
- European Data Protection Board (EDPB), official site: https://www.edpb.europa.eu/

**Vendor privacy/data-processing documentation**
- Discord — Privacy Policy: https://discord.com/privacy
- Supabase — Privacy Policy: https://supabase.com/privacy
- Supabase — Data Processing Addendum: https://supabase.com/legal/dpa
- Cloudflare — Data Processing Addendum: https://www.cloudflare.com/cloudflare-customer-dpa/
- Cloudflare — "Cloudflare Cookies" (confirms `cf_clearance` is used for JavaScript detections and is set with `SameSite=None; Secure; Partitioned`; this page describes partitioning specifically for third-party embedded contexts and does not use the words "first-party" or "first party" anywhere — the first-party characterization in §11 is this specification's own inference for a direct, non-embedded visit, not quoted Cloudflare language): https://developers.cloudflare.com/fundamentals/reference/policies-compliances/cloudflare-cookies/
- Cloudflare — "Challenge Passage" (confirms the `cf_clearance` cookie's default 30-minute lifetime): https://developers.cloudflare.com/cloudflare-challenges/challenge-types/challenge-pages/challenge-passage/
- Cloudflare — "Bot scores" (confirms Cloudflare's own description of its request-scoring system, used to "block, challenge, or allow requests based on their score"): https://developers.cloudflare.com/bots/concepts/bot-score/

**Copyright / DMCA**
- U.S. Copyright Office — DMCA Designated Agent Directory: https://www.copyright.gov/dmca-directory/
- U.S. Copyright Office — Section 512 resources (safe harbor / notice-and-takedown): https://www.copyright.gov/512/

---

## Related documents

- `docs/milestones/MILESTONE_27B_ADULT_OWNER_DECISION_PACKET.md` — the companion decision document this specification exists to inform.
- `docs/OPERATIONS.md` §10 — the full manual account-deletion procedure referenced throughout §3/§4/§10.
- `docs/STORAGE_ARCHITECTURE.md` — full Storage bucket/path/signed-URL detail referenced in §3/§4.
- `docs/LEGAL.md` — the prior, now-partially-stale placeholder-tracking note (see §6).
- `docs/ROADMAP.md` — the live milestone index this PR updates narrowly (§2).
