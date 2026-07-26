# Blueprint Design System

Version: 1.0
Status: Locked for Specbound Version 1.0

## Brand

- Product: Specbound
- Design system: Blueprint Design System
- Primary mark: Hexagonal S
- Primary font: Inter
- Primary accent: Electric blue
- Default appearance: Dark

## Product language

- Blueprint: the plan
- Project: the active process
- Build: the completed result
- Project Log: documented updates

## Core geometry

- Cards: 24px radius
- Controls: 12px radius
- Inputs: 12px radius
- Pills: full radius
- Category symbols: hexagonal frames

## Spacing

Use only the 8px spacing scale:

8, 16, 24, 32, 48, 64, 80, 96, 120

## Buttons

Only these variants:

- Primary
- Secondary
- Ghost
- Danger

Only these sizes:

- Small
- Default
- Large

## Cards

Only these variants:

- Default
- Elevated
- Interactive
- Outlined

## Images

- Blueprint cover: 16:9
- Project Log image: maximum 16:9 display
- Profile image: 1:1
- Category illustration: SVG
- Use object-fit: cover for uploaded photos

## Icons

- Custom category symbols
- Lucide for ordinary interface actions
- 48×48 source grid
- Rounded line construction
- Consistent visual weight
- Category icons use CSS masks and category accent colors

## Motion

- Fast: 150ms
- Normal: 220ms
- Slow: 350ms
- Motion must clarify interaction
- Avoid decorative motion that delays the user

## Accessibility

- Visible keyboard focus
- Alt text on meaningful images
- Labels for form controls
- Minimum readable contrast
- Do not rely on color alone for status

## Voice

Specbound sounds:

- Clear
- Encouraging
- Technical
- Human

Avoid exaggerated startup language and unnecessary jargon.

## Final rule

New components must use existing tokens.  
Do not introduce a new color, spacing value, radius, shadow,
font size, or animation timing without updating this document.