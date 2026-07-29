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
| 13 | Database correctness — formalize the `profiles` trigger, resolve `ensureProfile()`'s dead fallback, resolve the empty top-level SQL files | Partial — fallback and empty files resolved; trigger formalization blocked on a manual introspection query (see implementation report) |
| 14 | Brand implementation — roll out the approved palette and logo, recheck WCAG AA | Not started |
| 15 | Workshop/Dashboard resolution — merge any unique Dashboard functionality into Workshop, remove the orphaned page | Not started |
| 16 | Documentation and changelog completion — backfill Milestones 5–10 | Not started |
| 17 | Minimal CI and automated test execution | Not started |
| 18 | Formal WCAG 2.1 AA accessibility audit | Not started |

---

# Related Documents

- `SCOPE.md` — what this roadmap is building toward
- `PARKING_LOT.md` — ideas that are not on this roadmap
