# Specbound Version 1 Scope

Status: Authoritative. Approved 2026-07-28.

This is the canonical list of what's in and out of Version 1. If a future changelog entry needs to justify removing or rejecting a feature, cite this document.

(A prior version of this project apparently had a similar document — referenced in `CHANGELOG.md`'s Milestone 3 entry as a "canonical spec['s] prohibited-features list" — that no longer exists anywhere in this repository. This document is its replacement. If the original is ever recovered, reconcile the two; until then, this one governs.)

---

# The One Workflow

Version 1 focuses on one workflow:

Create Project → Add Build Logs → Track Progress → Finish or Archive → Revisit Later

---

# Required Product Areas

1. **Authentication** — sign up, sign in, sign out, email confirmation, password recovery
2. **Builder identity** — username, Builder Archive, projects, archive
3. **Projects** — create, read, edit, archive and restore, cover image, description, category, status, progress
4. **Build Logs** — create, edit, draft safety, photos, chronological timeline
5. **Workshop** — continue the most relevant project, recent work, clear next action
6. **Search** — projects, builders, categories, tags
7. **Settings** — profile, password, preferences

See the implementation report (2026-07-28) for the current status of each — as of that review, password recovery and password change are the two gaps.

---

# Community Features — Approved for V1

Specbound is not a social-media platform. Community features exist to support project improvement, not popularity.

Approved:
- **Project-focused comments and feedback**
- **Following builders or projects**
- **Meaningful notifications**

The Workshop must remain focused on continuing work, not consuming social content — community features are a supporting layer, never the home screen.

---

# Explicitly Out of Scope for Version 1

- direct messaging
- organizations
- marketplace
- streaks
- XP or levels
- engagement-based achievements
- AI-authored documentation
- mobile applications
- plugins
- public API
- live streaming
- stories
- infinite scrolling
- real-time collaborative cursors
- **likes**
- **popularity rankings**
- **engagement-first activity feeds**
- **vanity counters**
- **gamification**

Nothing above is approved unless explicitly re-approved in writing.

---

# Known Gap: Existing Features Ahead of This Decision

Some non-approved features already exist in the live schema and UI, predating this document: `likes` (a table and UI), and an "Activity Feed" homepage section that currently behaves as an engagement feed rather than a Build Timeline.

This document does not order their removal. Per the approved decision: **do not delete social tables yet unless they are completely unused.** The next step is a dependency review — identify every place `likes` and the current activity-feed behavior are read or written — followed by a proposed dormancy or removal plan, presented for approval before any deletion. Until that review happens, their existence is a tracked gap against this document, not a contradiction of it.

---

# Every Feature Must Answer

Does this help someone preserve their engineering journey?

If not, it probably doesn't belong in Specbound. See `PRODUCT_PRINCIPLES.md`.

---

# Related Documents

- `VISION.md` — why these boundaries exist
- `PRODUCT_PRINCIPLES.md` — the belief system behind the avoid-list
- `PRODUCT_ARCHITECTURE.md` — how approved scope maps to systems and pages
- `ROADMAP.md` — the milestone plan that acts on this scope
