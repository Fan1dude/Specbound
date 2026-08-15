# Specbound Roadmap

Status: Authoritative. Approved 2026-07-28. Supersedes the prior version of this document — its "UI 2.0" section had already shipped as Milestone 10, and its "Community" section (Comments, Bookmarks, Notifications) had already shipped as earlier milestones, ahead of what that version tracked.

This is a live pointer to the approved milestone plan, not a third copy of it. Detailed objectives, files, risks, dependencies, and acceptance criteria for each milestone live in the implementation report (2026-07-28) and, as each milestone executes, in its own architecture doc under `docs/milestones/`.

---

# Approved Order

| Milestone | Objective | Status |
|---|---|---|
| 11A | Foundation reset — vision, terminology, brand, and scope documentation | Complete |
| 11B | Fix the confirmed `record_build_view()` database bug | Complete — 3 private-build cases implementation-reviewed only, not live-verified (see commit) |
| 12 | Authentication completeness — password recovery, password change | Complete |
| 13 | Database correctness — resolve `ensureProfile()`'s dead fallback, resolve the empty top-level SQL files | Complete for Version 1 — trigger formalization split out below, not blocking |
| 14 | Brand implementation — roll out the approved palette and logo, recheck WCAG AA | Complete |
| 15 | Workshop/Dashboard resolution — merge any unique Dashboard functionality into Workshop, remove the orphaned page | Complete |
| 16 | Documentation and changelog completion — backfill Milestones 5–10 | Complete |
| 17 | Minimal CI and automated test execution | Complete |
| 18 | Formal WCAG 2.1 AA accessibility audit | Complete |
| 19 | Structured parts catalog, moderated submissions, paste-list import, and affiliate-link schema | Complete — merged to main |
| 20 | Builder Portfolio — redefined public profile page | Complete — merged to main |
| 21 | First-time builder experience — Welcome dialog, onboarding, contextual editor hints | Complete — merged to main |
| 22 | Community foundation — Discord linking, roles, reporting, feedback, beta invites, Community Guidelines | Complete — merged to main |
| 23 | Setup Inventory, scoped search, builder dates | Complete — merged to main, deployed to production |
| 24 | Moderator Report Queue — moderator-facing interface for content reports filed since Milestone 22 | Complete — see `docs/milestones/MILESTONE_24_MODERATOR_REPORT_QUEUE_SPECIFICATION.md`; merged and deployed to production |
| 25 | Follow Notifications — notify a builder when someone follows them | Complete — see `docs/milestones/MILESTONE_25_FOLLOW_NOTIFICATIONS_SPECIFICATION.md`; merged and deployed to production, including the follow-up security-hardening migration `0038` |
| 26 | Feedback Review — moderator/staff feedback triage workflow and a submitter-facing My Feedback page | Complete — see `docs/milestones/MILESTONE_26_FEEDBACK_REVIEW_SPECIFICATION.md`; merged and deployed to production (migration `0039`), including a same-week signed-out login-redirect hotfix |
| 27A | Launch Readiness, engineering track (PR1 signup posture, PR2 DB hardening, PR3 security headers/SEO, PR4 operator documentation, PR5 accessibility/performance) | PR2 (migrations `0040`/`0041`) and PR3 (Stage 1 HSTS, security-header CI check, crawl/noindex fix) complete, merged, and deployed to production. PR4 (this entry) is documentation-only — no production operation. PR1 is blocked pending 27B (public signup stays held until then). PR5 not started. |
| 27B | Launch Readiness, legal/policy track — Terms of Service, Privacy Policy, age rules, cookie disclosure, adult-owner review | Not started. Public signup remains held until 27B's legal placeholders are resolved; those placeholders are the current launch blocker. |

---

# Backlog (not part of the numbered sequence, not blocking)

| Item | Objective | Status |
|---|---|---|
| Verify baseline reconstruction against real production schema | `0000_baseline_pre_tracked_tables.sql` (2026-08-01) reconstructs `profiles`, `builds`, `build_revisions`, and the signup trigger from evidence in tracked migrations and application code, closing the "can't bootstrap a fresh project" problem. It is not a captured, verified-identical copy of the real production database's definitions — that still requires a one-time, read-only introspection query (`pg_get_triggerdef()`/`pg_get_functiondef()`, see `docs/DATABASE.md`'s Known Gap section and the Milestone 13 implementation report, 2026-07-28) run manually against the live project. | Narrowed, not closed — blocked on that query being run manually against the live database; picked up whenever that output is available, no deadline. |
| Component-submission anti-spam beyond the per-account cap | Migration `0022_component_submissions.sql` caps pending submissions at 20 per account — a real but minimal safeguard. It does nothing against multi-account abuse (one bad actor spreading submissions across several accounts to stay under the cap on each), slow-drip low-quality submissions that never breach the cap, or any CAPTCHA/rate-limit at the HTTP layer. **Tracked launch blocker for public beta** — revisit before opening catalog submissions to the general public, not just signed-in testers. See `docs/milestones/MILESTONE_19_SQL_SECURITY_AUDIT.md` §5. | Not started — no deadline, but flagged as blocking public (as opposed to invite/testing-scope) beta specifically. |
| Recoverable project Trash | Right now, unpublishing a project is the only way to take it out of public view — there is no delete of any kind (confirmed by code search during the post-M23 maintenance pass: no delete-project/delete-draft repository function exists anywhere). A real Trash system would need: moving a project to Trash; hiding it from public/search/profile/Workshop views while trashed; restoring it from Trash; permanently deleting it with strong (e.g. type-to-confirm) confirmation; safely cleaning up its associated revisions and uploaded storage files on permanent delete; and enforcing owner-only access to all of the above (never another user, never a moderator by default). Explicitly **not** V1 scope — flagged here rather than built during that maintenance pass. | Not started — no deadline. |

---

# Related Documents

- `SCOPE.md` — what this roadmap is building toward
- `PARKING_LOT.md` — ideas that are not on this roadmap
