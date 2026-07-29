# Specbound Terminology

Status: Authoritative. Approved 2026-07-28.

This document exists because five earlier docs each used different names for the same things. This is the one that wins.

---

# Official Product Language

Use these terms everywhere in visible product copy, documentation, and — for all new code — variable, component, and file names.

| Term | Meaning |
|---|---|
| Builder | Someone creating work on Specbound. Not "user." |
| Project | A living engineering record of something a builder is making. Not "content item," not "Blueprint." |
| Build Log | One documented step in a project: what changed, why, what happened, what's next. Not "post," not "progress entry," not "Revision." |
| Workshop | The builder's home screen — what to continue, what's recent, what's stalled. Not "dashboard." |
| Builder Archive | A builder's public page: their projects and history. Not "profile" in casual copy (the underlying page/route may still be named profile — see Deprecated Terms below). |
| Build Timeline | The chronological sequence of Build Logs on a project. Not "feed." |
| Version | An internal, permanent milestone in a project's history. |
| Release | A major, public milestone in a project's history. |

Do not invent replacement terminology without approval.

---

# Deprecated Terms

These terms are retired from product copy and documentation, effective immediately. They are **not** retired from the database or existing code yet — see Migration Status below.

| Old term | New term | Still lives in code/DB as |
|---|---|---|
| Blueprint | Project | `builds` table, `project_drafts` table, `BlueprintCard.js`, `BlueprintFeed.js`, page title "Blueprint \| Specbound" |
| Revision | Build Log | `build_revisions` table, `renderTimeline.js`, UI copy ("Start Your Project Log") |
| Dashboard | Workshop | Resolved (Milestone 15, 2026-07-29) — `pages/dashboard.html` removed; its one piece of unique functionality (Builds/Build Logs/Completed stats) ported into Workshop |
| Profile / Creator | Builder Archive / Builder | `profiles` table, `profileRepository.js`, "Creator Profile" page title |
| Activity Feed | Build Timeline | `activityRepository.js`, `renderActivityFeed.js` |

---

# Migration Status

Per the approved decision: **do not rename database tables, columns, or existing code identifiers as a side effect of this document.** Renaming a table or a widely-imported component is a real migration with real risk (broken imports, broken RLS policy references, broken foreign keys) — it needs its own proposal, reviewed on its own, separately from a documentation pass.

What changes now (Milestone 11A, documentation only):
- This document exists and is authoritative.
- New product copy, new documentation, and new code going forward should use the new terms.

What's deferred to a future, separately-approved migration:
- Renaming `builds`/`project_drafts`/`build_revisions` tables or columns.
- Renaming `BlueprintCard.js`, `BlueprintFeed.js`, and other existing components.
- Rewriting existing UI copy ("Blueprint | Specbound" page titles, "Revision" labels) — this is a real, visible product-copy pass and should be scoped and executed deliberately, not silently bundled into an unrelated change.

Until that migration happens, code comments and internal names referencing "Blueprint" or "Revision" are not bugs — they're known, tracked debt, tracked here.

---

# Related Documents

- `VISION.md` — what these words are in service of
- `PRODUCT_ARCHITECTURE.md` — the terms applied to actual pages, systems, and features
