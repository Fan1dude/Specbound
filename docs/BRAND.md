# Specbound Brand Guide

Status: Authoritative. Approved 2026-07-28. Supersedes `archive/design-system-v1.md`, `archive/design-v2.md`, and `archive/brand-pre-refresh.md`.

**Implementation status: this document describes the target brand. It is not yet implemented.** The live app currently ships a different palette (Deep Plum / Lavender Mist on near-black — see `css/base/tokens.css`) and a different logo mark. Rolling this document out to the actual product is Milestone 14. Nothing described below is true of the running app yet.

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

This replaces the rounded-square badge / two-arc-S mark shipped in Milestone 10 Step 9.

---

# Color System

| Token | Hex | Use |
|---|---:|---|
| Background | `#4F4C55` | Main app canvas |
| Background Alt | `#5B5861` | Secondary regions |
| Surface | `#696570` | Cards and panels |
| Surface Elevated | `#77727F` | Menus and dialogs |
| Border | `#8A8491` | Dividers and field outlines |
| Primary Lavender | `#B79AE6` | Main actions and active states |
| Primary Hover | `#C4AAEC` | Hover and selected emphasis |
| Primary Pressed | `#A987DA` | Pressed controls |
| Text Primary | `#F7F5FA` | Main text |
| Text Secondary | `#D8D3DE` | Supporting text |
| Text Muted | `#B9B2C1` | Metadata |
| Success | `#A8C7AE` | Confirmed success |
| Warning | `#D8B77A` | Caution |
| Danger | `#D98E8E` | Destructive or failed states |

**Purple is an accent, not wallpaper.** Use it for primary buttons, active navigation, focus rings, links, and meaningful progress. Most of the interface stays graphite, gray, and soft white so builder work remains the visual focus.

**Explicitly prohibited:** gradients, glows, neon styling, gaming aesthetics, or highly saturated Discord-like purple. This is a firmer constraint than the source brand package stated, and it governs: no ambient glow effects (the homepage's current fixed-gradient lighting system from the Milestone 10 refinement pass does not carry forward under this brand), no neon or oversaturated purple, no glassmorphism.

WCAG AA contrast must be reverified for this palette before Milestone 14 ships it — do not assume "calmer" implies compliant. See the implementation report (2026-07-28) for the verification methodology already established in this project (relative-luminance calculation, not just visual judgment).

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
