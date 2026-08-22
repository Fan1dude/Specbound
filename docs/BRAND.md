# Specbound Brand Guide

Status: Authoritative. Approved 2026-07-28. Supersedes `archive/design-system-v1.md`, `archive/design-v2.md`, and `archive/brand-pre-refresh.md`.

**Implementation status: shipped (Milestone 14, 2026-07-29).** `css/base/tokens.css` and the logo assets under `assets/brand/` now implement this brand. The Color System table below shows the values as actually shipped, not the package's original proposal — see that section for why several were adjusted and the full verification methodology.

---

# Brand Idea

Specbound is the permanent home for every builder's journey.

Public message:

> Share where it starts, not just where it finishes.

The brand should feel like a precision engineering notebook inside a premium design tool: calm, intentional, trustworthy, modular, and built to last.

It should feel: calm, modular, purposeful, professional, premium, timeless, builder-first.

It should not feel: like Discord, gaming-focused, neon, cyberpunk, crypto-related, like a generic AI startup, cluttered, overly white, trend-driven.

---

# Logo System

The Specbound symbol is a rounded modular assembly that creates a clear **S** through negative space.

The modules represent: building blocks, iteration, connected knowledge, projects becoming complete through many smaller steps.

Wide gaps between tiles make the mark readable at small sizes. Rounded geometry keeps it approachable without losing engineered structure.

**Clear space:** at least one tile-gap width around the symbol. No text, borders, or other marks inside that space.

**Minimum size:** symbol 16px minimum; full lockup 120px minimum width. Below 120px, use the symbol alone.

**Approved use:** lavender mark on graphite or white; white mark on dark photographic backgrounds; dark mark on light neutral backgrounds; monochrome when color is unavailable.

**Never:** close or remove the tile gaps. Sharpen the corners. Stretch, rotate, skew, or outline the mark. Add glows, gradients, bevels, or 3D effects. Recolor individual tiles. Place the mark on a low-contrast background.

**Approved exception (2026-08-22), homepage hero mark only:** the prominent homepage logo (`index.html`'s `.hero-mark`, animated in `css/pages/home/home.css`'s `hero-mark-highlight` keyframes) cycles a single tile at a time to the existing `--primary` token with a small `filter: drop-shadow` glow, clockwise, ~600ms per tile. Deliberately narrow — every other instance of the mark (navbar, footer, favicon, any static rendering) is untouched by this exception and still follows the "Never" rule above exactly as written. Disabled entirely under `prefers-reduced-motion: reduce`, which shows the plain static mark this rule already describes.

This replaces the rounded-square badge / two-arc-S mark shipped in Milestone 10 Step 9.

---

# Color System

As shipped (`css/base/tokens.css`), WCAG AA-verified. Every fill/badge color below is the package's original proposal, unchanged — these work as given because dark ink text sits on them, not white. Every surface and text color needed adjustment; see the notes column for why. Full contrast table in the Milestone 14 implementation report (2026-07-29).

| Token | Hex | Use | Note |
|---|---:|---|---|
| Background | `#4F4C55` | Main app canvas | Unchanged from the original proposal |
| Background Alt | `#54515A` | Secondary regions | Compressed from the proposed `#5B5861` |
| Surface | `#57545D` | Cards and panels | Compressed from the proposed `#696570` |
| Surface Elevated | `#5A5760` | Menus and dialogs | Compressed from the proposed `#77727F` — that value mathematically cannot support legible text at any tier (even the brightest text color only reaches 4.31:1 against it) |
| Border | `#ADA8B2` | Dividers, field outlines | Lightened from the proposed `#8A8491`, which only cleared WCAG's 3:1 non-text minimum against Background itself, failing against every surface above it |
| Border Strong | `#BCB7C1` | Hover/emphasis borders | New — a second, more visible step |
| Primary (text/links/icons) | `#DBC9F5` | Links, icons, active nav text | New — the proposed Primary Lavender fails badly as text (3.51:1 against Background); this is a lightened derivative reserved for text/link/icon use |
| Primary Fill | `#B79AE6` | Primary buttons, active-state fills | The original proposed "Primary Lavender," unchanged — pairs with dark ink text (`--color-text-inverse`), never white |
| Primary Fill Hover | `#C4AAEC` | Fill hover | Unchanged from the original proposal |
| Primary Pressed | `#A987DA` | Pressed fill state | Unchanged from the original proposal |
| Text Primary | `#F7F5FA` | Main text | Unchanged from the original proposal |
| Text Secondary | `#DBD6E1` | Supporting text | Nudged 3 units lighter than proposed so it clears Surface Elevated too |
| Text Muted | `#D4CEDA` | Metadata | Meaningfully lightened from the proposed `#B9B2C1`, which only measured 4.08:1 even against Background, the darkest tier |
| Text Inverse | `#17151C` | Text on light fills (buttons, badges) | New — not specified in the original package; white text fails on every light fill this palette has |
| Success (text) | `#C0D9C4` | Status text | Lightened from the fill value for small-text use |
| Success Fill | `#A8C7AE` | Fills, large badges | Unchanged from the original proposal |
| Warning (text) | `#E5CDA3` | Status text | Lightened from the fill value |
| Warning Fill | `#D8B77A` | Fills, large badges | Unchanged from the original proposal |
| Danger (text) | `#EEC9C9` | Status text | Lightened from the fill value |
| Danger Fill | `#D98E8E` | Fills, large badges | Unchanged from the original proposal |
| Info | `#BDD1E7` | Informational status | New — not specified in the original package |

**Purple is an accent, not wallpaper.** Use it for primary buttons, active navigation, focus rings, links, and meaningful progress. Most of the interface stays graphite, gray, and soft white so builder work remains the visual focus.

**Explicitly prohibited, and removed during implementation:** gradients, glows, neon styling, gaming aesthetics, or highly saturated Discord-like purple. Every former focus-ring glow now uses a solid, zero-blur ring instead (`--focus-ring`); the homepage's fixed ambient-gradient background (from the Milestone 10 refinement pass) was removed entirely, not just left unreferenced.

**A structural finding, not a style choice:** the surface ramp above is far more compressed than the original package proposed. The math doesn't allow otherwise — Background's own luminance is low enough that a genuinely "muted" text tone (dim enough to read as a third tier below Primary/Secondary, not a near-duplicate of them) cannot clear 4.5:1 against a surface as light as the original `#77727F`. Panels read as distinct primarily via border and shadow now, not a large background-color jump — which is also more consistent with this document's own "quiet elevation, restrained shadows" language than a dramatic ramp would have been.

---

# Typography

Preferred family: **Inter**

Fallback stack: `Inter, ui-sans-serif, system-ui, -apple-system, "Segoe UI", sans-serif`

| Style | Size / Line height | Weight |
|---|---|---|
| Display | 48 / 56 | 700 |
| H1 | 36 / 44 | 700 |
| H2 | 28 / 36 | 650 |
| H3 | 22 / 30 | 650 |
| Body large | 18 / 28 | 400 |
| Body | 16 / 24 | 400 |
| Small | 14 / 20 | 400 |
| Caption | 12 / 16 | 500 |

Use sentence case. Avoid excessive uppercase outside compact labels.

---

# Interface Character

- 8px spacing grid
- Buttons and inputs: 12px radius
- Cards: 16px radius
- Dialogs: 20px radius
- Thin rounded icons, consistent stroke widths
- 150–200ms ease-out motion
- Quiet elevation, restrained shadows
- No glassmorphism, neon glow, cyberpunk styling, or gaming UI conventions
- Subtle ambient workshop backgrounds are allowed — blueprint grids, PCB traces, CAD diagrams, gears, or knowledge-graph lines at low contrast — and must never distract from content. This is a texture/pattern allowance, distinct from the glow prohibition above: a faint static line pattern is permitted; a glowing light effect is not.

---

# Brand Voice

**Confident:** believes in builders without exaggeration.

**Clear:** explains complex ideas simply.

**Respectful:** treats every project as meaningful.

**Human:** practical, direct, and encouraging.

**Quietly motivating:** supports progress without hype.

Avoid cringy slogans, startup clichés, exaggerated claims, and engagement-focused language.

---

# Brand Decision Test

Before approving a visual or message, ask:

1. Does it feel engineered rather than trendy?
2. Does it keep the builder's work as the hero?
3. Is it calm enough for long work sessions?
4. Will it still feel appropriate in five years?
5. Does it strengthen trust?

If most answers are no, revise it.

---

# Related Documents

- `VISION.md` — what this brand is in service of
- `ARCHITECTURE.md` — where design tokens actually live in code (`css/base/tokens.css`)
