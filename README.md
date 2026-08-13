# Specbound

Specbound is a platform for documenting technology projects — PC builds, desk setups, Arduino projects, robotics, 3D printing, and home labs — with structured specifications, build logs, and a public profile for each builder.

**Production:** https://specboundapp.com

Share where it starts, not just where it finishes.

---

## What Specbound is

Most project documentation ends up scattered across forum threads, social posts, and photo dumps that disappear over time. Specbound gives each project a permanent, structured home: a parts/specifications list, a revision history as the build changes, and a public page other builders can actually learn from — not just look at.

---

## Current capabilities

Everything below is implemented in this repository and backed by a real Supabase schema, not a design placeholder.

**Account & access**
- Email/password sign-up with confirmation, login, logout, and password recovery
- A short first-time onboarding flow (welcome + starting technology selection)
- Discord account linking via Supabase Auth's native identity-linking, with an owner-controlled toggle for whether the connection shows on a public profile

**Project documentation**
- A project editor with autosaved drafts, a specifications/components section backed by a moderated parts catalog, a resources/links section, an image gallery, and a readiness checklist before publishing
- Publish/unpublish control, with every published change tracked as a revision (a build log, not just a single edited page)
- A paste-based parts-list import (compatible with PCPartPicker/BuildCore-style exports) that suggests catalog matches for review — nothing is saved without the builder confirming it

**Discovery**
- Explore and Search pages, plus six dedicated category pages (PC Builds, Desk Setups, Arduino, Robotics, 3D Printing, Home Labs) with filtering

**Community**
- Comments, likes, saves, and a following/followers system on top of every published project
- A notification system for the activity that follows from those
- Comment-level automatic role badges and a moderator-facing manual role-granting control

**Safety & feedback**
- A Community Guidelines acceptance gate before a builder's first publish or comment
- In-app content reporting and a feedback-submission form

Two features exist but are intentionally partial today, and this README won't claim otherwise: content reports and feedback are captured in the database with no in-app review/triage screen yet, and beta invite codes can be redeemed in-app but are currently generated outside the app. The legal pages (Terms, Privacy, Community Guidelines, Affiliate Disclosure) exist and are linked from every page's footer, but their content is still placeholder/draft text pending final legal review.

---

## Builder Portfolio

Every account has a public profile page — a builder's portfolio, not just an author byline. It includes a headline, an about section, a chronological build journey, a technology breakdown of what the builder works in, an optional featured project, a full project gallery, a follow button, and — when the owner has enabled it — a public Discord connection linking out to their Discord profile.

---

## Technology stack

Specbound is a static site with **no build step, no bundler, and no framework** — every file is served exactly as committed.

- **Frontend:** static HTML, CSS, and JavaScript ES modules (no framework, no root-level `package.json`)
- **Backend:** [Supabase](https://supabase.com) — Auth (including native OAuth identity-linking), a PostgreSQL database governed by Row Level Security on every table, and Storage for images
- **Hosting:** [Cloudflare Pages](https://pages.cloudflare.com/), deployed directly from this repository on every push to `main` — see `docs/DEPLOYMENT.md`
- **CI:** GitHub Actions running this repository's own static-analysis and browser-test tooling under `tools/ci/` — see `docs/CI.md`

---

## Repository structure

```
index.html, 404.html, pages/        Every real page (auth, editor, explore, profile, legal, ...)
js/
  core/          App bootstrap: layout, auth, Supabase client, onboarding
  pages/         Per-page bootstrap + rendering logic, one folder per page
  components/    Shared UI components (modals, cards, role badges, ...)
  repositories/  All Supabase reads/writes, grouped by domain
  services/      Cross-cutting logic (e.g. draft autosave)
  utils/         Small stateless helpers
  config/        Static config (technology categories, field definitions)
css/             Design tokens, shared components, per-page styles
assets/          Brand assets, icons, illustrations
supabase/
  migrations/    Every schema change, sequential and additive
  rollbacks/     A paired rollback for every migration
  tests/         SQL test suites, run against a disposable local database
  migrations.md  Human-readable migration log and status tracker
tests/           Browser-based regression tests (tests/*.test.html)
tools/ci/        CI scripts (syntax, references, accessibility, CSP, domain checks)
docs/            Architecture, deployment, and setup documentation
```

---

## Local development

There is no build step. To work on the frontend:

- Open any `.html` file directly in a browser, or
- Serve the repository root with any static file server (the repo includes `.claude/nocache_server.py` for this, used by this project's own tooling)

Either way, the app talks to Specbound's real Supabase project using the publishable client key already committed in `js/core/config.js` — safe for client-side exposure by design (see `docs/STORAGE_ARCHITECTURE.md` / `docs/AUTH_ARCHITECTURE.md` for why). No `.env` file or local secret is required to run the frontend.

To run this repository's CI checks locally, see `docs/CI.md` §3 — briefly:

```bash
node tools/ci/check-syntax.js
node tools/ci/check-references.js
```

```bash
cd tools/ci
npm install
npx playwright install --with-deps chromium
cd ../..
node tools/ci/run-tests.js
```

The SQL test suites under `supabase/tests/` are separate: they run against a disposable local Supabase/Docker stack (`supabase db reset --local`), never against production, and require the Supabase CLI and Docker installed locally.

---

## Testing and verification

**Run automatically by GitHub Actions on every push and pull request:**

- A browser-based regression suite (`tests/*.test.html`, driven headlessly via Playwright)
- JavaScript syntax validation across every source file
- Local reference checking (every `src`/`href`/`url()`/import resolves to a real file)
- Accessibility regression checks against known bug classes
- CSP/bootstrap validation (no inline scripts or styles the production Content-Security-Policy would block)
- Production-domain validation (no leftover placeholder domain in shipped pages or crawler config)

See `docs/CI.md` for exactly what each check covers and its known limitations.

**Not part of CI — run separately, by hand, against disposable local Supabase/Docker infrastructure:**

- SQL migration and Row Level Security policy tests (`supabase/tests/`), run against a local `supabase db reset --local` stack, never against production or as part of any automated pipeline

This split is deliberate: the CI checks above need nothing but Node, while the SQL suite needs the Supabase CLI and Docker running locally — see [Local development](#local-development) above.

---

## Documentation

- [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md) — Cloudflare Pages hosting, deploy flow, and production configuration
- [`docs/DISCORD_SETUP.md`](docs/DISCORD_SETUP.md) — Discord account-linking configuration and verification checklist
- [`docs/CI.md`](docs/CI.md) — what runs automatically, what still needs manual/browser verification
- [`docs/AUTH_ARCHITECTURE.md`](docs/AUTH_ARCHITECTURE.md) — the auth/profile/RLS model
- [`docs/STORAGE_ARCHITECTURE.md`](docs/STORAGE_ARCHITECTURE.md) — Storage bucket layout and access policy

---

## Current status

Specbound is live at https://specboundapp.com and under active, ongoing development. Account creation, project documentation, discovery, and the core community features listed above are built, deployed, and — for Discord account linking specifically — manually verified end-to-end in production (connect, OAuth return, username sync, public visibility toggle, refresh, and disconnect). Database migrations are current in production through the latest applied migration.

Not everything is finished: in-app generation of beta invite codes and final legal-page content are still open work, called out explicitly above rather than left implicit. In-app moderator tooling for reviewing content reports is built and deployed (a moderator-only report queue, resolvable per-report).

---

## Credit

Created by Odane Bernard Jr.
