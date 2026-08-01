-- Migration: 0000_baseline_pre_tracked_tables
-- Milestone: none — retroactive baseline, added 2026-08-01 after a fresh-
-- project dry run of 0001-0023 failed at 0002 with "relation public.builds
-- does not exist."
--
-- Purpose: public.profiles, public.builds, and public.build_revisions all
-- predate this repo's migration-tracking convention — they were already
-- live in the real Supabase project before supabase/migrations/ started,
-- and no tracked migration anywhere creates any of the three. Every
-- migration from 0001 onward only ever ALTERs them or adds foreign keys
-- to them, silently assuming they already exist. This was a known,
-- explicitly documented gap for profiles specifically (see
-- docs/AUTH_ARCHITECTURE.md §1-2, docs/DATABASE.md's former "Known Gap"
-- section) — but builds/build_revisions had the identical problem without
-- ever being called out as such, and it only surfaced when an actual
-- from-empty-database dry run was attempted for the first time.
--
-- Numbered 0000, not renumbered into the existing sequence — this
-- project's migration convention (docs/DATABASE.md) is that files are
-- "never reused, never renumbered." 0000 sorts before 0001 by both
-- lexical and numeric ordering, which is all that's required for a
-- migration meant to represent "state that existed before 0001."
--
-- Reconstruction method: every column below is sourced from direct
-- evidence in this repo — ALTER TABLE statements against these tables in
-- later migrations, column lists in INSERT/UPDATE/SELECT statements
-- inside migration functions (mainly publish_draft(), which evolved
-- across 0002/0004/0005/0006), and application code's own column
-- references (js/repositories/buildRepository.js and every page that
-- reads a build/revision). Nothing here is invented — where evidence was
-- ambiguous or absent (exact nullability on a handful of columns,
-- hours_worked's type), the choice made is the conservative one (nullable
-- rather than a guessed NOT NULL that could reject a legitimate future
-- write) and is called out inline. Two things are deliberately NOT
-- included despite being real production columns, to keep this baseline
-- honest about what it can actually verify:
--
--   - No UNIQUE constraint on builds.slug. The real gap this created
--     (uniqueness enforced only by publish_draft()'s check-then-insert
--     loop, racy under concurrency) is exactly what
--     0015_index_hardening.sql's own preflight-checked unique index
--     fixes, later in the real sequence. Adding it here too would just
--     make 0015 redundant instead of restoring the actual history.
--   - No CHECK constraint on builds.status or build_revisions.update_type.
--     Confirmed by direct audit (0013_activity_feed.sql's own header,
--     docs/milestones/MILESTONE_8_AUDIT.md) that no such constraint has
--     ever existed — status has only ever been written as 'planning',
--     update_type only as 'documentation' (after 0004's fix), but the
--     UI (BlueprintCard.js, renderTimeline.js) already anticipates a
--     wider set of values for future use. Baking in a restrictive CHECK
--     here would be a new constraint this schema never actually had, not
--     a faithful reconstruction of it.
--
-- Supersedes supabase/dev-bootstrap/bootstrap_profiles_for_fresh_project.sql
-- (a same-purpose, untracked, testing-only script written before this
-- baseline existed) — that file should be deleted once this migration is
-- reviewed; keeping both would let someone apply both and hit a duplicate
-- "relation already exists" error on profiles.
--
-- Touches: none (three new tables only: profiles, builds, build_revisions).
-- Every later migration's ALTER TABLE / FK / RLS-policy-rewrite statement
-- against these three tables is unchanged — this file only supplies what
-- they were always silently assuming already existed.
--
-- Rollback: see 0000_baseline_pre_tracked_tables_rollback.sql in
-- supabase/rollbacks/. Rolling this back also invalidates every later
-- migration that touches these tables (which is most of them) — only
-- use it to unwind an entire from-empty-database apply, never on a
-- project with real data.

begin;

create extension if not exists pgcrypto;

-- 1. profiles --------------------------------------------------------------
-- Column set reconstructed from js/repositories/profileRepository.js's
-- PUBLIC_PROFILE_COLUMNS, js/pages/settings/app.js's read/write fields,
-- and the two known migrations that ALTER this table without ever
-- creating it (0003_profile_avatar_path.sql, 0012_follows.sql).
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
    avatar_path text,
    followers_count integer not null default 0,
    following_count integer not null default 0,
    created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

-- Matches the real project's live, directly-verified behavior
-- (docs/AUTH_ARCHITECTURE.md §1: a live check found zero INSERT policies
-- on profiles, for any role) — public read, self-only update, no INSERT
-- policy for any client role at all. The only way a row is ever created
-- is the trigger below.
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
-- Column set reconstructed from every ALTER TABLE public.builds
-- statement in later migrations (visibility, 0002), every column in
-- publish_draft()'s INSERT/UPDATE lists (0002 through 0006), and
-- js/repositories/buildRepository.js's filter/select usage. version and
-- progress are deliberately absent — 0004_fix_publish_draft_builds_columns.sql
-- explicitly confirmed via live information_schema.columns that builds
-- has neither (only build_revisions does); anything in JS reading
-- build.progress is reading undefined off a real row, a separate,
-- pre-existing dead-code question this migration doesn't attempt to fix.
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
    visibility text not null default 'public'
        check (visibility in ('public', 'private')),
    likes_count integer not null default 0,
    views integer not null default 0,
    featured boolean not null default false,
    featured_order integer,
    -- Asserted to exist in the real (untracked) database by
    -- 0004_fix_publish_draft_builds_columns.sql's own header comment
    -- ("builds.specifications and builds.metadata exist"), but no tracked
    -- migration or application code anywhere reads or writes it. Included
    -- for fidelity with the real schema, not because anything here
    -- depends on it.
    metadata jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create index builds_user_id_idx on public.builds (user_id);

-- No RLS policy of any kind here, deliberately — 0002_publish_draft_and_visibility.sql
-- immediately enables RLS and adds the real SELECT policy itself (its own
-- migration body includes a drop-all-existing-policies step specifically
-- because it can't assume what, if anything, already exists on this
-- table). Enabling RLS here with zero policies means direct client access
-- is fully denied in the brief window between this migration and 0002,
-- which is the safe default, not a gap.
alter table public.builds enable row level security;

-- 3. build_revisions -----------------------------------------------------
-- Column set reconstructed from publish_draft()'s INSERT column list
-- (build_id, user_id, title, description, version, progress, image_url,
-- update_type, hours_worked, milestone, attachments — stable from
-- 0006_unpublish.sql onward) plus 0005_revision_history_and_restore.sql's
-- own ALTER TABLE (snapshot_title, snapshot_description, category,
-- specifications, resources). No updated_at — confirmed absent
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
    -- publish_draft() ever written (0002 through 0023) — no code anywhere
    -- reads it or reveals its real type. numeric is this migration's own
    -- judgment call (a fractional "hours worked" value is the more
    -- natural reading of the column name), not evidence-backed like the
    -- rest of this table — flagged here so a future correction has
    -- somewhere to start from if the real type ever turns out to differ.
    hours_worked numeric,
    milestone boolean not null default false,
    attachments jsonb not null default '[]'::jsonb,
    snapshot_title text not null default '',
    snapshot_description text not null default '',
    category text,
    specifications jsonb not null default '{}'::jsonb,
    resources jsonb not null default '[]'::jsonb,
    created_at timestamptz not null default now()
);

create index build_revisions_build_id_idx on public.build_revisions (build_id);

-- Same reasoning as builds above — 0002 enables RLS and adds the real
-- SELECT policy itself.
alter table public.build_revisions enable row level security;

commit;
