# Specbound Architecture

Status: Authoritative. Approved 2026-07-28. Supersedes `archive/architecture-v0.7.md`.

This is a short current map of how the system is actually built, not a restatement of the detailed docs it points to. For the two areas with real depth — auth/RLS and storage — read `AUTH_ARCHITECTURE.md` and `STORAGE_ARCHITECTURE.md` directly; this document won't duplicate them.

---

# Stack

Vanilla HTML, CSS, and JavaScript (ES modules), no bundler, no framework. Supabase for auth, Postgres, and Storage. Deployed as static files.

This is a deliberate choice, not a gap — see `ENGINEERING_STANDARDS.md` and the master prompt's "existing implementation rule": preserve the current stack unless the owner explicitly approves a migration. Do not introduce a bundler or framework as a side effect of any other work.

---

# Folder Layout

```
assets/        static assets only
css/           base/, components/, layout/, pages/, themes/
js/            components/, config/, core/, features/, pages/, repositories/, services/, utils/
pages/         HTML pages only
supabase/      migrations/ (each with a paired rollback), policies.sql, schema.sql, triggers.sql
docs/          this folder
tests/         manual browser test harnesses (*.test.html)
```

See `ENGINEERING_STANDARDS.md` for the full naming and layering conventions. The short version, enforced in practice: Pages assemble. Components render. Services perform business logic. Repositories are the only thing allowed to talk to Supabase. Utilities are pure and never touch the DOM.

---

# Data Model, at a Glance

Using the terminology from `TERMINOLOGY.md` (see that document's Deprecated Terms table for how these map onto current table/file names, which have not been renamed):

- **Builder** → `profiles` table. Created via an untracked `auth.users` trigger, not a migration — see `AUTH_ARCHITECTURE.md` for the full story and `DATABASE.md` for the plan to formalize it.
- **Project** → `builds` (published) and `project_drafts` (private editing state), linked via `project_media` and `revision_media` for images.
- **Build Log** → `build_revisions`.
- **Comments, Follows, Notifications** → `comments`, `follows`, `notifications` tables. Approved community features per `SCOPE.md`.
- **Likes, Activity Feed** → `likes` table, `activity_feed` view. Exist today, not approved for Version 1 per `SCOPE.md` — see that document's Known Gap section.

Every user-owned table has Row Level Security enabled. See `DATABASE.md` for the conventions this is built on.

---

# Security Posture, at a Glance

RLS on every table, a real Content-Security-Policy with no `unsafe-inline` (see `_headers`), consistent `escapeHtml`/`escapeAttribute` use in rendered markup, no secrets in client code. Full detail: `AUTH_ARCHITECTURE.md`, `STORAGE_ARCHITECTURE.md`, and the implementation report (2026-07-28).

---

# Related Documents

- `ENGINEERING_STANDARDS.md` — naming, layering, and code-review conventions
- `AUTH_ARCHITECTURE.md` — auth and profile RLS in full detail
- `STORAGE_ARCHITECTURE.md` — Storage bucket policy design in full detail
- `DATABASE.md` — schema conventions (UUIDs, timestamps, migrations, RLS-by-default)
- `DEPLOYMENT.md` / `OPERATIONS.md` — how this actually ships and runs
