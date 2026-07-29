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

One file per migration, sequentially numbered (`000N_description.sql`), with a **paired rollback file** (`000N_description_rollback.sql`) every time, no exceptions.

Each migration file opens with a header comment stating its purpose, status, and blast radius (what tables/policies it touches, what it explicitly does not touch) before any DDL. Read any file in `supabase/migrations/` for the pattern.

Schema migrations require approval before implementation — this isn't just a courtesy, it's how a static-file-deployed app with no CI safety net stays safe.

---

# Naming

Tables: `snake_case`, plural (`builds`, `project_drafts`, `comments`).

Ownership columns: `user_id`, referencing `auth.users(id) on delete cascade` (or the owning parent table, for child tables like `project_media` which check ownership through `project_drafts`).

Indexes: named for what they serve — `<table>_<columns>_idx` (e.g. `project_drafts_user_id_updated_at_idx`), added for the filters, joins, and ownership checks that actually run, not speculatively.

---

# Known Gap: The `profiles` Table

`profiles` and its `auth.users` trigger predate migration tracking — there's no tracked migration for its `CREATE TABLE` or the trigger that populates it on signup. This is a real audit-trail gap, not a design flaw (see `AUTH_ARCHITECTURE.md` for the full verification). Formalizing it into a tracked migration — capturing current behavior exactly, not a reimagined version — is Milestone 13.

---

# The Empty Top-Level SQL Files

`supabase/schema.sql`, `policies.sql`, and `triggers.sql` currently exist as 0-byte files, dated before the migrations folder started. They're not authoritative — `supabase/migrations/` is. Resolving these (populate as a generated current-state snapshot, or remove them) is also Milestone 13.

---

# Related Documents

- `ARCHITECTURE.md` — where this fits in the overall system
- `AUTH_ARCHITECTURE.md` — the `profiles` RLS story in full
- `STORAGE_ARCHITECTURE.md` — Storage bucket policy design
