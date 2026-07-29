# Specbound Product Architecture

Status: Authoritative, living document. Approved 2026-07-28.

This document is meant to stay current — update it when a system's scope actually changes, not just when a milestone finishes. It replaces the prior version of this document (previously "10-Product-Architecture.md"), which used "Blueprint" as the central object, framed Marketplace and a Discord-integrated Community/Forums system as near-term systems, and listed Followers/Achievements together under one Creator System — all superseded by the terminology and scope decisions below.

---

# Core Philosophy

Specbound is built around one central object: the **Project**.

Everything on the platform exists to help builders create, improve, discover, and learn from projects.

See `VISION.md` for the full philosophy and `TERMINOLOGY.md` for why "Project," not "Blueprint."

---

# The V1 Loop

Create Project → Add Build Logs → Track Progress → Finish or Archive → Revisit Later.

Every system below either drives this loop directly or supports it. Nothing on this page is exempt from that test — see `VISION.md`'s Final Quality Test.

---

# Product Systems

## 1. Discovery System

**Purpose:** help builders discover projects.

**Pages:** Home, Explore, Search, Categories.

**V1 features:** Trending, Recently Updated, Featured Projects, Featured Builders, Filters.

**Future, not approved for V1:** AI Search, Personalized Feed, Collections, Recommendations. (AI search is explicitly out of scope per `SCOPE.md`; a personalized feed needs to be designed carefully against the "not a social feed" principle before it's ever proposed.)

---

## 2. Project System

**Purpose:** document a technology project from idea to archive.

**Pages:** Project (a single project's page).

**V1 features:** Overview, Components, Gallery, Build Log timeline, Versions.

**Future, not approved for V1:** Releases as a distinct public-milestone concept beyond Version, Forks, Downloads, Guides, Benchmarks, Compatibility checking, AI Assistant.

A builder should understand a project's current state within 30 seconds of landing on its page.

---

## 3. Builder Archive System

**Purpose:** show a builder's work and history.

**Pages:** Builder Archive (the page currently implemented as `profile.html` — see `TERMINOLOGY.md`).

**V1 features:** Portfolio (published projects), social account links, following.

**Not approved for V1** (per `SCOPE.md`): Achievements, popularity statistics, follower-count-as-status-symbol framing. Follower relationships are functional (so a builder can see who's following whom and route notifications), not a leaderboard.

**Future:** Builder verification, premium portfolio options, Creator Collections.

---

## 4. Workshop System

**Purpose:** the builder's home screen — what to continue, not what to consume.

**Pages:** Workshop, Upload (project creation).

**V1 features:** Drafts, My Projects, meaningful notifications.

The Workshop answers one question: *what should I continue building?* It prioritizes the most relevant unfinished project, the current goal, draft Build Logs, recent work, and stalled projects that need attention. It must never become an analytics-heavy dashboard or a social feed — see `VISION.md` and `SCOPE.md`.

**Not approved for V1:** engagement analytics, vanity metrics.

**Future:** Team Workspaces, Scheduled Publishing.

`pages/dashboard.html` was never a separate system — it was removed in Milestone 15 (2026-07-29). Its one piece of functionality Workshop didn't already have (a Builds/Build Logs/Completed stats row) was ported in first; everything else it did, Workshop already did better (Continue, Drafts, Saved, Quick Actions all had no Dashboard equivalent).

---

## 5. Feedback & Connection System

**Purpose:** support project improvement through feedback and following — not popularity. (Renamed from "Community System" — the old name implied a broader social surface than what's approved.)

**Pages:** none dedicated; comments and follow relationships surface inline on Project and Builder Archive pages.

**V1 features (all three explicitly approved in `SCOPE.md`):**
- Project-focused comments and feedback
- Following builders or projects
- Meaningful notifications

**Explicitly not approved for V1** (per `SCOPE.md`): likes, popularity rankings, engagement-first activity feeds, vanity counters, infinite scrolling, gamification, forums, Discord integration, challenges, Q&A.

The existing `likes` table and the current homepage "Activity Feed" section predate this decision — see `SCOPE.md`'s Known Gap section for the dependency-review plan, not addressed by this document.

---

## 6. Marketplace System — not approved for V1

Explicitly out of scope per the master prompt and `SCOPE.md`. Recorded here so the idea isn't lost, not because it's planned. If ever revisited, it needs its own scope proposal.

---

## 7. Intelligence System — not approved for V1

AI-authored documentation and AI-driven features are explicitly out of scope per `SCOPE.md`. `docs/AI.md` is the placeholder for if/when this changes. Recorded here so the idea isn't lost, not because it's planned.

---

# Builder Flow

Sign Up → Create Builder Archive → Publish Project → Add Build Logs → Gain Followers → Continue Building.

(Previously included "Publish Guides" and "Become Featured Creator" — both removed: Guides aren't V1 scope, and "Featured Creator" status read as a popularity mechanic inconsistent with `PRODUCT_PRINCIPLES.md`.)

---

# North Star

Every feature must help someone start building, continue building, learn, improve, remember, or share meaningful work. See `VISION.md`.

---

# Related Documents

- `VISION.md` — the philosophy this architecture implements
- `TERMINOLOGY.md` — the words used above
- `SCOPE.md` — the authoritative in/out list this document must stay consistent with
- `PARKING_LOT.md` — ideas not yet on any system's roadmap
