# Milestone 10 — Brand Refresh: Design System Architecture Proposal

**Status: Approved, with 7 additions incorporated below (Design Goals, an expanded Spacing System, Iconography Standards, Skeleton Loading, Empty States, Microinteractions, Responsive Design Rules). Architecture only — no implementation yet, per your instruction to review the completed document once more before implementation begins.**

**Scope confirmed with you first**: "Assembly Mark" refers to the current rounded-square "S" badge (`assets/brand/logo/favicon.svg`, created in Phase 9C) — this proposal keeps that geometric-badge *approach* and refines its execution, rather than replacing the concept.

**Grounded against the current system**, not designed in a vacuum — every section below states what's being kept, what's changing, and why, referencing the real current values in `css/base/tokens.css` and the component files that consume them.

---

## The core problem this milestone solves

The current system (`--color-primary: #4f7dff`, a bright saturated blue, paired with color-tinted glow baked into the default hover shadow — `--shadow-hover: 0 18px 55px rgba(79, 125, 255, 0.18)` applied broadly) reads as *generic bright-SaaS-blue*, not as anything specific to Specbound. Nothing about the current palette or effects is broken or unprofessional — but nothing about it is **recognizable** either, and the ambient blue glow on hover states, applied fairly liberally, is the specific thing that risks tipping toward "gamer-adjacent" if pushed any further (RGB-lit product cards, glowing borders everywhere) rather than pulled back.

**The organizing idea for this refresh**: Specbound's whole product concept is *blueprints for builds* — technical drawings, specifications, versioned documentation. The visual language should borrow, subtly, from technical/engineering drafting conventions (hairline rule work, precise geometry, monospaced technical data, restrained corner-bracket framing reminiscent of CAD/viewfinder selection marks) instead of from general dashboard-SaaS or gaming-adjacent conventions. This is what makes "technical" and "recognizable" the same solution rather than two separate asks — and it's a natural fit for a product about documenting builds, not a decoration bolted on top.

Everything below is designed against that idea, and against the explicit avoid-list: no neon, no RGB-cycling, no glow-as-decoration, no visual noise.

**A governing principle, stated explicitly per your review note**: the blueprint/CAD inspiration is a *design influence*, not a *visual theme*. It shows up as structural and detail-level choices — corner-bracket framing on hover, monospaced technical data, precise (not soft) geometry, hairline rule weight — never as literal thematic decoration. **No graph-paper or grid-line backgrounds, no ruler/protractor chrome, nothing that makes the product look like it's imitating CAD software.** The test for every detail in this document: someone should be able to use Specbound for weeks, feel that it's unusually precise and considered compared to a generic dashboard, and only consciously notice *why* if they stop and look closely. If a detail would be noticed in the first ten seconds as "oh, this has a blueprint theme," it's wrong and should be cut — the goal is a modern premium product first, with the engineering heritage as an aftertaste, not a costume. (This replaces and supersedes the original proposal's §9.2 "blueprint-grid texture" idea, which the review below removes outright.)

---

## Design Goals — how Specbound should feel in the first 10 seconds

Every decision in this document is in service of six qualities, all present at first glance, before a visitor has read a word:

| Quality | What it means concretely here |
|---|---|
| **Professional** | Restrained color use (§1's three-tier model), neutral elevation by default (§5), no decorative flourish without function |
| **Focused** | Glow confined to 4 named uses (§6) so nothing competes for attention; interior/utility pages (Workshop, Settings, the editor) stay flat and undistracted — no ambient effects where someone is trying to get work done |
| **Technical** | Monospaced technical data (§2), precise tightened geometry (§4), the corner-bracket detail (§7) — structural signals, not literal theming (see the governing principle above) |
| **Organized** | The 4px/8px spacing grid (§3) applied without exception, a documented responsive system (new §11) so layouts never feel improvised at any viewport |
| **Approachable** | Warm, specific empty-state copy instead of generic system messages (new §10 revision), calm motion with no jarring or aggressive animation (§8, new §12), legible type hierarchy over color-coded hierarchy |
| **Premium** | Consistency above all — one icon system (new §7.5), one skeleton-loading language (new §10 revision), one motion vocabulary (new §12) applied identically everywhere, rather than each screen inventing its own treatment |

These six qualities are the acceptance criteria for every section below — where a choice is ambiguous, it should be resolved by asking which option serves more of these six, not by aesthetic preference alone.

---

## 1. Color tokens

Kept: the layered dark-surface *structure* (5 background steps), the semantic-color *concept* (success/warning/danger/info), the alias layer for backward compatibility during migration. Changed: nearly every actual value, all consolidated into token *categories* rather than ad hoc names, exactly as you asked ("use design tokens rather than page-specific colors" — already mostly true today, this formalizes and refines it).

### Base surfaces (dark-first, cooler and less saturated than current)

| Token | Value | vs. today |
|---|---|---|
| `--color-bg` | `#0a0b0f` | was `#090b11` — marginally cooler/darker, negligible visual shift, kept as the anchor |
| `--color-bg-elevated` | `#0e1015` | was `#0f131c` — less blue undertone |
| `--color-surface` | `#13151b` | was `#141923` — same idea, desaturated |
| `--color-surface-2` | `#191c24` | was `#1b2230` — desaturated |
| `--color-surface-3` | `#20232c` | was `#222b3a` — desaturated |

**Why desaturate the neutrals**: the current surfaces carry a fairly strong blue tint even before any accent color is applied — every dark panel already leans "blue app." Pulling the neutral ramp toward true cool-gray (barely-there blue, not absent, just quieter) frees the actual primary color to be the only saturated thing on screen, which is the single biggest lever for reading as "calm" and "premium" instead of "blue-themed."

### Primary, secondary, accent — the three-tier model you asked for

Today there's only ever been one brand color (`--color-primary`) doing every job: links, buttons, focus rings, hover glow, badges. This refresh **splits that single job into three deliberately distinct tokens**, so no single color has to be both "the professional UI color" and "the exciting highlight color" at once — that tension is exactly what pushes a palette toward overuse/neon:

| Token | Value | Role |
|---|---|---|
| `--color-primary` | `#4A5FE8` (a controlled indigo — deeper and less "sky blue" than today's `#4f7dff`, more ink than electric) | Primary actions, links, active states, focus rings — the everyday functional color, used often but never as a glow |
| `--color-secondary` | `#7C8291` (a cool graphite, roughly the value of today's `--color-text-muted` but promoted to a real token) | Secondary UI accents, inactive/quiet states, subtle iconography — the "calm" counterweight to primary |
| `--color-accent` | `#5EEAD4` (a restrained teal — desaturated enough to avoid neon, saturated enough to read as a genuine highlight) | **Reserved exclusively** for the specific glow/highlight moments defined in §6 — never used for body UI, never for buttons, never for large fills. This scarcity is what makes it feel premium instead of decorative. |

This is the mechanism that directly answers "avoid RGB overload / excessive neon": there are now exactly **three** brand colors total, each with a non-overlapping job, and only one of them (`--color-accent`) is allowed to be visually loud — and even that one only in the narrow contexts §6 defines.

### Surfaces, borders, typography colors (tokenized, not page-specific)

| Category | Tokens |
|---|---|
| Surfaces | `--color-bg`, `--color-bg-elevated`, `--color-surface`, `--color-surface-2`, `--color-surface-3` (as above) |
| Borders | `--color-border` (hairline, `rgba(255,255,255,0.10)` — much quieter than today's `0.35`, since the new desaturated surfaces need less contrast to read as distinct panels) and `--color-border-strong` (`rgba(255,255,255,0.18)`, for interactive/focus contexts that need the WCAG 1.4.11 3:1 non-text contrast the 8D audit required — re-verified against the new darker surfaces, not assumed) |
| Typography | `--color-text` (`#F5F6F8`, off-white — pure `#ffffff` reads slightly harsh against the new cooler backgrounds), `--color-text-secondary` (`rgba(245,246,248,0.68)`), `--color-text-muted` (`rgba(245,246,248,0.42)`), `--color-text-inverse` (`#0a0b0f`, new — needed for text-on-light-fill contexts like filled badges) |

### Semantic colors (refined, not reinvented)

| Token | Value | vs. today |
|---|---|---|
| `--color-success` | `#3DD68C` | was `#34d399` — negligible shift, already calm |
| `--color-warning` | `#E8B339` | was `#fbbf24` — very slightly desaturated to match the cooler overall palette |
| `--color-danger` | `#F0524D` | was `#ef4444` — negligible shift |
| `--color-info` | `#4A9FE8` | was `#22d3ee` — **this one changes more**: the old value was a bright cyan close enough to the new `--color-accent` teal to visually collide; shifted toward blue to stay clearly distinct from both `--color-primary` and `--color-accent` |

`--color-primary-strong`/`--color-danger-strong` (the separate darker pair for white-text-on-fill contrast, documented in the current tokens file's own comments) are kept as a *pattern*, recalculated against the new base colors, re-verified at WCAG AA before finalizing — the 8D audit's own methodology, not skipped this time either.

### Migration approach

Every current alias (`--primary`, `--bg`, `--surface`, etc.) stays in place, repointed to the new values — exactly the mechanism the current tokens file already uses to keep older CSS working. This means the refresh can land as a **token-file-only change** for the majority of the visual shift, with component-level CSS updates layered in only where §7's new component standards need more than a color swap (glow placement, border treatment, corner-bracket details).

---

## 2. Typography

**Kept**: Inter as the interface typeface, the existing weight range (400/500/600/700/800), the existing responsive `--font-size-display` clamp pattern.

**Added**: a second, deliberately narrow-use typeface — **a monospace face** (`"IBM Plex Mono", "JetBrains Mono", ui-monospace, monospace` — either is fine, pick based on licensing/loading preference) — reserved *only* for technical/numeric data: version numbers (`v1.1`), spec values, timestamps in the revision timeline, progress percentages. This is the single highest-leverage "technical" and "recognizable" signal in the whole system: a small, consistent typographic detail that shows up on every build page, every spec sheet, every timeline entry, and reads as deliberate engineering precision rather than decoration. It costs one extra font load and a handful of `font-family: var(--font-family-mono)` rules on already-existing elements — not a redesign of those elements.

### Complete scale

| Token | Size | Line-height | Weight | Typical use |
|---|---|---|---|---|
| `--font-size-display` | `clamp(3.4rem, 7vw, 6.5rem)` | `--line-height-tight` (1) | 800 | Homepage hero only (unchanged from today) |
| `--font-size-3xl` | `2.25rem` | `--line-height-heading` (1.12) | 800 | Page-level H1 |
| `--font-size-2xl` | `1.75rem` | 1.15 | 700 | Section headings |
| `--font-size-xl` | `1.375rem` | 1.2 | 700 | Card/subsection headings |
| `--font-size-lg` | `1.125rem` | 1.4 | 600 | Emphasized body, lede text |
| `--font-size-md` | `1rem` | `--line-height-body` (1.7) | 400 | Default body text |
| `--font-size-sm` | `0.875rem` | 1.55 | 400/500 | Secondary text, form labels |
| `--font-size-xs` | `0.75rem` | 1.4 | 500 | Captions, meta text, badge labels |
| `--font-size-mono` (new) | `0.8125rem` (13px) | 1.4 | 500 (mono faces read heavier at the same weight number) | Technical/numeric data only — versions, specs, timestamps |

`--font-size-3xl` moves from today's `2.4rem` to `2.25rem` — a small, deliberate tightening; the current value sits unusually close to `--font-size-display` on smaller viewports, undermining the hero's own primacy. Everything else in the scale is unchanged from today's values, since the existing progression is already sound — this section formalizes it as a documented scale (including the new mono step) rather than replacing working numbers.

---

## 3. Spacing

**Kept**: the 8px-based system and its current 9-step range (`--space-1` through `--space-9`, 8px→120px) — already a real, working, consistently-applied scale (used correctly per Phase 6/Phase 9C's own dead-code audits, which found no rogue magic-number spacing).

**Added**: a `--space-0` half-step at `4px`, for the finer control the current scale can't express (icon-to-label gaps, badge internal padding, the tight spacing technical/mono data benefits from). This is additive, not a renumbering — nothing currently using `--space-1` through `--space-9` needs to change.

| Token | Value | Typical use |
|---|---|---|
| `--space-0` (new) | `4px` | Icon gaps, badge padding, tight inline spacing |
| `--space-1` | `8px` | Unchanged |
| `--space-2` | `16px` | Unchanged |
| `--space-3` | `24px` | Unchanged |
| `--space-4` | `32px` | Unchanged |
| `--space-5` | `48px` | Unchanged |
| `--space-6` | `64px` | Unchanged |
| `--space-7` | `80px` | Unchanged |
| `--space-8` | `96px` | Unchanged |
| `--space-9` | `120px` | Unchanged |

### The grid rule (new — stated explicitly as a system rule, not just a token list)

**Every layout value in the application — margin, padding, gap, and (via §4) radius — must be one of the tokens above, with no exceptions and no arbitrary pixel values.** This is already largely true today (confirmed clean in Phase 6/9C's audits), but this milestone promotes it from an informal convention to a documented, enforceable rule, because the new component standards (§7) and responsive rules (§11) both depend on it: a corner-bracket detail, a modal's internal padding, and a mobile breakpoint's tightened gaps only look like one coherent system if they're all built from the same 4px/8px steps rather than each hand-tuned. Component-level CSS review during implementation should treat any new hardcoded pixel spacing value as a defect, the same way Phase 9C treated dead code — not a style nitpick, a system violation.

Two derived half-steps for cases the whole-number scale can't reach cleanly: `--space-0-5` (`12px`, new — the gap between `--space-0` and `--space-1`, useful for compact list-item padding) sits alongside `--space-0`. No further half-steps are proposed — if a third layout value doesn't fit this scale, that's a signal the layout itself needs rethinking, not that the scale needs another exception.

---

## 4. Radius

**One scale, as requested** — but tightened from today's fairly soft/rounded values. Heavy rounding (today's `--radius-xl: 36px`) reads as "friendly consumer app"; the technical/drafted aesthetic this refresh is going for wants corners that feel *precise*, not pillowy.

| Token | Value | vs. today |
|---|---|---|
| `--radius-xs` | `6px` | was `8px` |
| `--radius-sm` | `10px` | was `12px` |
| `--radius-md` | `14px` | was `16px` |
| `--radius-lg` | `20px` | was `24px` |
| `--radius-xl` | `28px` | was `36px` — the largest reduction, specifically because 36px on a large card/hero surface is where the "soft consumer app" read is strongest |
| `--radius-pill` | `999px` | Unchanged — pills stay pills (badges, tags) |

Every component keeps its current *radius token assignment* (a card still uses `--radius-lg`, a badge still uses `--radius-pill`) — only the underlying values shift, so this is a low-risk, high-leverage single-file change for a huge fraction of the visual refresh.

---

## 5. Shadows

**The most important structural change in this proposal**: shadows and glow are being **split into two separate systems** (this section = neutral elevation, §6 = colored glow). Today they're partially merged — `--shadow-hover` is a *color-tinted* shadow (`rgba(79, 125, 255, 0.18)`) used as the default hover state for cards, buttons, and other controls broadly. That's the single biggest reason the current system risks reading as over-lit: color-tinted "glow" is currently the *default*, not a special case.

### Elevation (neutral, this section)

| Token | Value | vs. today |
|---|---|---|
| `--shadow-xs` (new) | `0 2px 8px rgba(0,0,0,0.16)` | New — for subtle resting elevation (inputs, small controls) that today has no shadow step below `--shadow-sm` |
| `--shadow-sm` | `0 6px 20px rgba(0,0,0,0.20)` | was `0.18` alpha — negligible |
| `--shadow-md` | `0 10px 34px rgba(0,0,0,0.28)` | was `0.24` — slightly deeper, to compensate for the now-quieter borders (§1) still needing to read as distinct panels |
| `--shadow-lg` | `0 24px 70px rgba(0,0,0,0.42)` | was `0.38` — same reasoning |

**`--shadow-hover` is retired as a token name.** Every current consumer of `--shadow-hover` (card hover states, primarily) moves to `--shadow-md` — a neutral elevation bump on hover, no color. Anything that specifically wants the *glow* treatment on hover uses the new `--glow-*` tokens from §6 explicitly, as an opt-in, not a default.

---

## 6. Glow

**Exactly where glow is allowed — the direct answer to your ask, not a vague guideline.**

Glow uses `--color-accent` (the restrained teal, §1) exclusively — never `--color-primary`, so glow and "the button color" are never the same thing, which is what keeps it feeling like a deliberate highlight rather than an ambient tint everywhere.

| Token | Value | **The only 4 allowed uses** |
|---|---|---|
| `--glow-sm` | `0 0 24px rgba(94, 234, 212, 0.16)` | 1. **Focus-visible rings** on interactive elements (replaces a plain outline with a soft accent glow — genuinely useful, high-frequency, and exactly the kind of "premium technical tool" detail that reads well, e.g. Linear/Raycast's own focus treatment) |
| `--glow-md` | `0 0 48px rgba(94, 234, 212, 0.14)` | 2. **The single active/selected state per view** — e.g. the currently-selected technology filter chip on Explore, the cover-image star on the gallery grid. Never more than one glowing element on screen at a time. |
| `--glow-lg` | `0 0 96px rgba(94, 234, 212, 0.10)` | 3. **One ambient background glow per page, at most**, and only on marketing/landing-style surfaces (the homepage hero, the Featured Spotlight backdrop) — a large, soft, low-opacity radial glow behind content, not on any content element itself. This is a "set the mood once" device, not a repeated UI pattern. |
| — | — | 4. **Live/in-progress status indicators** — e.g. a small glow dot on an actively-building project's status badge, signaling "this is live/active" the way an LED would on real hardware. Reuses `--glow-sm`. |

**Explicitly not allowed, anywhere**: glow on card hover (that's `--shadow-md` now, §5), glow on every button (only primary CTAs get the focus-ring glow, and only on focus, not hover), glow as a decorative border, glow that cycles/animates/pulses (no breathing-neon effects), more than one glowing element visible at once in ordinary browsing.

---

## 7. Components

Standards for each, expressed as *deltas from today's actual CSS* where a current implementation exists, so this is a real spec, not a hypothetical:

### Buttons
Radius `--radius-sm` (now 10px, was 12px). `.btn-primary` uses `--color-primary`/`--color-primary-strong`, never glow — hover is a neutral `translateY(-1px)` (reduced from today's `-2px`, a subtler, more "precise" motion) plus a slight background lightening, no shadow change. Focus state gets `--glow-sm` (new — today's buttons have no distinct focus treatment beyond the browser default, a real gap this closes). `.btn-secondary` keeps the hairline-border treatment, border brightens to `--color-border-strong` on hover (not a primary-tinted border as today — `rgba(79,125,255,.4)` — since that's exactly the kind of incidental color-bleed this refresh is removing).

### Cards
Radius `--radius-lg` (20px, was 24px). Resting state: `--shadow-xs` (new — cards today have no resting shadow at all, only a hover one, which makes the whole grid look flat until you touch it). Hover state: `--shadow-md`, no color, plus the corner-bracket detail — a new, small, purely-CSS decorative treatment: four short hairline strokes at each corner (like a CAD selection/viewfinder mark) that fade in on hover. This is the single most distinctive, on-brand, *cheap* new visual signature this proposal introduces — it directly serves "technical" and "recognizable" without adding any color, glow, or clutter.

### Inputs
Radius `--radius-sm`. Resting border `--color-border`. Focus state: border color shifts to `--color-primary`, plus `--glow-sm` — this is the highest-value use of the whole glow system, since it's frequent (every form interaction) and functionally meaningful (clear focus indication was an 8D accessibility finding). Placeholder text `--color-text-muted`.

### Badges
Radius `--radius-pill` (unchanged). Two variants only: **filled** (solid `--color-surface-2` background, `--color-text-secondary` — the default, calm option, used for categories/status) and **outlined** (transparent background, `--color-border-strong` border, used sparingly for emphasis). Neither variant uses `--color-accent` — badges are informational, not highlights, so they stay out of glow territory entirely.

### Dropdowns
Radius `--radius-md`. Background `--color-surface-2` (one step up from the trigger's own surface, for clear layering). `--shadow-md` on the panel. Options use `--space-0`–`--space-1` internal padding (the new finer spacing step, §3) for tighter, more precise list density than today's more generous default spacing.

### Navigation
Height unchanged (`--navbar-height: 76px`). Background: the elevated surface at partial opacity with backdrop-blur (a small addition — a "frosted glass" scroll-aware navbar reads as considerably more premium than a flat-color bar, and is a one-property CSS addition, not a rebuild). Active nav link indicated by `--color-primary` text color plus a `1px` underline in `--color-primary` — no glow (frequent, low-stakes UI; glow here would violate the "one glowing element" discipline from §6 almost immediately).

### Progress bars
Track: `--color-surface-2`. Fill: `--color-primary` (not accent — progress is informational, not a highlight moment). Radius `--radius-pill`. No glow, no gradient fill — flat, precise, legible. This is a deliberate rejection of the "glowing progress bar" pattern common in gamified/gamer-adjacent UI, directly serving the avoid-list.

### Modals (new — no `.modal`/dialog component exists in the codebase today; confirmed via `Glob` across `css/components/*.css`, and confirmed behaviorally during Phase 9E testing that comment/gallery deletion currently uses the browser's native `confirm()`)
A real proposal, since this is genuinely new: `<dialog>`-element-based (native, accessible-by-default, no custom focus-trap JS needed), `--color-surface` background, `--radius-lg`, `--shadow-lg`, a scrim behind it at `rgba(10,11,15,0.72)` (using the new `--color-bg` value, not black, so it tints consistently with the rest of the palette). No glow. This closes a real, if minor, UX gap surfaced during Phase 9E (native `confirm()` dialogs are functional but visually and behaviorally inconsistent with the rest of the app) — worth noting as a byproduct of this milestone, not its purpose.

### Toasts
Background `--color-surface-2`, left border-accent in the relevant semantic color (`--color-success`/`--color-danger`/etc. — a `3px` solid left edge, not a full-border treatment, for a cleaner look than a fully colored box). `--radius-md`. `--shadow-md`. No glow — status feedback is functional, not a highlight moment.

### Iconography standards (new)

The codebase today uses icons inconsistently — some inline `<svg>` (e.g. the checklist icons in `renderReadinessChecklist.js`), some Unicode/text glyphs (e.g. the `→`/`↑` arrows scattered through card and upload-zone markup), no shared sizing or stroke convention. This section defines the **one system** every icon should belong to, closing that gap rather than adding another one-off treatment on top of it:

| Property | Standard | Rationale |
|---|---|---|
| Construction | Stroke-based (outline), never filled/solid glyphs, one shared source style (e.g. a Feather/Lucide-family icon set, or an equivalent small hand-drawn set built to the same rules) | Matches the "line-work, not illustration" language already proposed for empty states (§10) and the corner-bracket card detail (§7) — one construction method reads as one system |
| Stroke weight | `1.5px` at the base 20px size, scaling proportionally at other sizes (never a flat 1.5px regardless of size) | Consistent visual weight is what makes a mixed set of icons feel drawn by the same hand; a flat stroke width doesn't scale correctly and starts looking mismatched above/below the base size |
| Sizing scale | `16px` (inline with `--font-size-sm` text, e.g. metadata rows), `20px` (default — buttons, nav, most UI), `24px` (section/card-level emphasis icons), `32px` (empty-state icons, §10) — four sizes only, each tied to a real, named use, not an arbitrary range | A closed set of sizes is what makes icons feel systematic rather than ad hoc; if a new use case doesn't fit one of these four, that's a signal to reconsider the layout, not add a fifth size |
| Padding / hit target | Icon-only interactive controls (e.g. the notification bell, nav toggle) get a minimum `44×44px` hit target regardless of the visual icon size inside it (unchanged from the existing 8D accessibility standard — re-affirmed here, not replaced) | Carries forward, doesn't relitigate, the mobile-tap-target work already done in Phase 8D |
| Corner treatment | Rounded joins and caps (`stroke-linejoin: round`, `stroke-linecap: round`) on every icon, no mixing of sharp and rounded within the set | A small, easy-to-miss detail that's exactly the kind of consistency that separates "premium, considered" from "assembled from wherever" — the six Design Goals' "Premium" quality (above) is disproportionately made of details like this one |
| Color | `currentColor` always — never a hardcoded fill — so every icon inherits its context's text/icon color token automatically and never drifts out of sync with a future token change | Same reasoning as the empty-state icon treatment already proposed |

Unicode/text-glyph "icons" (the `→`/`↑` arrows currently in card and upload-zone markup) are replaced by real stroke icons under this system during implementation — not because they're currently broken, but because a text glyph can't carry a consistent stroke weight, and leaving them mixed in undermines the "one system" goal for the cheap cost of swapping a character for an inline SVG.

---

## 8. Motion

**Kept**: the three-tier duration system (`--duration-fast`/`--duration-normal`/`--duration-slow`) and the general timing values (150ms/220ms/350ms) — already reasonable, unchanged.

**Changed**: the easing curve. Today's `--ease-standard: cubic-bezier(0.2, 0.8, 0.2, 1)` has a slight overshoot character (the `0.8`/`1` control points create a gentle bounce-like deceleration) — pleasant, but reads as a touch "consumer app playful" rather than "precision tool." Replaced with `cubic-bezier(0.4, 0, 0.2, 1)` (Material Design's own "standard" curve, extremely well-tested, no overshoot, reads as controlled/mechanical rather than bouncy) for general UI transitions.

**Added**: a distinct, faster curve for the new corner-bracket card detail and focus-ring glow specifically — `--ease-precise: cubic-bezier(0.16, 1, 0.3, 1)` (a sharp deceleration, snappy-in/settle-out) — used only for these small, frequent, detail-level animations, so they feel crisp rather than sharing the same slightly slower rhythm as larger layout transitions (panel opens, page-level state changes), which keep `--ease-standard`.

| Token | Value | Use |
|---|---|---|
| `--duration-fast` | `150ms` | Unchanged — micro-interactions |
| `--duration-normal` | `220ms` | Unchanged — standard transitions |
| `--duration-slow` | `350ms` | Unchanged — panel/section transitions |
| `--ease-standard` | `cubic-bezier(0.4, 0, 0.2, 1)` | Changed — general-purpose, replaces the overshoot curve |
| `--ease-precise` (new) | `cubic-bezier(0.16, 1, 0.3, 1)` | New — corner-bracket reveal, focus-ring glow, other small detail animations |

No new animation *types* are introduced beyond what's already used (hover transforms, shimmer skeletons, dropdown reveals) — this section is entirely about making the existing motion vocabulary feel more precise, not adding new motion.

---

## Microinteractions (new section — the concrete catalog §8's tokens are applied through)

§8 defines the timing/easing *tokens*; this section is the standard for exactly which interaction gets which treatment, per component, so implementation has one reference table instead of inventing a transition per component on the fly.

| Component | Interaction | Treatment |
|---|---|---|
| Buttons | Hover | Background lightens one step, `translateY(-1px)`, `--duration-fast` / `--ease-standard` |
| Buttons | Active (pressed) | `translateY(0)` (returns to resting position — a real "press" feel, currently absent from the app entirely), `--duration-fast` |
| Buttons | Focus (keyboard) | `--glow-sm` ring fades in, `--duration-fast` / `--ease-precise` |
| Cards | Hover | `--shadow-xs` → `--shadow-md`, corner-bracket strokes fade in (§7), `--duration-normal` / `--ease-precise` for the brackets specifically (they should feel crisp/snappy, not lazy), `--ease-standard` for the shadow |
| Dropdowns | Open | Opacity + `translateY(-4px)→(0)` reveal, `--duration-fast` / `--ease-precise` — fast and snappy, since a slow-opening menu reads as laggy on a frequent interaction |
| Dropdowns | Close | Same reveal in reverse, `--duration-fast` (no slow fade-out — closing should feel immediate) |
| Progress bars | Value change | Fill width transitions (not jumps) over `--duration-slow` / `--ease-standard` — the one place a slightly longer duration is right, since progress changes are infrequent, meaningful events worth letting the eye follow |
| Modals | Open | Scrim fades in, panel scales `0.96→1` + opacity, `--duration-normal` / `--ease-precise` |
| Modals | Close | Reverse of open, `--duration-fast` (closing always faster than opening, throughout this table — consistent with how the dropdown pair works, a deliberate system-wide rule, not a per-component choice) |
| Toasts | Enter | Slide + fade from the toast stack's edge, `--duration-normal` / `--ease-precise` |
| Toasts | Exit (auto-dismiss or manual) | Fade + slight `translateY`, `--duration-fast` |

**A system-wide rule, not a per-row footnote**: closing/dismissing is always faster than opening/revealing, everywhere in this table. That asymmetry is a small thing but a consistent one, and consistent asymmetry reads as intentional design rather than arbitrary per-component timing — another detail in service of the "Premium" design goal.

**Respecting motion preference** (carried forward, not new — confirmed one `prefers-reduced-motion: reduce` query already exists in the codebase today): every microinteraction in this table must degrade to an instant/near-instant state change under `prefers-reduced-motion: reduce`, extending the existing pattern to the full table above rather than the one place it's currently applied.

---

## 9. Background system

**Layered surfaces**: already exists structurally (5-step surface ramp, kept per §1) — this section is about the *gradient* half of the ask, which is genuinely new.

One gradient treatment, kept deliberately singular and extremely subtle (this is where "avoid visual clutter" matters most, and per your review note this section is scoped down from the original proposal — no grid/graph-paper texture, removed outright rather than softened):

- **Ambient radial glow** (marketing surfaces only — homepage hero, Featured Spotlight backdrop): a single large soft radial gradient using `--color-accent` at very low opacity (`rgba(94, 234, 212, 0.06)` at its brightest point, fading to transparent), positioned off-center, fixed behind content. This is the "one ambient glow per page" from §6.3, described here as a background technique rather than a component effect. Never on interior/utility pages (Workshop, Settings, the editor) — those stay flat, calm, and undistracted, which is the right call for pages where someone is doing focused work, not being sold to.

This is an additive layer behind existing flat-color backgrounds — nothing about the current layout or content structure changes, only what sits behind it on two named marketing surfaces. No other background texture, pattern, or decorative layer is proposed anywhere in the application — every other surface stays a flat, calm, single-color background, exactly as today.

---

## 10. Brand assets

### Favicon / Assembly Mark
Kept: the rounded-square badge *format* (confirmed as the right direction, per your answer above) and its use as favicon/apple-touch-icon/OG-image element. Changed: the mark's fill color moves to the new `--color-primary` (`#4A5FE8`), and the mark itself is redrawn — today's is a hand-fitted bezier path shaped like a stylized "S" (from the Phase 9C quick-fix); this refresh proposes a more geometrically constructed version (built from precise arcs/straight segments at consistent angles, reinforcing "assembled/drafted" rather than "hand-drawn calligraphic"), still legible as an "S," still simple enough to read correctly at 16×16px. The PNG fallback/apple-touch-icon set (Phase 9D) regenerates from the same source at the same sizes — no new asset *types* needed, just re-exports.

### Open Graph image
Redesigned using the new palette, the refined Assembly Mark, and the new mono typeface for the version/tagline treatment — same 1200×630 dimensions and generation method (Pillow, per Phase 9D), updated content. Flat background (per §9's revision, no grid texture) — the visual interest comes from the mark, type, and the ambient radial glow treatment (§9), not a pattern.

### Loading screen
No full-page branded loading splash exists today (confirmed — the app uses in-content skeleton shimmer states, `css/components/skeleton.css`, which is good, modern practice and is **kept as-is architecturally, expanded on below**). No full-page splash is proposed — a delay/flash-of-unstyled-content risk for no real benefit on an already-fast static site.

---

## Skeleton Loading (new section — expanded from a color-refresh footnote into a full standard)

Today's skeleton system (`css/components/skeleton.css`) is a solid foundation — shimmer animation, a handful of shape variants (`.skeleton-text`, `.skeleton-title`, `.skeleton-image`, `.skeleton-avatar`) — but it isn't consistently *assembled* into full loading layouts per content type. Several loading states in the app today fall back to plain text ("Loading...") instead. This section defines the assembled skeleton layout for every major content type, so nothing in the app shows a bare loading string once implementation lands:

| Content type | Skeleton composition |
|---|---|
| **Feeds / grids** (Explore, Search results, Home) | A grid of card-shaped skeletons matching `BlueprintCard`'s real layout: `.skeleton-image` at the card's actual aspect ratio, `.skeleton-title`, two `.skeleton-text` lines, sized and spaced with the real card's padding tokens — so the loading state and the loaded state don't visually jump when content arrives |
| **Project/build cards** (Workshop, Dashboard) | Same card skeleton as above, reused — one shared skeleton component, not a separate one per page, consistent with the "one system" principle |
| **Profiles** | `.skeleton-avatar` at the real avatar size, a `.skeleton-title` for the display name, one `.skeleton-text` line for the bio, three small skeleton blocks for the stats row (followers/following/projects) |
| **Comments** | A repeated row: `.skeleton-avatar` (small) + two `.skeleton-text` lines of different widths (one shorter, mimicking natural comment-length variation rather than two identical bars, which reads more like real content settling in) |
| **Lists** (followers/following, notifications) | A repeated row: `.skeleton-avatar` (small) + one `.skeleton-text` line — the simplest composition, matching the simplest real row layout |

**Visual refresh** (the original proposal's scope, kept): the shimmer gradient's colors move to the new surface tokens (§1) — base `--color-surface-2`, shimmer highlight a lightened step of it, no color tint. **Timing**: shimmer animation duration and easing move to the new `--ease-standard` (§8) for consistency with every other motion in the system, rather than its own bespoke curve.

**Rule for implementation**: any view that currently shows a bare "Loading..." string gets one of the compositions above instead — this is a completeness bar (every loading state uses a real skeleton), not just a color update to the states that already have one.

---

## Empty States (new section — expanded into a full branded language)

Today's `.empty-state` (`css/components/emptystate.css`) is functional but generic — a dashed border, a heading, a paragraph, an optional button, and copy along the lines of "No projects found." This section replaces that with a deliberate, warm, on-brand language, while holding the line on the governing principle above: **subtle line-icons, not illustrations, and absolutely not a literal blueprint/graph-paper motif.**

### Iconography
One simple, outlined icon per context (per the Iconography Standards above: stroke-based, `1.5px` weight scaled to the `32px` empty-state size, `--color-text-muted`, rounded joins) — e.g. an outlined document/page glyph for "no builds yet," an outlined magnifying-glass for "no search results," an outlined bell for "no notifications," an outlined people/silhouette pair for "no followers yet." Simple enough that they read instantly, restrained enough that they never compete with real content — a small detail, not an illustration or a scene.

### Copy
Replacing generic system-message phrasing with copy that's specific to the context and quietly encouraging — written to sound like a person who's excited about what you might build, not a database returning zero rows:

| Context | Old-style generic copy | Proposed copy |
|---|---|---|
| No published builds on a profile | "No projects found." | "Nothing published yet — every great build starts with a first draft." |
| Empty Workshop (no drafts or builds) | "You have no projects." | "Your workshop is empty. Start documenting your first build." |
| No search results | "No projects matched your search." | "Nothing matches yet — try a different term or browse by category." |
| No comments on a build | "No comments yet." | "Be the first to weigh in on this build." *(kept close to today's existing copy for this one case — it already had the right tone; not every empty state needs rewriting, only the generic ones)* |
| No notifications | "No notifications yet." | "You're all caught up. New activity on your builds will show up here." |
| No followers | "No followers yet." | "No followers yet — publish a build to start building an audience." |

This is a representative set, not exhaustive — the same tone (specific, warm, forward-looking, never apologetic or robotic) applies to any other empty state found during implementation, following this table as the reference standard rather than a fixed final list.

---

## Responsive Design Rules (new section)

**Grounded in what's actually there today**: a repo-wide survey of every `@media` query currently in use found breakpoints clustering around `900px` and `700px` (10 and 7 uses respectively), with several near-duplicate outliers (`650px`, `600px`, `500px`, `720px`, `1100px` — each used once or twice, evidence of ad hoc per-component decisions rather than a shared system). This section formalizes three real breakpoints and consolidates the outliers into them during implementation — not a redesign of when things reflow, a cleanup of the inconsistent edges of an already-reasonable existing pattern.

### Breakpoints

| Name | Range | Replaces |
|---|---|---|
| Desktop | `≥901px` | Unchanged — today's implicit default |
| Tablet | `700–900px` | Consolidates today's `900px`, `1100px`, and `720px` queries onto one shared `900px` boundary |
| Mobile | `≤699px` | Consolidates today's `700px`, `650px`, `600px`, `500px` queries onto one shared `700px` boundary |

### Spacing
Desktop uses the full scale (§3) as documented. Tablet steps every layout-level spacing token (page margins, section gaps — not component-internal padding) down by one step (e.g. a `--space-6` section gap becomes `--space-5`). Mobile steps down by two from desktop (`--space-6` becomes `--space-4`). Component-internal spacing (button padding, card padding, form field gaps) stays constant across all three — only the macro, layout-level spacing compresses, so components themselves never feel cramped even as the page around them tightens up.

### Navigation
Desktop: full horizontal nav bar, all links visible (unchanged from today). Tablet: unchanged from desktop — the existing nav already fits comfortably down to `700px`, confirmed by the current breakpoint survey, so no new tablet-specific nav treatment is proposed. Mobile: collapses to the existing hamburger/toggle pattern (already implemented, Phase 3's mobile-interaction work) — kept as-is architecturally, only the toggle button and menu panel receive the new token values (radius, surface color, the `44×44px` icon hit-target standard above).

### Grids
Card grids (Explore, Search, Workshop, Home) use the same `repeat(auto-fill, minmax(...))` responsive pattern already in place today (confirmed working correctly in Phase 9C's regression testing) — kept unchanged, since it already reflows correctly at any width without a hard breakpoint. Fixed-column layouts (e.g. any place currently using an explicit multi-column grid rather than `auto-fill`) collapse to a single column at the Mobile breakpoint.

### Components
- **Cards**: unchanged structure at all sizes — the corner-bracket hover detail (§7) is suppressed below the Tablet breakpoint (a hover-only effect has no meaning on a touch device with no hover state, so it simply never triggers — not a separate mobile treatment, a natural consequence of it being a `:hover` rule).
- **Modals**: Desktop/Tablet render as a centered panel (§7's standard). Mobile renders full-screen (edge-to-edge, no visible scrim) — a standard, well-established mobile pattern for dialogs, and a genuine adaptation (not just a smaller centered box, which reads cramped on a small viewport).
- **Dropdowns**: Desktop/Tablet render as an anchored floating panel (§7's standard). Mobile renders as a bottom sheet (anchored to the viewport's bottom edge, full-width) — same reasoning as modals: an anchored floating panel is a poor fit for a small touch viewport, and a bottom sheet is the established mobile-native equivalent for the same interaction.
- **Toasts**: Desktop/Tablet stack in a corner (unchanged from today). Mobile stacks full-width at the top or bottom edge — corner-anchored toasts are hard to tap-dismiss accurately on a small screen.
- **Tables/data-dense layouts** (the Specifications grid, the Overview stat grid): collapse from their current multi-column arrangement to a single stacked column below the Mobile breakpoint, consistent with the existing pattern already used elsewhere in the app (confirmed: `dynamic-field-grid` and similar grids already do this today) — this rule formalizes what's already the working convention, not a new one.

---

## What this milestone does *not* touch

Explicitly out of scope, to keep this a design-system refresh and not a silent feature-scope creep:

- No change to information architecture, page structure, or navigation flow.
- No change to any component's *behavior* — only visual treatment (the one exception, modals, is a visual/consistency fix for an existing native-dialog gap, not new functionality).
- No change to the underlying build-with-no-bundler architecture — this remains a token-file-plus-component-CSS change, same deployment model as today.
- No change to Milestone 9's completed work (Storage/Auth architecture, deployment config, metadata) — this milestone is purely `css/` and brand-asset files.

---

## Proposed sequencing (implementation order)

1. **Token file first** (`css/base/tokens.css`): every new color/radius/shadow/glow/motion token, spacing half-steps, aliases repointed. Delivers a large fraction of the visual shift at the lowest risk (one file, no markup changes).
2. **Iconography** (§7.5): establish the icon set/sizing/stroke system early, since Empty States, Skeleton Loading, and several components below all consume it.
3. **Component-level CSS** (§7 + Microinteractions): buttons, cards, inputs, badges, dropdowns, nav, progress, toasts — updated to the new standards and interaction table.
4. **New modal component**: the one net-new piece of UI, built and swapped in for the native `confirm()` call sites found during Phase 9E.
5. **Skeleton Loading**: assembled compositions per content type, replacing any remaining bare "Loading..." text.
6. **Empty States**: icon + copy pass across every existing `.empty-state` usage.
7. **Responsive Design Rules**: breakpoint consolidation (900px/700px), the component-level adaptations (modals, dropdowns, toasts, tables).
8. **Background system** (§9): applied to the two named marketing surfaces only.
9. **Brand assets** (§10): Assembly Mark redraw, OG image regeneration.
10. **A visual regression pass** across the same page set this milestone's verification work has repeatedly used (home, explore, a build page, the editor, settings, login/signup), at desktop/tablet/mobile widths — screenshotted before/after, not just "looks fine."

Approved for implementation, per your review. Beginning with step 1.
