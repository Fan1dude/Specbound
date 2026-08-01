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

# Known Gap: `profiles`, `builds`, `build_revisions` Predate Tracking

`profiles`, `builds`, and `build_revisions` — plus the `auth.users` trigger that populates `profiles` on signup — all predate this repo's migration-tracking convention. No tracked migration created any of the three; every migration from `0001` onward only ever `ALTER`s them or adds a foreign key to them, silently assuming they already existed. This was long known and explicitly documented for `profiles` specifically (see `AUTH_ARCHITECTURE.md` §1-2) — `builds`/`build_revisions` had the identical gap without ever being called out, and it only surfaced 2026-08-01 when a from-empty-database dry run of `0001`-`0023` against a fresh Supabase project failed at `0002` with `relation "public.builds" does not exist`.

**Fixed**: `0000_baseline_pre_tracked_tables.sql` (added 2026-08-01, numbered `0000` rather than renumbering anything — see that file's own header) reconstructs all three tables and the signup trigger from evidence across the tracked migrations and application code, letting a brand-new project bootstrap from `0000` through `0023` with no manual intervention.

**What this does and doesn't close**: `0000` is a reconstruction good enough for fresh-project bootstrapping — it is *not* a captured, verified-identical copy of the real production database's actual table definitions or trigger function body. That verification still requires a one-time, read-only introspection query (`pg_get_triggerdef()`/`pg_get_functiondef()`) run manually against the live project, which remains out of reach from this implementation environment (anon/authenticated PostgREST access only). Still tracked as its own backlog item, "Formalize existing profiles/builds/build_revisions against real production schema," in `ROADMAP.md` — narrower in scope now that `0000` exists, but not fully closed.

---

# The Empty Top-Level SQL Files

Resolved in Milestone 13: `supabase/schema.sql`, `policies.sql`, and `triggers.sql` were removed. They were 0-byte files predating the migrations folder, not authoritative even when they existed — `supabase/migrations/` always was. Deleting them didn't lose any information; there was none to lose.

---

# Related Documents

- `ARCHITECTURE.md` — where this fits in the overall system
- `AUTH_ARCHITECTURE.md` — the `profiles` RLS story in full
- `STORAGE_ARCHITECTURE.md` — Storage bucket policy design
