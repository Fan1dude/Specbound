-- Migration: 0000_baseline_pre_tracked_tables
-- Milestone: none — retroactive baseline, added 2026-08-01, corrected
-- 2026-08-01 after a second dry run, corrected again the same day after a
-- third dry run reached 0017 and failed on a missing storage.objects
-- policy.
--
-- Purpose: public.profiles, public.builds, public.build_revisions, the
-- project-images Storage bucket, and four of its RLS policies all predate
-- this repo's migration-tracking convention — they were already live in
-- the real Supabase project before supabase/migrations/ started, and no
-- tracked migration anywhere creates any of them. Every migration from
-- 0001 onward only ever ALTERs the three tables or adds foreign keys to
-- them; 0017_storage_rls_hardening.sql's own header goes further and
-- states outright that its four DROP POLICY targets "predate migration
-- tracking" and match "Supabase's own dashboard-generated default-policy
-- template names/shapes" — i.e., created via the dashboard UI, never
-- through a migration, same story as the three tables.
--
-- Numbered 0000, not renumbered into the existing sequence — this
-- project's migration convention (docs/DATABASE.md) is that files are
-- "never reused, never renumbered." 0000 sorts before 0001 by both
-- lexical and numeric ordering, which is all that's required for a
-- migration meant to represent "state that existed before 0001."
--
-- CORRECTION (2026-08-01): the first version of this file reconstructed
-- the CURRENT (post-0023) shape of these three tables — it included
-- columns that later migrations add via their own ALTER TABLE
-- statements. Applying 0000 then running forward hit "column already
-- exists" at 0002 (builds.visibility), then again at 0003
-- (profiles.avatar_path) — proof by repeated failure that the
-- reconstruction method itself was wrong, not just those two columns.
-- This version represents the schema strictly as it stood immediately
-- BEFORE 0001, built by auditing every ALTER TABLE statement against
-- these three tables across 0001-0023 and excluding every column any of
-- them adds — each such column is added instead by the migration that
-- was always meant to add it, unchanged. Full audit report: see the
-- implementation notes for this correction (git log message on this
-- file's amending commit) for the complete list of what was removed and
-- which migration now correctly owns each one.
--
-- Evidence standard: a column is included below only if either (a) a
-- migration's own header comment explicitly confirms it already existed
-- before that migration ran (builds.likes_count per 0008, builds.views
-- per 0010, builds.metadata per 0004 — all three state this directly,
-- quoted inline below), or (b) application code reads/writes it and no
-- tracked migration (0001-0023) ever adds it via ALTER TABLE — the only
-- remaining explanation being that it predates tracking entirely, same
-- as the table itself. No index or constraint is included unless it
-- meets the same standard — an earlier draft invented two indexes
-- (`builds_user_id_idx`, `build_revisions_build_id_idx`) that no
-- migration or comment ever evidenced; both are removed here rather than
-- left as unverified guesses about what "should" exist.
--
-- Deliberately NOT included despite being real production behavior, for
-- the same "restore the actual history, don't paper over it" reason:
--
--   - No UNIQUE constraint on builds.slug — 0015_index_hardening.sql's
--     own preflight-checked unique index is what fixes this gap; adding
--     it here would make 0015 redundant instead of restoring history.
--   - No CHECK constraint on builds.status or build_revisions.update_type
--     — confirmed by direct audit (0013's own header,
--     docs/milestones/MILESTONE_8_AUDIT.md) that neither ever had one.
--
-- Storage evidence: 0017_storage_rls_hardening.sql's own ROLLBACK file
-- (supabase/rollbacks/0017_storage_rls_hardening_rollback.sql) recreates
-- all four policies with an explicit comment that they were "captured
-- directly from a pg_policies dump before this migration was applied" —
-- the exact role/qual/with_check below is copied verbatim from that
-- file, not inferred. The project-images bucket itself is the same
-- category of gap (no migration anywhere does `insert into
-- storage.buckets`) — created public (`public = true`), matching
-- 0002's and 0017's own header comments, both of which describe
-- "flipping the project-images bucket to private" as a deliberate,
-- never-yet-taken manual action outside the migration framework, not
-- something any tracked migration does.
--
-- Touches: none (three new tables, one new bucket, four pre-existing
-- storage policies). Every later migration's ALTER TABLE / FK /
-- RLS-policy-rewrite statement against these objects is unchanged — this
-- file only supplies what they were always silently assuming already
-- existed.
--
-- Rollback: see 0000_baseline_pre_tracked_tables_rollback.sql in
-- supabase/rollbacks/. Rolling this back also invalidates every later
-- migration that touches these tables (which is most of them) — only
-- use it to unwind an entire from-empty-database apply, never on a
-- project with real data.

begin;

create extension if not exists pgcrypto;

-- 0. Storage: project-images bucket + four pre-existing policies ----------
-- No dependency on anything else in this file (all four policies below
-- are either fully unscoped or bucket_id-scoped only — none reference
-- public.project_drafts or any other table), so this can safely run
-- before the tables below. Public, matching the documented historical
-- starting state (see this file's header) — no tracked migration ever
-- flips it.
insert into storage.buckets (id, name, public)
values ('project-images', 'project-images', true)
on conflict (id) do nothing;

-- Verbatim from supabase/rollbacks/0017_storage_rls_hardening_rollback.sql
-- (itself a direct pg_policies capture, not a reconstruction). 0017 drops
-- all four of these and adds two owner-scoped avatar policies in their
-- place — this is deliberately the vulnerable pre-0017 state, not a
-- "fixed" version of it, so that applying 0017 afterward is a faithful
-- replay of the real fix rather than a no-op.
create policy "Anyone can view project images" on storage.objects
    for select
    to public
    using (bucket_id = 'project-images');

create policy "Authenticated users can upload project images" on storage.objects
    for insert
    to authenticated
    with check (bucket_id = 'project-images');

create policy "Enable insert for authenticated users only" on storage.objects
    for insert
    to anon
    with check (true);

create policy "Enable read access for all users" on storage.objects
    for select
    to public
    using (true);

-- 1. profiles --------------------------------------------------------------
-- Column set: js/repositories/profileRepository.js's PUBLIC_PROFILE_COLUMNS
-- and js/pages/settings/app.js's read/write fields, MINUS every column a
-- tracked migration adds (avatar_path — 0003_profile_avatar_path.sql;
-- followers_count, following_count — 0012_follows.sql). Nothing else
-- ALTERs this table anywhere in 0001-0023 (verified by grep across every
-- file), so display_name/bio/location/website/github/youtube/avatar_url
-- are the remaining pre-existing set by elimination.
create table public.profiles (
    id uuid primary key references auth.users(id) on delete cascade,
    username text not null unique,
    display_name text,
    bio text,
    location text,
    website text,
    github text,
    youtube text,
    avatar_url text,
    created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

-- Matches the real project's live, directly-verified behavior
-- (docs/AUTH_ARCHITECTURE.md §1: a live check found zero INSERT policies
-- on profiles, for any role) — public read, self-only update, no INSERT
-- policy for any client role at all. The only way a row is ever created
-- is the trigger below. No tracked migration touches profiles' RLS at
-- any point, so this is the complete, permanent policy set, not just a
-- baseline that a later file replaces.
create policy "Profiles are readable by everyone" on public.profiles
    for select using (true);

create policy "Users can update their own profile" on public.profiles
    for update
    to authenticated
    using (auth.uid() = id)
    with check (auth.uid() = id);

-- Classic Supabase pattern: AFTER INSERT on auth.users, SECURITY DEFINER
-- so it can write to profiles despite profiles having no INSERT policy
-- for any ordinary role. Reads the username from signup's
-- options.data.username (js/pages/signup/app.js), matching the documented
-- live behavior exactly (docs/AUTH_ARCHITECTURE.md §2 — proved live via a
-- signup where zero client-side code ran, and the profiles row still
-- appeared correctly).
create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    insert into public.profiles (id, username)
    values (new.id, new.raw_user_meta_data->>'username');

    return new;
end;
$$;

create trigger on_auth_user_created
    after insert on auth.users
    for each row
    execute function public.handle_new_user();

-- 2. builds ------------------------------------------------------------
-- Column set: every column any tracked migration ALTERs builds to add is
-- EXCLUDED here — the only one found across all of 0001-0023 is
-- visibility (0002_publish_draft_and_visibility.sql). The remaining
-- columns are confirmed pre-existing three different ways:
--   - likes_count: 0008_project_likes.sql's own header says outright,
--     "builds.likes_count already existed as a column, just never
--     maintained."
--   - views: 0010_build_view_tracking.sql's own header says outright,
--     "builds.views already existed as a column (unpopulated)."
--   - metadata: 0004_fix_publish_draft_builds_columns.sql's header
--     confirms it "exist[s]" via a live information_schema.columns
--     check, and no migration ever adds it.
--   - featured, featured_order: read by js/repositories/buildRepository.js
--     (`.eq("featured", true)`, `.order("featured_order")`); no migration
--     ever adds either. Weaker evidence than the three above (no migration
--     comment confirms it directly), but the same elimination logic
--     applies — nothing else could have created these columns.
-- version and progress are confirmed ABSENT from builds — see
-- 0004_fix_publish_draft_builds_columns.sql's header (live-schema-verified
-- negative: "builds has no version/progress at all (only build_revisions
-- does)").
create table public.builds (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    title text not null,
    slug text not null,
    description text not null default '',
    category text not null,
    status text not null default 'planning',
    image_url text,
    specifications jsonb not null default '{}'::jsonb,
    likes_count integer not null default 0,
    views integer not null default 0,
    featured boolean not null default false,
    featured_order integer,
    metadata jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

-- No RLS policy of any kind here, deliberately — 0002_publish_draft_and_visibility.sql
-- immediately enables RLS and adds the real SELECT policy itself (its own
-- migration body includes a drop-all-existing-policies step specifically
-- because it can't assume what, if anything, already exists on this
-- table). Enabling RLS here with zero policies means direct client access
-- is fully denied in the brief window between this migration and 0002,
-- which is the safe default, not a gap. No index here either, for the
-- same reason 0015_index_hardening.sql exists — none was ever evidenced
-- as pre-existing, and inventing one would misrepresent this file as a
-- more authoritative reconstruction than it actually is.
alter table public.builds enable row level security;

-- 3. build_revisions -----------------------------------------------------
-- Column set: every column 0005_revision_history_and_restore.sql's own
-- ALTER TABLE adds — snapshot_title, snapshot_description, category,
-- specifications, resources — is EXCLUDED here. The remaining columns
-- come from publish_draft()'s INSERT column list as it stood in 0002
-- (build_id, user_id, title, description, version, progress, image_url,
-- update_type, hours_worked, milestone, attachments) — confirmed by
-- reading 0002's own function body directly, not the later 0006 version
-- that also writes the 0005 columns. No updated_at — confirmed absent
-- everywhere, consistent with 0002's design note that revisions are
-- "effectively immutable."
create table public.build_revisions (
    id uuid primary key default gen_random_uuid(),
    build_id uuid not null references public.builds(id) on delete cascade,
    user_id uuid not null references auth.users(id) on delete cascade,
    title text not null,
    description text not null default '',
    version text,
    progress integer not null default 0,
    image_url text,
    update_type text not null,
    -- Always inserted as a literal null by every version of
    -- publish_draft() ever written — no code anywhere reads it or
    -- reveals its real type. numeric is this migration's own judgment
    -- call (a fractional "hours worked" value is the more natural
    -- reading of the column name), not evidence-backed like the rest of
    -- this table — flagged here so a future correction has somewhere to
    -- start from if the real type ever turns out to differ.
    hours_worked numeric,
    milestone boolean not null default false,
    attachments jsonb not null default '[]'::jsonb,
    created_at timestamptz not null default now()
);

-- Same reasoning as builds above — 0002 enables RLS and adds the real
-- SELECT policy itself; no index here either, for the same "not
-- evidenced, don't invent it" reasoning as builds.
alter table public.build_revisions enable row level security;

commit;
