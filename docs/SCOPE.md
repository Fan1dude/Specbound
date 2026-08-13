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
- **Discord account linking** — an optional, builder-controlled identity connection (Settings, Builder Archive), not a forums/chat integration. Approved 2026-08-12, shipped as part of Milestone 22.
- **Likes, as lightweight appreciation only** — a single low-friction signal of "I saw this and it mattered," not a ranking input, not surfaced as a leaderboard or popularity statistic anywhere. Approved 2026-08-12, formally reversing this document's prior blanket "likes" prohibition below.
- **Activity Feed, redefined around meaningful builder activity** — project milestones, publishes, and comparable build-log progress, not raw engagement counts (likes/views) and not an algorithmic ranking. Approved 2026-08-12, formally reversing this document's prior "engagement-first activity feeds" prohibition below for this specific, redefined shape only — an engagement-ranked feed remains out of scope.
- **Content moderation** — user-submitted reports (Milestone 22) and a moderator-only review queue to act on them (Milestone 24, `pages/moderation.html`). Resolving a report records a decision only; it does not itself unpublish or delete content, suspend an account, or notify anyone beyond the reporter that a decision was made.

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
- **popularity rankings** (leaderboards, "top builder" framing, follower count as status)
- **engagement-first activity feeds** (ranked by like/view counts rather than by meaningful activity — see the redefined Activity Feed under Community Features above, which is the approved exception)
- **vanity counters** (raw counts displayed as a status symbol, e.g. a public follower-count leaderboard)
- **gamification** (streaks, XP, badges-as-status)

`likes` was removed from this list on 2026-08-12 — see Community Features above; it remains approved only as a lightweight appreciation signal, never as a ranking input or a displayed popularity statistic.

Nothing above is approved unless explicitly re-approved in writing.

---

# Resolved: Likes and Activity Feed (formerly "Known Gap")

As of 2026-08-12, `likes` and the homepage Activity Feed are formally approved (see Community Features above) — not merely tolerated pre-existing features. This section previously flagged them as predating this document with their removal or dormancy still open; that review concluded in favor of keeping both, redefined: likes stay a lightweight appreciation signal, and the Activity Feed is redefined around meaningful builder activity (project milestones, publishes, build-log progress) rather than raw engagement counts. Any future work that makes the Activity Feed read as an engagement-ranked or like/view-count-sorted feed is a regression against this decision, not a continuation of it.

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
