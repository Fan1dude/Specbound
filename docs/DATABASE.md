# Specbound Database Conventions

Status: Authoritative. Approved 2026-07-28.

These conventions are already followed consistently across all 18 migrations — this document writes them down for the first time so a future migration can be checked against something.

---

# Primary Keys

UUID primary keys, generated via `gen_random_uuid()` (the `pgcrypto` extension), consistent with the existing schema.

---

# Timestamps

`created_at timestamptz not null default now()` on every table that needs one.

`updated_at` is maintained by the database, not application code, via the shared `public.set_updated_at()` trigger function (defined once in `0001_project_drafts_and_media.sql`, reusable by any table via `create trigger ... execute function public.set_updated_at()`). Don't reinvent this per-table — attach the existing trigger.

---

# Row Level Security

Every user-owned table has RLS enabled. No exceptions, no "temporarily disabled for testing." This has held across all 18 migrations to date — keep it that way.

Public data (e.g. builder profiles, published projects) gets an explicit, deliberate public SELECT policy — never exposed by leaving RLS off.

Storage policies mirror table ownership and visibility (see `STORAGE_ARCHITECTURE.md`).

---

# Migrations

One file per migration, sequentially numbered (`000N_description.sql`), with a **paired rollback file** (`000N_description_rollback.sql`) every time, no exceptions. Forward migrations live in `supabase/migrations/`; their rollback pairs live in the separate `supabase/rollbacks/` folder, not alongside them — early on, rollback files sat in `supabase/migrations/` too, but a dry run against a real Supabase project showed its tooling treats every `.sql` file in that folder as a forward migration, applying rollbacks as if they were forward changes. Splitting the folders fixed that; each migration's own header comment points to its rollback's new location.

Each migration file opens with a header comment stating its purpose, status, and blast radius (what tables/policies it touches, what it explicitly does not touch) before any DDL. Read any file in `supabase/migrations/` for the pattern.

Schema migrations require approval before implementation — this isn't just a courtesy, it's how a static-file-deployed app with no CI safety net stays safe.

---

# Naming

Tables: `snake_case`, plural (`builds`, `project_drafts`, `comments`).

Ownership columns: `user_id`, referencing `auth.users(id) on delete cascade` (or the owning parent table, for child tables like `project_media` which check ownership through `project_drafts`).

Indexes: named for what they serve — `<table>_<columns>_idx` (e.g. `project_drafts_user_id_updated_at_idx`), added for the filters, joins, and ownership checks that actually run, not speculatively.

---

# Known Gap: The `profiles` Table

`profiles` and its `auth.users` trigger predate migration tracking — there's no tracked migration for its `CREATE TABLE` or the trigger that populates it on signup. This is a real audit-trail gap, not a design flaw (see `AUTH_ARCHITECTURE.md` for the full verification). Formalizing it into a tracked migration requires capturing the trigger's and function's exact current definitions first — `pg_get_triggerdef()`/`pg_get_functiondef()` output isn't reachable through the anon/authenticated PostgREST API this project's implementation environment has access to, so this step is blocked on a one-time, read-only introspection query run manually against the live database. Per explicit decision (2026-07-29), this does not block Version 1 — tracked as its own backlog item, "Formalize existing profiles trigger," in `ROADMAP.md`, not as a numbered milestone. See the Milestone 13 implementation report (2026-07-28) for the exact query needed.

---

# The Empty Top-Level SQL Files

Resolved in Milestone 13: `supabase/schema.sql`, `policies.sql`, and `triggers.sql` were removed. They were 0-byte files predating the migrations folder, not authoritative even when they existed — `supabase/migrations/` always was. Deleting them didn't lose any information; there was none to lose.

---

# Related Documents

- `ARCHITECTURE.md` — where this fits in the overall system
- `AUTH_ARCHITECTURE.md` — the `profiles` RLS story in full
- `STORAGE_ARCHITECTURE.md` — Storage bucket policy design
