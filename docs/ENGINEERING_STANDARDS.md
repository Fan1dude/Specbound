# Specbound Engineering Standards

Version: 1.0

Last Updated: July 2026

Status: Authoritative, kept from the original numbered doc series. Renamed from `00-Engineering-Standards.md` and lightly updated (example names below) to match `TERMINOLOGY.md`, approved 2026-07-28.

---

# Purpose

These standards exist to keep Specbound maintainable, scalable, and consistent as the project grows.

Every line of code should follow these guidelines.

---

# Core Philosophy

We optimize for:

- Readability
- Reusability
- Simplicity
- Performance
- Accessibility

Never optimize for cleverness.

Future developers should understand the code immediately.

---

# Folder Responsibilities

assets/
Only static assets.

css/
Only styling.

js/components/
Reusable UI components.

js/core/
Core platform functionality.

js/config/
Configuration and constants.

js/features/
Feature-specific logic.

js/services/
Business logic.

js/repositories/
Database access.

js/utils/
Pure utility functions.

pages/
Only HTML pages.

docs/
Documentation only.

---

# Naming

## HTML

lowercase-with-dashes.html

Example

profile.html

---

## CSS

One component per file.

button.css

card.css

badge.css

---

## JavaScript Components

PascalCase

ProjectCard.js

BuilderCard.js

SearchBar.js

(Existing files still use the prior naming — e.g. `BlueprintCard.js` — see `TERMINOLOGY.md`'s Migration Status. New components should follow the naming above; existing ones are renamed only as part of an approved migration, not incidentally.)

---

## Utilities

camelCase

formatDate.js

slugify.js

timeAgo.js

---

## Variables

camelCase

const buildCount

const creatorName

---

## Classes

PascalCase

Project

Builder

BuildLog

---

# CSS Rules

Never hardcode repeated values.

Bad

padding: 18px;

Good

padding: var(--space-2);

Always use design tokens.

No inline styles.

One responsibility per CSS file.

---

# HTML Rules

Semantic HTML first.

Always use:

header

main

section

article

aside

footer

Avoid unnecessary div nesting.

---

# JavaScript Rules

One responsibility per file.

Pages never contain business logic.

Business logic belongs in Services.

Database access belongs in Repositories.

Components only render UI.

Utilities never touch the DOM.

---

# Import Order

1. Core
2. Config
3. Services
4. Repositories
5. Components
6. Utilities

---

# Database

Never access Supabase directly from components.

Always go through repositories.

---

# Accessibility

Every image needs alt text.

Every input needs a label.

Keyboard navigation must work.

Visible focus states are required.

---

# Performance

Lazy load large images.

Avoid duplicate queries.

Reuse components.

Avoid unnecessary DOM updates.

---

# Mobile

Every feature must work on desktop and mobile.

Mobile is never an afterthought.

---

# Security

Never trust client input.

Validate uploads.

Sanitize text.

Respect Row Level Security.

Never expose secrets in frontend code.

---

# Git

Commit often.

Commit messages should explain why.

Example

feat: add project card component

fix: correct builder archive routing

refactor: move upload logic into service

---

# Pull Request Checklist

Before merging:

- Code works
- No console errors
- Responsive
- Accessible
- Uses design tokens
- Uses reusable components
- No duplicated logic

---

# The Golden Rule

Pages assemble.

Components render.

Services perform.

Repositories fetch.

Utilities help.

Config defines.

---

# Related Documents

- `ARCHITECTURE.md` — how these standards show up in the actual system
- `TERMINOLOGY.md` — the naming this document's examples follow
