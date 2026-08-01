# Milestone 20: Builder Portfolio Specification

Status: **Approved.** 2026-08-01. All decisions in §3.3, §11, §10.3, and §15 are final — see §15 for the closed checklist and §20 for the final-decisions addendum. Implementation is proceeding in the phases defined in §19, in the logical-commit groups listed there.

Goal: redesign `pages/profile.html` so a Specbound profile can fully replace a builder's personal portfolio website — designed like **GitHub + Behance**, not Instagram. Minimal, premium, focused on craftsmanship. Uses only the existing, settled design system (`css/base/tokens.css`) — no new colors are introduced.

---

## 1. Design Position

**GitHub, borrowed:** information-dense but calm identity block; quiet numeric stats, not oversized dashboard tiles; a real chronological activity record instead of a static "about me"; project list treated as a working body of output, not a highlight reel.

**Behance, borrowed:** one project gets outsized visual treatment as the entry point into the builder's best work; image-forward project cards with generous whitespace; a narrative "About" section that reads like an artist statement, not a form dump.

**Instagram, explicitly rejected:** no square-grid-as-the-whole-page; no follower/like count treated as the hero element; no infinite scroll; no cover-photo-as-mood-board banner. Per `docs/BRAND.md`'s own decision test — "does it keep the builder's work as the hero?" — engagement chrome stays quiet and the projects stay loud.

This page sits on the existing frozen `.page-foundation` dark-workspace background (`css/base/foundation.css`) like every other page. Nothing here changes that background; all new surfaces use the existing `--surface-card` / `--surface-raised` / `--surface-input` elevation tokens.

---

## 2. Section Ordering (confirmed, as specified)

1. Hero
2. Builder Overview
3. Featured Project
4. Project Gallery
5. Technology Breakdown
6. Builder Journey
7. About Builder
8. Footer (existing global footer, reused as-is — no bespoke portfolio footer)

Sections 3–6 are conditionally rendered — see §7 Empty States. Sections 1, 2, 7, 8 always render (a profile always has an identity, even with zero projects).

---

## 3. Data Requirements

### 3.1 Existing data — sufficient for most of the page

| Section | Source | Columns used |
|---|---|---|
| Hero | `profiles` | `username`, `display_name`, `bio`, `location`, `website`, `github`, `youtube`, `avatar_url`/`avatar_path`, `created_at` |
| Builder Overview | `profiles`, `builds` (aggregate) | `followers_count`, `following_count`, count of published `builds`, sum of `views` |
| Featured Project | `builds` (one row, selected — see 3.3) | `title`, `slug`, `description`, `image_url`, `specifications`, `category`, `likes_count`, `views` |
| Project Gallery | `builds` (all published, minus Featured) | same as `BlueprintCard` already consumes today |
| Technology Breakdown | `builds.category` (client aggregation) | count per category, matched to `js/config/technologies/*.js` |
| About Builder | `profiles.bio` | see 3.3 for the headline/bio split decision |

### 3.2 New data required — Builder Journey (revised per decision, see §3.3d)

`build_revisions` has no existing cross-project aggregation (today's timeline rendering, `renderTimeline.js`, is scoped to one build). Builder Journey needs the builder's recent revisions across *all* their public projects, but per §3.3(d) it must not show every revision — the raw feed is fetched once and then filtered/synthesized into a small set of meaningful events. See §17.3 for the exact fetch and §17.4 for the pure event-synthesis function. Additive only — no schema change.

### 3.3 Data-model decisions — resolved 2026-08-01

**(a) Hero tagline vs. About narrative — decided: separate field.**
Add a new optional `profiles.headline` column, capped at 120 characters, for the Hero. The existing `bio` column remains the longer About Builder narrative. Both are independently optional — the portfolio must render correctly with either, both, or neither present (see §7 for the exact empty-state text per combination). Schema in §16.

**(b) Featured Project selection — decided: builder-controlled, no likes-based ranking.**
Add a new optional `profiles.featured_build_id` column, referencing one of the builder's own `builds` rows. The builder picks it explicitly (Settings UI, §19 Phase 6) — `likes_count` is never used as a selection signal. Resolution order at render time:
1. `featured_build_id`, if set **and** still one of the builder's own **public** builds (a pin can go stale if the build is later made private or deleted — `on delete set null` handles deletion at the DB level; visibility staleness is handled by the read-path fallback in §17.2, not by re-validating on every write).
2. Otherwise, the most recently updated build with `status = 'completed'`.
3. Otherwise, the most recently updated build with `visibility = 'public'` (any status).
4. Otherwise, the section is omitted (no public builds exist at all).

Database-level enforcement: `featured_build_id`, when set, must reference a build owned by the same profile — enforced by a trigger (§16), since RLS alone can't express a cross-row "same owner" constraint. It does **not** enforce visibility at write time (a builder may pin a build they're still finishing) — only ownership is a security boundary; visibility eligibility is re-checked every time the page renders.

**(c) Technology Breakdown accent colors** — unchanged from the first draft, not actually in question: `js/config/technologies/*.js` accents (`#4F7DFF` pc_build, `#9B6CFF` setup, `#32D583` arduino, `#FF8A3D` robotics, `#22C7E8` homelab, `#EC5FA7` 3d_printer) are already an approved, shipped part of the system (category pages/`technology-card.css`). Reusing them for a proportion bar is existing precedent, not a new color introduction.

**(d) Builder Journey scope — decided: curated milestones, not a raw revision feed.**
V1 shows the latest **10** events (within the approved 8–12 range), synthesized from four sources, all derived from data that already exists — no new columns:
- **Published** — one event per public build, dated `builds.created_at` (the moment `publish_draft()` inserts the row — the closest available proxy to a true "published at" timestamp; there is no separate one).
- **Completed** — one event per build with `status = 'completed'`, dated `builds.updated_at` (best available proxy — there's no dedicated `completed_at` column or a status-change history log, so this is the row's last-modified time, not necessarily the exact moment it flipped to completed; flagged as a known approximation, not a defect to fix here).
- **Milestone revisions** — any `build_revisions` row with `milestone = true`, dated `created_at`. This reuses a flag builders already set themselves when logging an update, so it's the most direct "the builder called this a big deal" signal available, not an invented heuristic.
- **First build in a category** — per distinct `builds.category` value among the builder's public builds, the earliest one by `created_at`.
- **Major version releases** — `build_revisions.version` is freeform text (e.g. `"v1.0"`, `"2.3"`, `"v0.1"`), not a structured field, so this is necessarily a best-effort pattern match, not authoritative parsing: a revision counts if its trimmed `version` matches `/^v?\d+\.0$/i` (e.g. matches `"v1.0"`, `"2.0"`; does not match `"v1.2"`, `"1.0.1"`, or non-numeric text). Because this only decides what surfaces in a highlight list — never what gets written or persisted — an occasional under- or over-match is low-stakes, unlike the parts-catalog import work where mismatches had to be caught before persisting.

If fewer than 10 qualifying events exist, show however many exist (down to 1). If zero exist, the section is omitted — same "don't render an empty shell" rule as every other conditional section (§7).

---

## 4. Layout

### 4.1 Desktop (≥1024px, primary target — this is a "sit down and read" page)

Single centered column, `max-width: 1120px` (matches existing `.profile-page` container convention), generous vertical rhythm between sections (`--space-9`, 96px, between major sections; tighter `--space-6`/`--space-7` within a section).

```
┌─────────────────────────────────────────────┐
│  HERO                                        │
│  [avatar]  Display Name  ⋅ @username         │
│            headline                          │
│            📍 location  🔗 links  · joined   │
│            [ Follow ]                        │
├─────────────────────────────────────────────┤
│  BUILDER OVERVIEW  (quiet stat strip)        │
│  12 Projects · 340 Followers · 48K Views     │
│  Primarily building: [PC Builds] [Home Labs] │
├─────────────────────────────────────────────┤
│  FEATURED PROJECT          "Featured" badge  │
│  ┌───────────────────────────────────────┐   │
│  │         large cover image (21:9)       │   │
│  └───────────────────────────────────────┘   │
│  Title · short description · key specs        │
│  [ View Project → ]                          │
├─────────────────────────────────────────────┤
│  PROJECT GALLERY          [filter] [sort ▾]  │
│  ┌───────┐ ┌───────┐ ┌───────┐               │
│  │ card  │ │ card  │ │ card  │  (3-col grid) │
│  └───────┘ └───────┘ └───────┘               │
│  ┌───────┐ ┌───────┐ ┌───────┐               │
│  │ card  │ │ card  │ │ card  │               │
│  └───────┘ └───────┘ └───────┘               │
│              [ Load more ]                   │
├─────────────────────────────────────────────┤
│  TECHNOLOGY BREAKDOWN                        │
│  ▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░ (proportion bar) │
│  ● PC Builds 45%  ● Home Labs 30%  ● ...     │
├─────────────────────────────────────────────┤
│  BUILDER JOURNEY                             │
│  │ Aug 2026 — Reached v1.0 on Project X       │
│  │ Jul 2026 — Milestone: upgraded cooling     │
│  │ Jun 2026 — Completed Home Lab Server       │
│  │              (10 curated events, no        │
│  │               "view full history" — V1     │
│  │               shows a fixed top-10 list)   │
├─────────────────────────────────────────────┤
│  ABOUT BUILDER                               │
│  full narrative bio · links repeated         │
├─────────────────────────────────────────────┤
│  FOOTER (existing, global)                   │
└─────────────────────────────────────────────┘
```

Hero identity block is left-aligned (avatar + text side by side), not centered — centered identity blocks read as a landing page, not a workspace; left alignment matches GitHub and keeps scanning fast.

### 4.2 Tablet (600–1023px)

Same section order. Project Gallery drops to 2 columns. Hero stays side-by-side (avatar + text) down to ~640px, then stacks (avatar above text, both centered-left) below that. Technology Breakdown proportion bar and legend stack vertically instead of bar-above-legend-row. Builder Journey timeline rail stays left-aligned, unchanged.

### 4.3 Mobile (<600px)

- Hero: avatar (96px) above name/username/headline, all left-aligned (not centered — avoids the "app onboarding screen" feel). Links wrap to their own row as a horizontal scroll-free wrapped list. Follow button becomes full-width.
- Builder Overview: stat strip wraps to 2 lines instead of horizontal scroll; technology chips wrap.
- Featured Project: image aspect ratio changes from 21:9 to 16:9 so the crop doesn't get too shallow at narrow widths.
- Project Gallery: single column, filter bar becomes a horizontally-scrollable chip row (existing Explore pattern, reused).
- Technology Breakdown: bar stays full-width; legend becomes a 2-column list.
- Builder Journey: timeline rail indent reduces; entry dates move above each entry instead of inline, to avoid cramped wrapping.
- About Builder: unchanged structurally, just narrower measure.

No content is hidden at any breakpoint — everything present on desktop is present on mobile, just reflowed. Consistent with the rest of the site's responsive convention (confirmed against `profile.css`'s existing breakpoint behavior).

---

## 5. Spacing System

Uses the existing 8px-based scale from `tokens.css` — no new values introduced.

- Between major page sections: `--space-9` (96px) desktop, `--space-7` (56px) mobile.
- Within a section, heading-to-content: `--space-5` (32px).
- Card/grid gutters (Project Gallery): `--space-5` (32px) desktop, `--space-4` (24px) mobile — matches existing `BlueprintFeed` grid gap.
- Hero internal spacing (avatar-to-text gap, line spacing within identity block): `--space-4`/`--space-3`.
- Builder Journey timeline entry spacing: `--space-5` between entries, `--space-2` between an entry's date/title/body internally.

---

## 6. Typography Hierarchy

Uses the existing type scale — no new sizes.

| Element | Token/size | Weight |
|---|---|---|
| Hero display name | H1 scale (existing hero H1 pattern, but reduced from the current `clamp(3rem, 7vw, 5.5rem)` — see §11) | 600 |
| Hero headline/tagline | Body-large | 400 |
| Section headings (Featured Project, Project Gallery, etc.) | H3 scale | 600 |
| Builder Overview stat numbers | H4/Body-large-strong, **not** the current oversized 2.5rem — deliberately quieter, see §11 | 600 |
| Builder Overview stat labels | Small, `--color-text-secondary` | 400 |
| Project card titles | existing `BlueprintCard` title scale (unchanged) | 600 |
| Builder Journey entry title | Body | 500 |
| Builder Journey entry date | Small, `--color-text-muted`, monospace-adjacent if the system defines one (else Small default) | 400 |
| About Builder body | Body-large, generous line-height for long-form reading | 400 |

---

## 7. Empty States

Empty states must never look broken — each is a deliberate, on-brand message, not a blank gap.

- **Zero published projects (whole-profile empty state) — final:** Featured Project, Project Gallery, Technology Breakdown, and Builder Journey are all omitted entirely (not shown empty) if a builder has zero public projects — the page becomes Hero → Builder Overview (0 projects, real number) → About Builder → Footer. Builder Overview's "0 Projects" stat is truthful, not hidden. If the visitor is the profile owner, a quiet inline message replaces the missing sections: "Your published projects will show up here." with a **"Publish Your First Build"** button linking to `../upload.html` — the site's existing Publish flow entry point (the same page linked as "Upload Project" from Workshop), not the editor directly, since the editor is reached by first starting a publish/draft flow, not visited standalone. If the visitor is anyone else, the message is omitted with no CTA (nothing for another visitor to do here).
- **Featured Project specifically, with ≥1 project but the top pick has no cover image:** falls back to the existing `BlueprintCard` placeholder-image treatment already used elsewhere, scaled to the larger Featured aspect ratio.
- **Technology Breakdown with only 1 category represented:** bar renders as a single full-width segment — still valid, not a degenerate case needing special-casing.
- **Builder Journey with projects but zero qualifying events** (no milestones, no completed builds, no major-version revisions — just routine documentation updates): section is omitted (same "don't show an empty rendered shell" rule) rather than showing an empty timeline rail.
- **About Builder with no bio text written:** if visitor is the profile owner, quiet inline prompt ("Add a bio to tell people about your work" linking to Settings — reuses existing Settings link pattern). If visitor is anyone else, section is omitted entirely rather than showing empty white space.
- **No location/website/github/youtube set:** each link/meta item is independently optional and simply omitted from the Hero meta row — this already matches current `renderLinks`/`LINK_FIELDS` behavior in `renderProfile.js`, unchanged.

---

## 8. Loading Skeletons

Reuses the existing `css/components/skeleton.css` composable primitives — no new skeleton pieces needed structurally, only new compositions assembled in `js/utils/skeletons.js`:

- **Hero skeleton:** `.skeleton-avatar-lg` + stacked `.skeleton-title` + two `.skeleton-text` lines + a pill-shaped skeleton for the Follow button.
- **Builder Overview skeleton:** a row of 3–4 short `.skeleton-text` blocks at label width.
- **Featured Project skeleton:** one large `.skeleton-image` at the Featured aspect ratio + `.skeleton-title` + two `.skeleton-text` lines.
- **Project Gallery skeleton:** reuses the existing `.skeleton-card-body` composition already used elsewhere (BlueprintCard grid loading state) — 6 repeated instances in the grid.
- **Technology Breakdown skeleton:** a single full-width shimmering bar block, no legend skeleton (appears together once data resolves).
- **Builder Journey skeleton:** 3–4 repeated `.skeleton-row`-style entries (existing composition) each with a small circular node placeholder.

All skeletons respect `prefers-reduced-motion` per the existing shimmer implementation — no new work needed there, just correct reuse.

---

## 9. Accessibility Considerations

- Hero avatar has `alt="{display_name}'s avatar"`, not decorative — it's identity-bearing content.
- Follow button state (`Follow`/`Following`) is announced via `aria-pressed`, matching whatever pattern the existing follow button already uses elsewhere in the app (confirm reuse, not reinvention).
- Builder Overview stat strip uses real text content for numbers (not icon-only or color-only encoding) — screen readers get "12 Projects" as one readable phrase, not a bare "12" next to a decorative icon.
- Technology Breakdown proportion bar: color segments are supplemented by the text legend below (label + count + percentage) so the information is never color-only. Each bar segment gets a `title`/`aria-label` with the same text ("PC Builds — 45%, 5 projects").
- Builder Journey timeline: the visual rail/node styling is decorative (`aria-hidden`); the actual entry content is a normal semantic list (`<ol>`, most-recent-first, matching real chronological order) so screen reader users get a correctly ordered list, not a div soup.
- Featured Project's "Featured" badge is a visible label, not just a border/glow treatment — consistent with the existing badge component's text-first design.
- Filter/sort controls in Project Gallery are real `<button>`/`<select>` elements (reused from Explore's existing accessible pattern), not custom unlabeled divs.
- All new icons (see §10) ship with accompanying visible or `aria-label` text — the icon system's existing convention (icons pair with text, not icon-only buttons) continues here.
- Color contrast: every text/background pairing introduced by this spec reuses existing token pairs already verified for WCAG AA elsewhere in the app (no new pairings to re-audit) — reconfirm with axe-core at implementation/verification time per the project's standard process.

---

## 10. Reusable Components

### 10.1 Reused as-is
- `BlueprintCard` (Project Gallery cards, and the basis for the Featured Project's larger treatment)
- Badge component (`badge.css`) — "Featured" label, technology chips in Builder Overview
- Skeleton primitives (`skeleton.css`)
- Button system (Follow button, Load More, View Project CTA)
- Explore's existing filter-pill and sort-dropdown patterns (Project Gallery filter bar)
- Global footer

### 10.2 New components needed
- **`ProfileHero`** — the identity block; new because current `.profile-hero` needs restructuring (headline field, quieter meta row, left-alignment).
- **`FeaturedProjectCard`** — a larger-format sibling of `BlueprintCard`, not a variant prop on it (different enough layout — bigger image, more copy visible — that overloading `BlueprintCard` with a "featured" mode would complicate its simpler, proven job).
- **`TechnologyBreakdownBar`** — new proportion-bar + legend component, technology-config-driven.
- **`BuilderJourneyTimeline`** — new cross-project timeline list, distinct from the existing single-project `renderTimeline.js` (different data shape: entries carry a project reference, single-project timeline doesn't need one).
- **`BuilderOverviewStats`** — new quiet stat-strip component (deliberately not reusing current `.profile-stat` tile markup — see §11).

### 10.3 New icons — approved, added to the shared system (§16.3)

Gap in `js/utils/icons.js` (currently 11 icons, none of these 6 exist). Per decision, these are added as new keys in the existing `PATHS` object in `js/utils/icons.js` itself — **not** inlined as page-specific `<svg>` markup in profile-page files — so any other page can call `icon("link", 20)` the same way it already calls `icon("bell", 20)` today:

- `link` (external website)
- `github` (brand mark, monochrome stroke-adapted to match the system's stroke-icon language, not the literal GitHub logo glyph)
- `location-pin`
- `calendar` (join date)
- `milestone` (Builder Journey milestone marker — also usable anywhere a "flag" concept is needed)
- `arrow-up-right` (external link affordance, distinct from existing `arrow-right`)

Each must follow the existing construction rules exactly: 24×24 viewBox, the 4 fixed sizes (16/20/24/32) driven by the existing `icon(name, size)` function, 1.5px base stroke scaled proportionally, `currentColor`, rounded joins/caps, no fills except the existing small-dot exception already used by `bell`/`warning`/`info`. This spec fixes the integration point and naming; exact path coordinates are authored at implementation time (§19 Phase 3), same as any hand-drawn icon.

---

## 11. Deviations From Current Implementation — approved 2026-08-01

- **Builder Overview stats get quieter, not louder — approved.** Current `.profile-stat` uses `2.5rem` bordered tiles — visually competes with Featured Project below it. New treatment is a slim text-only stat strip (closer to GitHub's "12 repositories · 340 followers" line).
- **Hero H1 size reduces — approved.** Drops from the current bespoke `clamp(3rem, 7vw, 5.5rem)` to the existing H1/H2 token scale — on a content-dense portfolio page where 7 more sections follow, a huge name leaves less room for scanning past it.
- **Avatar radius standardized — approved.** Uses the existing `--radius-xl` token (20px — the same value already used for dialogs) rather than the current bespoke 30px value, so the avatar stays anchored to the defined system instead of a one-off number.

These are approved for implementation (§19) — no further sign-off needed on these three specifically.

---

## 12. Animations & Component Interactions

Consistent with the brand's "calm enough for long work sessions" principle — every motion is subtle, purposeful, and respects `prefers-reduced-motion` (existing site-wide convention, unchanged).

- **On page load:** sections fade/slide in slightly (existing site entrance-animation pattern, if one exists site-wide — reuse, don't invent a bespoke one for this page).
- **Featured Project image:** subtle scale-on-hover (existing `BlueprintCard` hover treatment, reused at the larger scale) as the only hover affordance — no new hover language.
- **Technology Breakdown bar:** segments animate their width in from 0 on first reveal (one-time, on-scroll-into-view), then static — this is the one place a slightly more "alive" motion earns its keep, since it's presenting proportional data. Respects reduced-motion by rendering final-state widths immediately.
- **Builder Journey:** V1 renders a fixed top-10 list with no pagination/"load more" affordance (per §3.3d) — the timeline nodes can each fade/slide in once on first reveal (on-scroll-into-view, one-time), same treatment as the Technology Breakdown bar below it, then static. No list-append interaction exists to animate.
- **Follow button:** existing press/loading state pattern, unchanged, reused verbatim.
- **Project Gallery filter/sort:** existing Explore filter-pill active-state transition, reused verbatim — no new interaction language invented for a page that should feel like the rest of the site, not a separate microsite.

---

## 13. Performance Considerations

- **Featured Project resolution** (§3.3b, §17.2) needs only `featured_build_id` (already on the fetched profile) plus `status`/`updated_at`/`visibility` on each build — all already fetched today via `getProfileBuilds`. No extra query; a client-side `find`/`sort` over data already in memory. No N+1 risk.
- **Builder Journey fetches a capped recent-revisions window** (§17.3, `limit = 100`), not the builder's entire revision history — synthesis then trims to the top 10 events client-side (§17.4). A prolific builder's very old milestones could in principle fall outside that 100-row window; flagged as a known V1 limitation (raise the cap later if it proves too tight) rather than fetching an unbounded history up front.
- **Technology Breakdown aggregation** is a pure client-side reduce over builds already fetched for Project Gallery — no separate query.
- **Images:** Featured Project's large cover image should use `loading="eager"` (above the fold, high-priority) while Project Gallery cards below it stay `loading="lazy"` — matches the existing lazy-load convention already used in `BlueprintCard`/`BlueprintFeed`.
- **Non-blocking secondary fetches** (comment counts, current-user follow-state) should continue the existing pattern in `loadProfile.js` — fire after primary content renders, never block first paint.
- **New cross-project journey query** should be deferred (fetched after the above-the-fold content is rendered) since it's the 6th section down the page and never blocks initial render — matches the existing "secondary, non-blocking fetch" pattern already established for comment counts.

---

## 14. Explicitly Out of Scope This Milestone

- Any change beyond the one approved migration in §16 (`profiles.headline`, `profiles.featured_build_id`, and their supporting constraint/trigger) — no other schema work is in scope.
- A messaging/contact system — no such schema exists; not invented here.
- Cover-photo/banner upload — considered and rejected in favor of GitHub's calmer identity-block approach (§1); could be revisited as a V2 enhancement if requested.
- Any change to `.page-foundation`, the color palette, or any token in `tokens.css` — the palette is settled; this spec composes entirely from existing tokens.
- Rich text/markdown support for the About Builder bio — remains plain text, matching the current `bio` column's actual capability.

---

## 15. Approval Checklist — status as of this revision

1. §3.3(a) — ~~add `profiles.headline` column, or reuse single `bio` field?~~ **Decided: separate `headline` column, ≤120 chars.**
2. §3.3(b) — ~~automatic vs. builder-controlled Featured Project?~~ **Decided: builder-controlled `featured_build_id`, with a completed → published → hidden fallback chain. No likes-based ranking.**
3. §11 — ~~approve the three visual deviations?~~ **Approved: quieter stat strip, reduced Hero H1, standardized avatar radius.**
4. §10.3 — ~~how should the 6 new icons be added?~~ **Decided: as new entries in the shared `js/utils/icons.js` `PATHS` object, not page-specific markup.**
5. §3.3(d) — ~~should Builder Journey show every revision?~~ **Decided: curated top 8–12 (implementing as 10) from published/completed/milestone/major-version/first-in-category events only.**

6. §7 — ~~zero-projects owner-view CTA?~~ **Decided: "Publish Your First Build" linking to `../upload.html` (the existing Publish flow entry point), not the editor directly.**

All six items are now closed — see §20 for the consolidated final-decisions record. Sections §16–19 give the exact schema, queries, component map, and phased implementation plan. **Implementation is approved and proceeding** in the phases and commit groups defined in §19/§20.

---

## 16. Schema Migration (Proposed — Not Yet Applied)

One new migration, `supabase/migrations/0024_profile_headline_and_featured_build.sql`, following this repo's existing convention (header comment, `begin`/`commit`, paired rollback in `supabase/rollbacks/`). Next available number is `0024` (last tracked migration is `0023`).

### 16.1 Forward migration

```sql
-- Migration: 0024_profile_headline_and_featured_build
-- Milestone: 20 (Builder Portfolio)
-- Status: PROPOSED — not yet applied. Depends on 0000-0023 being applied
-- first.
--
-- Purpose: adds the two profiles columns the Builder Portfolio redesign
-- needs (see docs/milestones/MILESTONE_20_BUILDER_PORTFOLIO_SPECIFICATION.md
-- §3.3, §16):
--   - headline: a short (<=120 char) hero tagline, distinct from the
--     existing longer `bio` column (About Builder section). Optional —
--     both columns may be null independently.
--   - featured_build_id: the builder's own explicit pin for the Featured
--     Project section. Builder-controlled by design decision — never
--     selected by likes_count or any other engagement metric.
--
-- Touches: public.profiles (2 new nullable columns, 1 new CHECK, 1 new FK
-- to public.builds), 1 new trigger function + trigger. Does not touch RLS:
-- the existing "Users can update their own profile" policy (0000) already
-- covers write access to these two new columns, since it's a whole-row
-- policy keyed on auth.uid() = id, not a column allowlist. What that
-- policy can't express is "the referenced build must belong to the same
-- profile" — a cross-row constraint — so a trigger enforces that
-- separately. The trigger checks ownership only, not visibility: a builder
-- may pin a build that isn't currently public (e.g. still finishing it).
-- Visibility eligibility is re-checked every time the page renders (see
-- spec §17.2), not enforced at write time.
--
-- Rollback: see 0024_profile_headline_and_featured_build_rollback.sql in
-- supabase/rollbacks/. Drops the trigger/function first, then both new
-- columns (the CHECK constraint drops automatically with its column).

begin;

alter table public.profiles
    add column headline text,
    add column featured_build_id uuid references public.builds(id) on delete set null;

alter table public.profiles
    add constraint profiles_headline_length_check
    check (headline is null or char_length(headline) <= 120);

-- Runs with the invoking user's own privileges (no reason to elevate — it
-- only checks a row the invoking user already owns via the outer UPDATE's
-- own RLS pass) and pins search_path defensively, matching the convention
-- set by public.set_updated_at() in 0001.
create or replace function public.validate_featured_build()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
    if new.featured_build_id is not null then
        if not exists (
            select 1 from public.builds
            where id = new.featured_build_id
              and user_id = new.id
        ) then
            raise exception 'featured_build_id must reference a build owned by this profile';
        end if;
    end if;
    return new;
end;
$$;

create trigger validate_featured_build_before_write
    before insert or update of featured_build_id on public.profiles
    for each row
    execute function public.validate_featured_build();

commit;
```

### 16.2 Rollback

```sql
-- Rollback for 0024_profile_headline_and_featured_build.
-- Drop order: trigger before function (dependency), then both columns
-- (the CHECK constraint and the FK both drop automatically with their
-- owning column — no separate `drop constraint` needed for either).

begin;

drop trigger if exists validate_featured_build_before_write on public.profiles;
drop function if exists public.validate_featured_build();

alter table public.profiles
    drop column if exists featured_build_id,
    drop column if exists headline;

commit;
```

### 16.3 What this does and doesn't enforce

- **Enforced in the database:** `headline` length (≤120 chars); `featured_build_id`, when set, must point at a build owned by the same profile (security boundary — prevents a builder from pinning someone else's project under their own name).
- **Not enforced in the database, by design:** that the pinned build is currently `visibility = 'public'`. A builder can legitimately pin a build they're still working on. The read path (§17.2) is what guarantees only a public build ever actually displays as Featured — if the pinned build isn't public at render time, resolution falls through to the same fallback chain as if nothing were pinned.
- **No RLS changes** — the existing whole-row "Users can update their own profile" policy already covers these columns.

---

## 17. Repository Queries (Proposed)

All additive — no existing function's behavior changes. `getProfileBuilds` (already in `profileRepository.js`) is reused as-is for §17.1 and §17.2; nothing about it needs to change.

### 17.1 `profileRepository.js` — column list and generic update

```js
const PUBLIC_PROFILE_COLUMNS =
    "id, username, display_name, headline, bio, location, website, github, youtube, avatar_path, avatar_url, created_at, followers_count, following_count, featured_build_id";
```

Settings currently updates `profiles` with an inline `supabase.from("profiles").update(updates).eq("id", user.id)` call in `js/pages/settings/app.js` rather than going through `profileRepository.js` (a pre-existing gap, not introduced by this milestone). `headline` and `featured_build_id` slot into that same existing `updates` object with no new repository function strictly required — Phase 6 (§19) can either keep that pattern or introduce a `updateProfile(id, fields)` repository wrapper for consistency; not a decision this spec needs to force.

### 17.2 Featured Build resolution — pure function, no new query

Operates on data `loadProfile.js` already fetches (`profile` from `getPublicProfile`, `builds` from `getProfileBuilds`). New file: `js/pages/profile/resolveFeaturedBuild.js`.

```js
export function resolveFeaturedBuild(profile, builds) {
    const pinned = profile.featured_build_id
        ? builds.find(b => b.id === profile.featured_build_id && b.visibility === "public")
        : null;
    if (pinned) return pinned;

    const completed = builds.filter(b => b.status === "completed");
    if (completed.length) {
        return mostRecentlyUpdated(completed);
    }

    if (builds.length) {
        return mostRecentlyUpdated(builds);
    }

    return null;
}

function mostRecentlyUpdated(list) {
    return list.slice().sort((a, b) => new Date(b.updated_at) - new Date(a.updated_at))[0];
}
```

`builds` passed in is already filtered to `visibility = 'public'` by `getProfileBuilds` itself — the explicit `visibility === "public"` check on the pinned branch exists for the case where `featured_build_id` points at a build outside that already-filtered public set (i.e. currently private), which `.find()` over a public-only list would naturally return `undefined` for anyway; kept explicit for readability rather than relying on that implicitly.

### 17.3 Builder Journey — recent revisions fetch

New function in `js/repositories/buildRepository.js` (sibling to the existing build/revision queries there):

```js
export async function getRecentBuilderRevisions(userId, { limit = 100 } = {}) {
    const { data, error } = await supabase
        .from("build_revisions")
        .select(
            "id, build_id, title, snapshot_title, version, milestone, update_type, created_at, " +
            "builds!inner(title, slug, category, user_id, visibility)"
        )
        .eq("builds.user_id", userId)
        .eq("builds.visibility", "public")
        .order("created_at", { ascending: false })
        .limit(limit);

    if (error) throw error;
    return data || [];
}
```

Uses PostgREST's embedded-resource filter syntax (`builds!inner(...)` plus `.eq("builds.user_id", ...)`) to push the join and both filters to the database in one round trip — same pattern already used elsewhere in this codebase for owner-scoped joins. Exact filter syntax should be smoke-tested against the project's actual PostgREST version at implementation time (no DB access from this environment to verify in advance); the fallback if embedded filters don't behave as expected is two plain queries (fetch the builder's public build ids first, then `.in("build_id", ids)` on `build_revisions`) — functionally equivalent, one extra round trip.

### 17.4 Builder Journey — event synthesis (pure function, no I/O)

New file: `js/pages/profile/buildBuilderJourney.js`. Takes the already-fetched `builds` (§17.1's `getProfileBuilds` result) and `revisions` (§17.3's result); returns up to `limit` events, most recent first.

```js
import { getTechnology } from "../../config/technologies/index.js";

const MAJOR_VERSION_PATTERN = /^v?\d+\.0$/i;

export function buildBuilderJourney(builds, revisions, { limit = 10 } = {}) {
    const events = [];

    for (const build of builds) {
        events.push({
            type: "published",
            date: build.created_at,
            build,
            label: `Published ${build.title}`
        });

        if (build.status === "completed") {
            events.push({
                type: "completed",
                date: build.updated_at,
                build,
                label: `Completed ${build.title}`
            });
        }
    }

    for (const build of firstBuildPerCategory(builds)) {
        const technology = getTechnology(build.category);
        events.push({
            type: "first-in-category",
            date: build.created_at,
            build,
            label: `First ${technology ? technology.title : build.category} project: ${build.title}`
        });
    }

    for (const revision of revisions) {
        const isMajorVersion = MAJOR_VERSION_PATTERN.test((revision.version || "").trim());
        if (!revision.milestone && !isMajorVersion) continue;

        events.push({
            type: revision.milestone ? "milestone" : "major-version",
            date: revision.created_at,
            build: revision.builds,
            label: revision.milestone
                ? (revision.snapshot_title || revision.title || "Milestone update")
                : `${revision.builds.title} reached ${revision.version}`
        });
    }

    return events
        .sort((a, b) => new Date(b.date) - new Date(a.date))
        .slice(0, limit);
}

function firstBuildPerCategory(builds) {
    const firstByCategory = new Map();
    for (const build of builds) {
        const existing = firstByCategory.get(build.category);
        if (!existing || new Date(build.created_at) < new Date(existing.created_at)) {
            firstByCategory.set(build.category, build);
        }
    }
    return firstByCategory.values();
}
```

No de-duplication pass is included: a single build can legitimately contribute a "published" event and a "completed" event and a "first-in-category" event as three distinct, individually true facts — that's a feature (a builder's biggest project earning multiple journey entries), not a bug to suppress.

### 17.5 Technology Breakdown — no new query

Confirmed unchanged from the first draft: a pure client-side `reduce` over the same `builds` array already in memory from `getProfileBuilds`, grouping by `category` and mapping each to `getTechnology(category).accent`/`.title` from the existing `js/config/technologies/index.js`.

---

## 18. Component Map

New/modified files, grouped by what they implement. CSS files are named but not spec'd token-by-token here — §5/§6 already fix the spacing and typography inputs each must use.

| File | Change |
|---|---|
| `supabase/migrations/0024_profile_headline_and_featured_build.sql` | New — §16.1 |
| `supabase/rollbacks/0024_profile_headline_and_featured_build_rollback.sql` | New — §16.2 |
| `supabase/migrations.md` | Modified — new `## 0024` entry, existing convention |
| `docs/DATABASE.md` | Modified — note new columns if the file's conventions warrant it (matches how prior migrations were logged) |
| `js/repositories/profileRepository.js` | Modified — `PUBLIC_PROFILE_COLUMNS` (§17.1) |
| `js/repositories/buildRepository.js` | Modified — add `getRecentBuilderRevisions` (§17.3) |
| `js/pages/profile/resolveFeaturedBuild.js` | New — §17.2 |
| `js/pages/profile/buildBuilderJourney.js` | New — §17.4 |
| `js/utils/icons.js` | Modified — 6 new `PATHS` entries (§10.3) |
| `js/pages/profile/renderProfileHero.js` | New/rewritten — replaces the Hero portion of current `renderProfile.js`; headline, quieter meta row, left-alignment, standardized avatar radius (§11) |
| `js/pages/profile/renderBuilderOverview.js` | New — quiet stat strip + technology-focus chips (§4.1, §11) |
| `js/pages/profile/renderFeaturedProject.js` | New — consumes `resolveFeaturedBuild` |
| `js/pages/profile/renderProjectGallery.js` | New/rewritten — filter/sort bar + `BlueprintCard` grid, reused from current build-grid rendering |
| `js/pages/profile/renderTechnologyBreakdown.js` | New — proportion bar + legend |
| `js/pages/profile/renderBuilderJourney.js` | New — consumes `buildBuilderJourney`, renders the semantic `<ol>` timeline |
| `js/pages/profile/renderAboutBuilder.js` | New — narrative bio + repeated links |
| `js/pages/profile/loadProfile.js` | Modified — fetch `getRecentBuilderRevisions` as a deferred/non-blocking call (§13), call the new render functions in section order |
| `js/pages/profile/renderProfile.js` | Modified — becomes the thin orchestrator calling the section renderers above, replacing its current monolithic body |
| `js/utils/skeletons.js` | Modified — new compositions for Hero/Overview/Featured/Journey (§8), reusing existing primitives |
| `css/pages/profile/profile.css` | Modified — quieter stat strip, reduced H1, standardized avatar radius, new section layouts |
| `pages/profile.html` | Modified — new section markup/order matching §4 |
| `js/pages/settings/app.js` | Modified (Phase 6) — headline input (120-char counter), Featured Build picker sourced from the builder's own published builds |
| `pages/settings.html` | Modified (Phase 6) — new form fields |

No changes to `BlueprintCard.js`, `technologies/*.js`, `badge.css`, `skeleton.css` primitives, `foundation.css`, or any token file — all reused as-is per §10.1 and §14.

---

## 19. Implementation Phases

Kept in small, separately-verifiable steps, matching this repo's established milestone convention (e.g. Milestone 19's phased build), and landing as separate logical commits per §20.

1. **Schema.** Apply `0024` (§16) to a dev Supabase project only, per this repo's standing dev-application procedure — never applied directly to production from this environment. Verify the ownership trigger rejects a cross-user `featured_build_id` and accepts a same-user one, in both `insert`-via-trigger and profile-signup paths. *Commit: schema.*
2. **Repository layer.** `profileRepository.js` column list, `buildRepository.js`'s `getRecentBuilderRevisions`, `resolveFeaturedBuild.js`, `buildBuilderJourney.js`. Pure-function pieces (§17.2, §17.4) can be exercised with hand-built fixture data before any live data exists. *Commit: repository/data logic.*
3. **Icon system + section components.** Six new `PATHS` entries in `js/utils/icons.js` (§10.3, hand-authored to the existing construction rules), plus the new `render*.js` section files and `profile.css` changes from §18, built and visually checked one section at a time against §4's layout and §11's approved deviations. *Commit: shared icons/components.*
4. **Page wiring + skeletons.** `pages/profile.html` restructuring, `renderProfile.js` becoming the thin orchestrator, `loadProfile.js`'s fetch sequencing (§13's non-blocking-fetch ordering), skeleton compositions (§8), the zero-project empty state with its "Publish Your First Build" → `../upload.html` CTA (§7, §20.1). *Commit: page wiring.*
5. **Settings UI — required for this milestone, not deferred.** Headline field (120-char limit, live counter) and Featured Build picker added to `pages/settings.html`/`settings/app.js`. The picker's option list is fetched and filtered to the signed-in builder's own `visibility = 'public'` builds only (§20.2) — the database ownership trigger from §16 remains as defense in depth, not the primary UX guard; a builder should never even see an ineligible build as a choice. *Commit: Settings UI.*
6. **Tests.** Update `tests/profile.test.html` (currently written against the pre-redesign `renderProfile.js`; every DOM id/structure assertion needs re-authoring against the new section orchestration) and add new fixture-driven unit coverage for the pure functions in §17: `resolveFeaturedBuild.js` (all three fallback tiers, plus the stale-pin/now-private case) and `buildBuilderJourney.js` (each of the 5 event sources, the conservative major-version regex's accept/reject cases, and the 10-event cap). Follows this repo's existing `tests/*.test.html` + `window.__testResults` convention (`tools/ci/run-tests.js`). *Commit: tests.*
7. **Verification.** Live-browser check of every section against real and fixture data, including: zero-project profile (confirm the new CTA), profile with unset `featured_build_id` (all three fallback tiers), profile with a stale `featured_build_id` pointing at a now-private or deleted build (§20.3), a profile with zero qualifying Builder Journey events, mobile/tablet responsive check (§4.2–4.3), axe-core pass (§9), and the repo's two standing static checks (`verify_refcheck.py`, `verify_a11y_regressions.py`). Not a separate commit — a verification pass over the five commits above; fixes for anything it finds land as follow-up amendments to the relevant commit's phase, not a catch-all cleanup commit.

---

## 20. Final Decisions — locked 2026-08-01

Consolidated record of the decisions that closed §15's checklist, for quick reference:

1. **Zero-project empty-state CTA** (§7): "Publish Your First Build", linking to `../upload.html` — the site's existing Publish flow entry point — not an editor page reached any other way.
2. **Featured Build selector scope** (§19 Phase 5): the Settings picker's option list must only ever contain the builder's own published (`visibility = 'public'`) builds — filtered at the UI/query level, not just relying on the trigger to reject a bad choice after the fact. The `0024` database ownership trigger (§16) stays in place as defense in depth, not as the primary correctness mechanism.
3. **`featured_build_id` deletion behavior** (§16.1): confirmed `on delete set null` (already specified, not a change) — if a pinned build is deleted, or later found ineligible (private) at render time, resolution falls through the documented fallback chain (§17.2), never errors or shows a broken reference.
4. **Builder Journey scope** (§3.3d): confirmed latest 10 curated events, no pagination or "full history" view in V1 (already specified, not a change).
5. **Major-version detection conservatism** (§3.3d, §17.4): confirmed the `/^v?\d+\.0$/i` pattern is deliberately narrow — an ambiguous freeform version (e.g. `"1.0.1"`, `"Update 2"`, `"v1"`) is skipped rather than guessed at. No looser heuristic is introduced.
6. **Settings scope** (§19 Phase 5): headline and Featured Build controls are in scope for this milestone's implementation, not deferred to a later one.
