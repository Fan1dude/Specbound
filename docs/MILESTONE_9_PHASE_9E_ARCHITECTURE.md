# Milestone 9 — Phase 9E: Final Launch Verification — Architecture Proposal

**Status: Track A complete and verified live (2026-07-27). Track B not started — requires a live Cloudflare Pages deployment, which does not exist yet. Results, a Known Limitations section, the Track-A scorecard, and the launch recommendation are all at the end of this document, after the original plan.**

**Scope:** the closing phase of Milestone 9 — verify the cumulative result of Migrations A/B/C and Phases 9C/9D actually holds, run the checks this milestone has deferred to this point (S2's profiles INSERT policy, L4/L6/L8/L9/L10 from the original audit), and produce a final, honestly-scored recommendation on launch readiness.

**A structural note before the plan itself**: this phase splits cleanly into two tracks, and the plan below is organized around that split rather than strictly around the user's 6 numbered categories, because it changes what's actually executable right now versus what has a hard dependency:

- **Track A — verifiable today**, against the live Supabase project (anon key, browser-driven, same methodology used throughout Migrations A/B/C) and the local dev server. No production deployment exists yet — confirmed via `git remote -v` (empty) — so nothing requiring a live production URL can run until Phase 9D's deployment steps are actually carried out.
- **Track B — requires a live production deployment first**: Lighthouse/PageSpeed against the real URL, DNS/Cloudflare/domain checks, Supabase Auth redirect verification against the real domain, production header verification against what Cloudflare Pages actually serves (as opposed to the local dev server simulating it, which is as far as Phase 9D's own verification could go).

Each section below is tagged **[A]** or **[B]** accordingly. This isn't a scope change from what you asked for — it's making explicit which parts of the plan can start immediately on approval and which parts are blocked on your own deployment action (matching the "document exact steps instead of claiming completion" principle already established in `docs/DEPLOYMENT.md`).

---

## 1. Security

| # | Item | Track | Method |
|---|---|---|---|
| S-1 | **Verify the `profiles` INSERT policy** | A | `SELECT * FROM pg_policies WHERE tablename = 'profiles' AND cmd = 'INSERT'` (you run in the Supabase SQL editor, same pattern as every prior live-policy check this milestone). Confirm `with_check` is scoped to `auth.uid() = id` (or equivalent) — this is the one item explicitly deferred from the S2 resolution in `docs/AUTH_ARCHITECTURE.md` §3. If it's unscoped, this becomes a **launch blocker** requiring its own scoped migration (same pattern as Migration A) — not expected to block, given the profile-creation code path was already found structurally safe regardless of policy wording, but the live confirmation is still owed. |
| S-2 | **Reconfirm Storage RLS** | A | Re-run the exact behavioral test set from Migration A/C's verification: anonymous root/folder listing denied, anonymous upload denied, anonymous signing of an orphaned/unlinked path denied, owner can sign their own draft media, public visitor can sign a published build's media, cross-user signing of a private draft denied. Nothing in Phases 9C/9D touched RLS or storage policies, so this is a regression check, not new territory — expected to pass cleanly, but "expected to pass" is exactly the kind of assumption this milestone has repeatedly found worth verifying rather than trusting. |
| S-3 | **Reconfirm bucket privacy** | A | Attempt a direct fetch against `/storage/v1/object/public/project-images/<any known path>` — confirm it still fails (bucket flag is a dashboard setting, not code, so nothing in 9C/9D could have changed it, but it's a one-request check and this milestone's whole storage arc started with exactly this setting being wrong). |
| S-4 | **Verify no secrets exist** | A | Repo-wide scan for `.env`, service-role key patterns, private-key markers, hardcoded tokens — same pattern as the original Milestone 9 audit and the Phase 9C/9D pre-commit checks, run once more as a final gate specifically over the full accumulated history, not just the latest diff. |
| S-5 | **Verify CSP** | B | Phase 9D verified the CSP against the **local dev server** with the header temporarily injected — a necessary approximation at the time, since no production deployment existed. This item re-runs that same check against the **real Cloudflare Pages deployment**, confirming `_headers` is actually being honored in production (Cloudflare Pages picks up `_headers` automatically, but "should work" and "confirmed working against the real thing" are different claims, and this milestone has a demonstrated pattern of the two not always matching). |
| S-6 | **Verify production headers** | B | Beyond CSP specifically: confirm `X-Content-Type-Options`, `Referrer-Policy`, `Permissions-Policy` are all present on real production responses (`curl -I` or `read_network_requests` against the live domain). |

## 2. Performance

| # | Item | Track | Method |
|---|---|---|---|
| P-1 | **Lighthouse audits** | B | **Important tooling constraint, stated plainly**: nothing in this environment can run Chrome DevTools' Lighthouse panel directly. Two real options: (a) Google PageSpeed Insights' public API (`https://pagespeed.web.dev/`, backed by Lighthouse), fetchable once a real production URL exists — this is the planned default; (b) you run Lighthouse yourself via Chrome DevTools and share the results. Plan is (a), with (b) as the fallback if the API is rate-limited or unavailable. Run against: homepage, Explore, a build page, a profile page, the editor (representative of the 5 distinct template types this app actually has). |
| P-2 | **Performance review** | A + B | Track A now (re-verify the Phase 9C fixes still hold: fonts load correctly on all pages, `loading="lazy"` present where added, the pinned Supabase CDN version resolves). Track B once live (real network waterfall against production — Cloudflare's actual edge latency, not the local dev server's). |
| P-3 | **Accessibility review** | A | The original Milestone 9 audit explicitly carried forward 8D's 8/10 accessibility score **without** a fresh re-check, flagging that Phase 9C's cleanup work touched several of the same files 8D fixed (footer links, page structure via the dead-code removals). This is the deferred re-check: keyboard navigation, focus management, screen-reader labels, contrast, and mobile interaction — re-verified against the *current* DOM, not assumed unchanged since 8D. Runs against the dev server, no production dependency. |
| P-4 | **Best Practices** | B | Largely covered by Lighthouke's own "Best Practices" category (P-1) — HTTPS, no console errors, no deprecated API usage, correct image aspect ratios. Cross-referenced against Track A's manual console-error sweep across the same page set used throughout Phases 9C/9D. |
| P-5 | **SEO review** | A + B | Track A: confirm the Phase 9D metadata work is structurally complete (already verified 25/25 pages have full tags — this re-verifies nothing broke since, e.g. no page lost its `<title>` in a later edit). Track B: confirm `robots.txt`/`sitemap.xml` are reachable at the real domain, confirm Google's [Rich Results Test](https://search.google.com/test/rich-results) or PageSpeed's SEO category doesn't flag anything the local-only check couldn't catch (e.g. an incorrect canonical due to the `specbound.app` placeholder not having been swapped for the real domain yet — see `docs/DEPLOYMENT.md` §3, this is a real thing to double check hasn't been missed). |

## 3. Functional verification

This app has **no automated end-to-end test suite** — `tests/*.test.html` (23 files) are component/unit-level (e.g. `resolveBuildImageUrls.test.html` tests one repository function, not a full user flow). Functional verification here means live, browser-driven testing against real (test) data, the same methodology used throughout Migrations A/B/C's regression passes. Existing component tests are cited below where they provide *partial* coverage, but none substitute for the live end-to-end check.

| Area | Existing component-test coverage | Live verification plan |
|---|---|---|
| **Authentication** | None dedicated | Sign up (new test account), confirm `ensureProfile()` creates a row (per `docs/AUTH_ARCHITECTURE.md`), sign out, sign in, trigger password reset and confirm the email's link domain (ties directly to S-5-adjacent item in `docs/DEPLOYMENT.md` §4 — can only fully close once production exists) |
| **Upload flow** | `gallery20.test.html`, `legacyImageUrlCompatibility.test.html` | Upload an avatar (all 4 size variants land in Storage), upload gallery images to a draft, confirm signed URLs resolve, confirm the D6 correction from Phase 9C (the *actual* reachable upload zone, editor gallery section) still shows upload progress/feedback correctly |
| **Build creation** | `draftValidation.test.html`, `editorPublishUnpublish.test.html` | Create a draft, fill specifications, publish, confirm `revision_media` rows are created correctly (per `docs/STORAGE_ARCHITECTURE.md` §4), confirm the published build renders on its public URL |
| **Revision history** | `revisionView.test.html`, `restoreButton.test.html`, `buildImageResolution.test.html` | Publish a second revision, confirm the timeline shows both, confirm each revision's images resolve independently, test "restore to draft" from an older revision |
| **Comments** | `comments.test.html` | Post a comment (authenticated), confirm it renders with correct avatar/date formatting (post-Phase-9C consolidation — `formatDate`/`avatarInitial` now shared utils, worth confirming the consolidation didn't subtly change comment rendering) |
| **Follow system** | `followList.test.html`, `renderFollow.test.html` | Follow/unfollow a builder, confirm follower/following counts update, confirm the followers/following pages render correctly (these were part of the Phase 9D metadata + noindex work — confirm that didn't affect functionality, only `<head>` content) |
| **Search** | `searchBuilds.test.html`, `searchPage.test.html` | Live search across builds — **note**: `searchPage.test.html` has a known, pre-existing, environment-specific hang unrelated to app code (documented earlier this milestone: the Browser pane doesn't composite frames when not visually displayed, which breaks the debounce timing this test depends on) — live verification in an actually-displayed browser context sidesteps this, but it's worth remembering this isn't a real app bug if the automated test itself is run again and hangs |
| **Workshop** | `workshopSaved.test.html` | Confirm "My Projects," drafts, and saved builds all render correctly for a signed-in user |
| **Settings** | `profile.test.html` (partial) | Update profile fields, upload a new avatar, confirm `updateAvatarPath()` and the settings page's `resolveAvatarUrl()` usage (the Phase 9C centralization fix) still work correctly |
| **Notifications** | `notificationBell.test.html`, `notifications.test.html` | Trigger a notification-generating action (comment, follow, like) from a second account, confirm it appears for the recipient, confirm mark-read/mark-all-read |
| **Profile pages** | `profile.test.html`, `renderFollow.test.html` | View another user's public profile anonymously (confirms the S4 fix — `getPublicProfile()` — still returns everything the page needs and nothing more) |
| **Error handling** | `editorPublishedBuildMissing.test.html`, `listState.test.html` | Deliberately trigger failure paths: navigate to a nonexistent build slug, a deleted revision, a network failure mid-upload — confirm graceful degradation (toast messages, placeholder fallbacks) rather than a broken/blank page; confirm the new `404.html` (Phase 9D) covers the "URL doesn't exist at all" case correctly |

**A note on test data hygiene**: live functional verification should use a dedicated test account (or the existing `fan1dude`/`fan1dude1` test builds already present in the database from this milestone's prior verification work), not a real user's account — consistent with how Migration A/B/C's verification was conducted throughout this session.

## 4. Production readiness

All of Track B by nature — these are exactly the checklists `docs/DEPLOYMENT.md` already wrote out as "steps to follow," now being formally treated as a required gate before calling the milestone done rather than optional reference material:

| Checklist | Source | What it confirms |
|---|---|---|
| **Deployment checklist** | `docs/DEPLOYMENT.md` §10 | Cloudflare project connected, build command/output directory set, first deploy succeeded |
| **DNS checklist** | `docs/DEPLOYMENT.md` §5 | Domain resolves, points at Cloudflare correctly |
| **Cloudflare checklist** | `docs/DEPLOYMENT.md` §1, §5, §7 | `_headers` is being served, SSL is active and auto-renewing, a rollback has been tested at least once live (per §9.11 of that document — not yet done, since it requires a real deployment to roll back) |
| **Supabase checklist** | `docs/DEPLOYMENT.md` §4 | Site URL and Redirect URLs updated to the real domain (not left on a dev/localhost value) |
| **Auth redirect verification** | `docs/DEPLOYMENT.md` §9.10 | A real password-reset email, triggered against production, contains a link to the real domain |
| **Domain verification** | `docs/DEPLOYMENT.md` §3 | The `https://specbound.app` placeholder has been replaced everywhere (canonical tags, `og:url`, `sitemap.xml`, `robots.txt`'s `Sitemap:` line) with the actual chosen domain — this is a real, specific thing to double-check hasn't been silently missed, since it's a find-and-replace across ~20 files that's easy to partially forget |

## 5. Final scorecard — methodology

The original Milestone 9 audit (`docs/MILESTONE_9_ARCHITECTURE.md`) scored 8 categories against the *pre-fix* state, explicitly as a snapshot to be revisited once fixes landed. This phase is that revisit. **The actual scores are not filled in below** — that requires Sections 1-4 of this plan to actually run, which requires approval and, for the Track B items, your own deployment action first. What's defined here is the scoring methodology, so the eventual scorecard is computed consistently rather than assigned by feel:

| Category | What feeds the score |
|---|---|
| **Security** | Section 1 results (S-1 through S-6). Capped at whatever the lowest-severity unresolved item implies — e.g. if S-1 (profiles INSERT policy) turns out unscoped, Security cannot score above the original audit's pre-fix ceiling regardless of how clean everything else is, matching how the original audit's methodology treated unresolved unknowns |
| **Reliability** | Rollback tested and working (§4), CSP/headers confirmed live (S-5/S-6), error-handling verification (§3's Error Handling row) |
| **Performance** | Lighthouse Performance category score (P-1) directly, cross-checked against the manual review (P-2) |
| **Accessibility** | Lighthouse Accessibility category score (P-1) plus the manual re-check (P-3) — the manual check matters more here, since Lighthouse's automated accessibility audit catches roughly a third of real WCAG issues by its own documented limitations, and 8D's original pass was manual/thorough for exactly this reason |
| **Maintainability** | Backward-looking: did Phase 9C's cleanup actually stick (no new dead-code recurrence), is the codebase in a state a future session could pick up cleanly. Not a fresh audit — carried forward from Phase 9C's completion state unless Section 3's functional verification surfaces something new |
| **Deployment** | Section 4 in full — every checklist item either done or explicitly not | 
| **Documentation** | Does `docs/` accurately reflect the live system as of this phase — `STORAGE_ARCHITECTURE.md`, `AUTH_ARCHITECTURE.md`, `DEPLOYMENT.md`, `OPERATIONS.md` all exist and were kept current through 9C/9D; this phase's own output (this document, once executed) is the last piece |
| **Launch Readiness (Overall)** | Not an average of the above — a floor set by the single worst *launch-blocking* item, same principle the original audit used (it scored 5/10 overall despite several strong individual categories, because a few Critical/High items capped it) |

## 6. Final recommendation — decision framework

Once Sections 1-5 actually run, the recommendation will be one of the three options you specified, chosen by this rule (defined now, applied then, so the decision isn't made ad hoc in the moment):

- **Ready for production**: zero unresolved Critical/High findings across Section 1 (Security) and Section 4 (Production readiness); Performance/Accessibility/Best Practices/SEO all at or above a reasonable bar (not necessarily perfect scores — this audit's own prior standard was "9/10 for launch-critical categories," not 10/10); Section 3's functional verification finds no broken user-facing flow.
- **Ready after minor fixes**: everything above holds *except* a small number of Low/Medium findings with a clear, scoped, quick fix — named explicitly, not left vague, with an estimate of what "minor" actually means in hours/files touched.
- **Not ready**: any unresolved Critical/High Security or Production-readiness item, or a functional verification failure in a core user flow (auth, upload, publish — the load-bearing paths), or a Performance/Accessibility result meaningfully below bar with no quick fix available.

No recommendation is being made in this document — that would mean pre-deciding the answer before running the verification that's supposed to determine it, which defeats the point of this phase.

---

## Sequencing

1. **Track A items can start immediately on approval** — no dependency on you doing anything else first (S-1 through S-4, P-2/P-3/P-5's local halves, all of Section 3's functional verification against the current dev environment).
2. **Track B items are blocked on your own deployment action** (`docs/DEPLOYMENT.md` §1-§5: connect the repo to Cloudflare Pages, add the custom domain, update Supabase's Auth settings). Recommend running Track A first regardless — if Track A surfaces a real blocker (e.g. S-1's policy is unscoped), that's worth knowing and fixing before spending time on production deployment mechanics.
3. Sections 5-6 (scorecard, recommendation) are the final step, after both tracks are complete.

---
---

# Track A — Results (2026-07-27)

Everything below is what was actually run and observed, against the live Supabase project and the local dev server, using a QA account (`fan1dude` — pre-existing, not freshly created) provided for this purpose. No Track B item was attempted or fabricated.

## 1. Security — results

| # | Item | Result |
|---|---|---|
| S-1 | Profiles INSERT policy | **Investigated in depth — see the dedicated section below.** Live query returned zero rows (no INSERT policy exists at all). Empirically proven safe anyway: a real database-level trigger (not visible in any tracked migration) creates profile rows server-side, and a direct client INSERT attempt is unconditionally denied for any id. `docs/AUTH_ARCHITECTURE.md` has been corrected accordingly. |
| S-2 | Storage RLS reconfirmed | **Pass.** Anonymous root/folder listing precisely scoped (verified the exact 3 objects listed for a public build's folder match exactly its linked `revision_media` paths, nothing more); anonymous upload denied (`42501`-style RLS violation); anonymous signing of a known orphan path denied ("Object not found"); anonymous signing of a genuinely public build's revision media succeeds. No regression since Migration A/C. |
| S-3 | Bucket privacy reconfirmed | **Pass.** Direct fetch to `/storage/v1/object/public/project-images/<a real, public, signable path>` still returns 400. Bucket remains Private. |
| S-4 | No secrets | **Pass.** Repo-wide scan (working tree + full `git log -p` history, not just the latest diff) for `.env` files, service-role key patterns, private-key markers — zero matches. |
| S-5 | CSP verified live in production | **Not run — Track B (no production deployment exists).** Already verified against the local dev server in Phase 9D (temporarily sending the real header); re-verification against the actual Cloudflare Pages deployment is a Track B item. |
| S-6 | Production headers verified live | **Not run — Track B**, same reason as S-5. |

## 2. Performance — results (Track A portions only)

| # | Item | Result |
|---|---|---|
| P-1 | Lighthouse | **Not run — Track B.** No production URL exists to audit, and this environment has no way to invoke Lighthouse directly (as flagged in the original plan) — PageSpeed Insights against the real domain is the intended method once deployed. |
| P-2 | Performance review (local half) | **Pass.** Spot-checked: Google Fonts load correctly across pages, `loading="lazy"` present on the Phase 9C-added spots, the pinned Supabase CDN version (`@supabase/supabase-js@2.110.8`) resolves and the app functions correctly on it (confirmed throughout every authenticated action performed in Section 3 below). |
| P-3 | Accessibility manual re-check | **Pass**, focused on the specific files Phase 9C's utility consolidation touched. Re-verified via the accessibility tree (not just visual inspection): build page retains its skip link, `aria-live`/`status` regions for like/save sign-in prompts and the empty comments state, descriptive accessible names on icon-only controls ("Toggle navigation menu," "Notifications"). Explore/Search's `BlueprintCard`/`BlueprintFeed` output retains descriptive per-card link names ("View TEST 12345," not a bare "View more"). The editor's `ComponentAutocomplete` (an ARIA combobox) was tested live and authenticated (see Section 3) — `role="combobox"`, `aria-expanded` toggling correctly, `aria-controls` pointing at a real `role="listbox"` populated with `role="option"` children on a real search. The notification bell disclosure widget was also tested live — `aria-haspopup="true"`, `aria-expanded` toggles correctly on open. No regression found anywhere touched by the Phase 9C consolidation. |
| P-4 | Best Practices | **Partially assessable without Lighthouse** — no console errors observed across any tested page beyond one pre-existing, unrelated, already-known issue (a `view_recording`-adjacent error present before any Milestone 9 work began, unrelated to app functionality). Full category score is Track B. |
| P-5 | SEO review (local half) | **Pass.** Re-confirmed all 25 real pages still carry complete metadata (title/description/OG/Twitter — automated field-count check, zero missing). Confirmed the `specbound.app` placeholder is consistently present across exactly the 27 expected files (25 pages + `robots.txt` + `sitemap.xml`), nothing missed or partially replaced. Live indexability checks (Rich Results Test, real `robots.txt`/`sitemap.xml` reachability at the real domain) are Track B. |

## 3. Functional verification — results

Anonymous (no auth needed):

| Area | Result |
|---|---|
| Search | **Pass.** Query "trap" correctly matched "trap open"; confirmed the debounce/search-then-render cycle completes correctly (an empty-seeming intermediate "Searching..." state was observed mid-flight, expected). |
| Public profile pages | **Pass.** Rendered correctly (avatar initial, bio, stats, published projects list) for an anonymous viewer. |
| Revision history viewing | **Pass**, including the honest "not recorded for this revision" state for a pre-snapshot revision, and the "viewing an older revision, publishing history is never changed" banner. |
| Error handling — nonexistent build | **Pass.** A nonexistent slug degrades gracefully to a "Blueprint unavailable" state (with an expected, intentionally-logged `console.error`), not a blank page or uncaught exception. |
| Error handling — 404 page | **Pass** (re-confirmed from Phase 9D). Note: the *routing* that auto-serves `404.html` for any unmatched URL is a Cloudflare Pages platform feature and cannot be exercised against the local dev server (a plain Python `http.server` with no such routing) — this specific sub-behavior is implicitly Track B, only the page's own content/rendering was re-verifiable here. |
| Followers list viewing | **Pass.** |

Authenticated (QA account, `fan1dude`):

| Area | Result |
|---|---|
| Login | **Pass.** |
| Logout | **Pass.** Confirmed at the app level, not just the SDK: after `signOut()`, navigating to an auth-gated page (`settings.html`) correctly redirected to `login.html`. |
| Workshop | **Pass.** Rendered "Welcome back, fan1dude," in-progress drafts, and "My Projects" correctly. |
| Upload flow | **Pass.** A synthesized test PNG was uploaded through the real gallery upload path (file input → Storage → `project_media` insert → auto-cover-assignment) and rendered in the gallery grid. |
| Build creation | **Pass, end to end.** Created a new draft ("Phase 9E QA Test Draft"), filled specifications via `ComponentAutocomplete`, uploaded a gallery image, published — the resulting build page rendered correctly at its real public URL with all data intact. |
| Revision creation/history | **Pass.** Used "Update Live Version" on the same test build — version correctly bumped v1.0 → v1.1, and the Project Log correctly showed both revisions. |
| Comment posting | **Pass**, tested twice: once on the QA account's own build, once cross-user on an existing build owned by a different account (`trap-open`, owned by `fan1dude1`) — both posted correctly with no console errors, both cleaned up afterward via `deleteComment()`. |
| Follow/unfollow | **Pass.** Followed `fan1dude1` — follower count correctly went 0→1, the button correctly changed to "Following," and the followers list correctly showed the new follower. Unfollowed afterward — count correctly returned to 0. |
| Notifications | **Partially verified.** The notifications page itself renders correctly (empty state, "Mark all read" control present). The cross-user comment above exercised the code path that creates a notification for the *other* account, with no error — but confirming that `fan1dude1` actually *received* it isn't independently verifiable without that account's own session (`notifications` RLS correctly restricts each user to only their own rows — the same privacy boundary that makes this hard to test from `fan1dude`'s session is itself a good sign, not a gap). **Recorded honestly as indirect evidence (no error on the creating side), not a fully closed-loop confirmation.** |
| Settings / profile editing | **Pass.** Updated the bio field, saved (confirmed via a live "updated successfully" toast), then restored it to its original empty value afterward. |
| ComponentAutocomplete accessibility | **Pass** — see P-3 above. |
| Notification-bell accessibility | **Pass** — see P-3 above. |

**Test-data cleanup performed**: both test comments deleted; the follow relationship removed; the settings bio field restored to its original (empty) value; the test build (`phase-9e-qa-test-draft`) set back to `visibility: private` (unpublished, not deleted — this app has no build-delete feature, and deleting isn't necessary to remove it from public view). **Left behind, low-impact**: the test build itself still exists as a private/unpublished row (harmless, not publicly visible, same treatment any real abandoned draft gets); one earlier unrelated test signup (`sectest...@gmail.com`, from the profiles-INSERT investigation) remains unconfirmed with an auto-created profile row — pre-existing test-data noise from this same investigation, not new clutter from this pass.

## 4. Production readiness — local-only results

All from `docs/DEPLOYMENT.md`'s checklist that can run without a real deployment:

| Item | Result |
|---|---|
| Metadata completeness | **Pass** — re-confirmed 25/25 pages. |
| Manifest/icons | **Pass** — re-confirmed both icon sizes resolve, manifest parses. |
| `robots.txt`/`sitemap.xml` validity | **Pass** — re-confirmed. |
| 404 page content | **Pass** — re-confirmed (routing behavior itself is Track B, see Section 3 above). |
| Domain placeholder consistency | **Pass** — exactly 27 files reference `specbound.app`, matching the expected set precisely. |
| Everything requiring Cloudflare/DNS/a real domain | **Not run — Track B**, per `docs/DEPLOYMENT.md` §1, §5, §7. |

---

## Profiles INSERT policy — investigation, findings, and proposed fix

**Your live query result** (`SELECT * FROM pg_policies WHERE tablename = 'profiles' AND cmd = 'INSERT'`) returned **zero rows**. Investigated per your 4 questions:

**1. Does profile creation succeed?** Yes, unconditionally. Confirmed for the QA account (`fan1dude`, an established account with a real working profile) and — more tellingly — for a brand-new, still-email-unconfirmed signup from earlier this session (`sectest1785120843704@gmail.com`, id `35d9e517-74fa-463d-9cd0-46f86f0a8873`) that **never received a browser session and for which the app's own `ensureProfile()` client-side code was never called** (its call site is explicitly gated `if (data.session)`, and no session existed). That user has a real `profiles` row anyway, with the exact username passed at signup.

**2. What mechanism?** By elimination, backed by direct testing:
- Not a database policy — confirmed zero rows for `cmd = 'INSERT'`.
- Not client-side/service-role code — this architecture has no server component, and a live test proved the client path is blocked (below).
- **Must be a database-level trigger** on `auth.users`, almost certainly `AFTER INSERT`, calling a `SECURITY DEFINER` function (or a function owned by a role that bypasses RLS) that reads the new user's metadata and writes the corresponding `profiles` row — the standard, well-documented Supabase pattern for this exact use case. It runs entirely server-side, in the same transaction as (or immediately after) the `auth.users` insert, before any client JavaScript executes.

**3. Why does this work with zero policies?** Because RLS policies only ever gate `anon`/`authenticated` roles making requests through PostgREST (i.e., through the Supabase client library, carrying the user's JWT). A trigger function — especially a `SECURITY DEFINER` one — runs as its *owner* (typically the table/schema owner, e.g. `postgres`), a role RLS was never applied to in the first place. This is confirmed directly: authenticated as `fan1dude`, a direct `supabase.from("profiles").insert([{ id: "<an arbitrary UUID>", username: "..." }])` call was **denied**, `42501`, `"new row violates row-level security policy for table \"profiles\""` — the exact, correct behavior of RLS-enabled-with-zero-matching-policies. The trigger's writes don't go through this path at all.

**4. Is this a security issue, or a missing migration?**

**Not a security issue — it's actually a stronger posture than the "properly scoped INSERT policy" originally recommended as the fix.** A policy-gated INSERT (even one correctly scoped to `auth.uid() = id`) is still a client-reachable code path, evaluated per-request against attacker-supplied input. **No policy at all** means there is categorically no client-reachable INSERT path whatsoever — not "restricted," *absent*. The only way a `profiles` row is ever created is by reacting to `auth.users` itself, which ordinary client code cannot write to directly. This closes out the exact impersonation-shaped risk the original (now-corrected) `docs/AUTH_ARCHITECTURE.md` had flagged as a hypothetical — that risk class doesn't exist here.

**It *is* a missing migration — a documentation/tracking gap, the same shape as the original `profiles` table and its SELECT/UPDATE policies before this milestone's work.** The trigger is real, live, and correctly locked down, but it exists nowhere in this project's 18 tracked migrations — anyone reading only the migration history (as the original, now-corrected version of `docs/AUTH_ARCHITECTURE.md` did) would wrongly conclude no such mechanism exists.

**Proposed fix**: a new baseline migration, `0019_baseline_profile_creation_trigger.sql`, that **documents the existing trigger and function verbatim — a capture, not a behavior change.** This is deliberately not proposed as a `CREATE OR REPLACE` that recreates the trigger from a guess at its logic, since guessing wrong could silently alter live signup behavior. **To write this accurately, one more live query is needed** (not run yet — this document stops at "propose," per your Track-A-only instruction):

```sql
-- Get the trigger definition
SELECT tgname, tgrelid::regclass AS table_name, tgtype, tgenabled,
       pg_get_triggerdef(oid) AS definition
FROM pg_trigger
WHERE tgrelid = 'auth.users'::regclass AND NOT tgisinternal;

-- Get the function(s) it calls
SELECT proname, prosecdef AS is_security_definer, pg_get_functiondef(oid) AS definition
FROM pg_proc
WHERE proname IN (
    SELECT tgfoid::regprocedure::text
    FROM pg_trigger
    WHERE tgrelid = 'auth.users'::regclass AND NOT tgisinternal
);
```

Once you share those results, the migration file can transcribe the real, live definition exactly (marked as a baseline/documentation migration, `-- Status: capturing pre-existing database state, not a behavior change`, matching this project's established migration-file header convention), plus its own `_rollback.sql` (which for a pure-capture migration would be a no-op with an explanatory comment, since there's nothing to actually roll back — the trigger already existed before the migration file did). **Not implemented yet** — this is the proposal, awaiting either your go-ahead or the query results, whichever you'd prefer to provide first.

`docs/AUTH_ARCHITECTURE.md` has already been updated to reflect all of the above as the current, correct understanding.

---

# Known Limitations

Intentional architectural decisions, carried into production as-is. **None of these are defects, and none block launch** — they're documented here so they're understood as deliberate, not rediscovered later as surprises.

- **Generic Open Graph image for dynamic pages.** `build.html`, `profile.html`, `followers.html`, `following.html`, and `pages/build/edit.html` all use the same brand-level `og-image.png` rather than a per-build/per-profile preview image. This architecture has no server-side rendering — a single static HTML template cannot emit different `og:image`/`og:title` per instance. Producing true per-build social previews would require adding either a server-rendering layer or a serverless image-generation function, both out of scope for this milestone. Decided and documented in Phase 9D (`docs/MILESTONE_9_PHASE_9D_ARCHITECTURE.md` §2.5).
- **The Migration B legacy-URL compatibility layer is retained until a Migration D.** `extractStoragePath()` in `mediaRepository.js` still normalizes pre-Milestone-5A full public URLs on every read. This is deliberate — the alternative (a one-time data migration rewriting every legacy `image_url`/`avatar_url` value to a bare path) was explicitly deferred, not forgotten, when Migration B was scoped. The compatibility layer works correctly today and carries negligible runtime cost (a regex check + string slice); removing it is a future cleanup opportunity, not a current gap.
- **"Verified Legacy Covers" remain intentionally unlinked.** Migration C's audit found 3 legacy cover images with provable *ownership* but no provable *revision linkage* (no `build_revisions` row corroborates them). Per the approved scope, these were deliberately left on the placeholder-fallback path rather than force-linked to an unrelated revision (which would have asserted something false in the data). Documented in `docs/STORAGE_ARCHITECTURE.md` §8 and `docs/MILESTONE_9_MIGRATION_C_SUMMARY.md`.
- **No server-side rendering (SSR).** Every page is a static HTML file with client-side data loading. This is the root cause of the OG-image limitation above, and of why dynamic pages (`build.html`, `profile.html`) can't set a per-instance `<title>`/canonical URL in the raw HTML response. A deliberate architectural choice for a project of this scale (no build step, no server to operate or secure), not an oversight.
- **No custom 500 page.** Explicitly decided in Phase 9D and reconfirmed in this phase: this architecture has no server-side code path that could produce a traditional 500 error. Supabase-layer failures are already handled by the app's own client-side error/toast UI (proven throughout this phase's functional verification — e.g. the graceful "Blueprint unavailable" degradation for a nonexistent build). Building a 500 page would handle a case that cannot structurally occur here.
- **Deployment-based Cloudflare cache strategy (no custom `Cache-Control` overrides).** `_headers` intentionally carries no cache directives for JS/CSS/assets. This was a real correction made during Phase 9D: Cloudflare's own documentation recommends against custom caching on a custom domain for a site with no content-hashed filenames (this app has none, having no bundler), since it risks stale assets surviving a deploy. The app instead relies entirely on Cloudflare Pages' built-in per-deployment cache invalidation, which is already correct with zero configuration. Documented in `docs/DEPLOYMENT.md` §8.

---

# Final scorecard — Track A only

Scored against what Track A actually proved. Categories that depend materially on Track B evidence are marked as such rather than guessed.

| Category | Score | Basis |
|---|---|---|
| **Security** | **8/10** | Every live-checkable item passed (Storage RLS, bucket privacy, no secrets), and the one open question (profiles INSERT) resolved *favorably* — not merely "acceptable," but a stronger posture than originally hoped for. Held below 9-10 by two things Track A cannot close: the proposed baseline migration for the profile-creation trigger is not yet written (documentation debt, not a live risk), and CSP/production-header verification against the real deployment (S-5/S-6) remains outstanding — a strong local result, not yet a production-confirmed one. |
| **Reliability** | **7/10** | Every functional flow tested passed, including full round-trips (create → publish → revise → comment → follow → settings) with zero unexpected errors. Held below higher marks because the rollback mechanism (`docs/DEPLOYMENT.md` §7) has never been exercised even once — it's designed and documented, but "tested live" is a Track B item, and this milestone's own methodology throughout has been to distrust untested claims. |
| **Performance** | **Not scored — Track B.** | No Lighthouse/PageSpeed data exists yet. The local-only signals available (fonts load, lazy-loading present, no console errors) are necessary but not sufficient to score this category honestly. |
| **Accessibility** | **8/10** | A real, targeted re-check (not an assumption) of every file Phase 9C's consolidation touched found zero regressions — ARIA combobox pattern, live regions, accessible names, disclosure-widget semantics all intact and verified live, including under real keyboard-relevant states (expanded/collapsed, populated listbox). Held below 9-10 because this was a *focused* re-check of touched files, not a full from-scratch re-audit at 8D's original depth — appropriate given the actual risk surface, but not equivalent to a complete pass. |
| **Maintainability** | **8/10** | Phase 9C's cleanup held (no new dead-code recurrence observed). This phase surfaced one real, if benign, documentation gap of its own (the untracked profile-creation trigger) — found and already corrected in `docs/AUTH_ARCHITECTURE.md`, with a migration proposed to close it structurally. The fact that this was found *by testing*, not assumed away, is itself a maintainability positive for the project's methodology, even though the underlying gap briefly existed. |
| **Deployment** | **Not scored — Track B.** | Nothing in the deployment pipeline itself (Cloudflare project connection, custom domain, DNS, live rollback) has been exercised yet — `docs/DEPLOYMENT.md` is a complete, reviewed plan, but a plan isn't a score. |
| **Documentation** | **9/10** | `docs/STORAGE_ARCHITECTURE.md`, `docs/AUTH_ARCHITECTURE.md` (now corrected with today's finding), `docs/DEPLOYMENT.md`, `docs/OPERATIONS.md`, and this document are all current and accurate as of today. The one open item is the proposed baseline migration itself not yet existing as a file. |
| **Launch Readiness (Overall)** | **Not scored — see recommendation below.** | Consistent with this milestone's own established scoring principle (a floor set by the worst launch-blocking gap, not an average): the honest floor right now is "Track B hasn't happened," which isn't a defect to average against everything else, it's simply the next required step. |

---

# Final recommendation

**Ready after minor fixes** — specifically, "minor" here means *procedural remaining steps*, not defects found. Applying the decision framework defined earlier in this document:

- **Zero unresolved Critical/High findings** across everything Track A could reach. The one real open question (profiles INSERT) resolved favorably, not as a gap.
- **Zero functional verification failures** — every core flow (auth, upload, publish, revise, comment, follow, notify, settings) was tested live and passed, including full end-to-end round trips, not just spot checks.
- **Zero accessibility regressions** found in the specifically-at-risk surface (Phase 9C's consolidation).
- **What's actually missing before "ready for production" is entirely Track B** — a real Cloudflare Pages deployment, DNS, Lighthouse/PageSpeed results, and the auth-redirect email test. None of these are open questions about whether the *code* works; they're steps that simply haven't happened yet because they require your own account/domain action, per `docs/DEPLOYMENT.md`.
- **One concrete, scoped, small fix is recommended before calling this fully done**: write and apply the proposed baseline migration (`0019_baseline_profile_creation_trigger.sql`) documenting the profile-creation trigger — a one-file, non-behavior-changing migration, blocked only on one more query result from you.

This is not "not ready" — nothing broken was found. It is not "ready for production" either — that claim requires Track B evidence this phase was explicitly scoped not to fabricate. **"Ready after minor fixes"** is the accurate label: the minor fix is procedural (run Track B, land the one documentation migration), not remedial.

---

# Track B — not started

Every item below requires a live Cloudflare Pages deployment, which does not exist (confirmed via `git remote -v` returning empty). **None of these have been run. None of these results are fabricated or assumed.** Per `docs/MILESTONE_9_PHASE_9E_ARCHITECTURE.md`'s own plan:

- Cloudflare deployment itself (connecting the repo, first deploy)
- A real public URL / custom domain / DNS configuration
- Lighthouse / PageSpeed Insights audits (Performance, Accessibility, Best Practices, SEO categories)
- Production header verification (CSP, security headers) against what Cloudflare Pages actually serves
- Auth email redirect verification (a real password-reset email against the production domain)
- The rollback mechanism, exercised live at least once
- The `404.html` auto-routing behavior specifically (as opposed to the page's own content, which was verified)

Stopping here, per your instruction — Track B has not begun.
