# Milestone 9 — Phase 9E: Final Launch Verification — Architecture Proposal

**Status: Architecture only. No implementation. Awaiting approval.**

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

Stopping here for review, per your instructions — no implementation performed.
