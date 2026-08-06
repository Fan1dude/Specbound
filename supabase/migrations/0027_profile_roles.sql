-- Migration: 0027_profile_roles
-- Milestone: 22 (Community Foundation)
-- Status: PROPOSED — not yet applied. Depends on 0000-0026 being applied
-- first.
--
-- Full design: docs/milestones/MILESTONE_22_COMMUNITY_FOUNDATION_SPECIFICATION.md
-- §5, §8.1, §0.2 decision 1.
--
-- Purpose: one table for every manually-awarded or permission-bearing
-- community role (Community Builder, Project Mentor, Moderator, Staff).
-- Automatic roles (New/Active/Long-Term Builder) are deliberately absent
-- from this schema entirely — they're computed live from existing
-- profile/build data (js/services/communityRecognition.js), the same
-- "pure function, no storage" pattern already established for the
-- editor readiness checklist (Milestone 20) and the profile completion
-- checklist (Milestone 21). No role in this app has a score, a level, or
-- an expiry.
--
--   Merged what could have been two tables (a recognition table for
--   Community Builder/Project Mentor, a separate permissions table for
--   Moderator/Staff) into this one — the permission-vs-recognition
--   distinction is meaningful in what a role *does* (expressed below in
--   is_platform_moderator()/is_platform_staff()), not in how it's
--   stored. unique (user_id, role) rather than a single-row-per-user
--   table: a builder can hold more than one role at once (e.g. a
--   Moderator who's also a recognized Project Mentor).
--
--   is_platform_moderator()/is_platform_staff() are deliberately
--   separate from is_catalog_moderator() (0020_components_catalog.sql)
--   — not merged, not generalized into one is_admin(). Same reasoning
--   0020's own header already gives for why catalog moderation is its
--   own narrow thing: a catalog moderator curates parts-catalog data
--   quality; a platform moderator handles community reports and role
--   grants. Someone could reasonably hold one without the other.
--
--   No write policy of any kind on this table for any client role —
--   not even the two role-check functions below can write to it (both
--   are read-only, `stable`). The only way a row is ever created is
--   grant_profile_role() in 0028_moderation.sql. It isn't defined here:
--   it needs to log into moderation_actions, which doesn't exist until
--   0028 — the same "can't forward-reference a not-yet-defined object"
--   constraint 0020's own header already ran into with
--   catalog_moderators/is_catalog_moderator(). Read-side (this file) and
--   write-side (0028) are split for that reason, not by accident.
--
-- Touches: none (one new table, two new functions).
--
-- Rollback: see 0027_profile_roles_rollback.sql in supabase/rollbacks/.

begin;

create table public.profile_roles (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    role text not null check (role in ('community_builder', 'project_mentor', 'moderator', 'staff')),
    granted_by uuid references auth.users(id) on delete set null,
    granted_at timestamptz not null default now(),
    note text,

    unique (user_id, role)
);

create index profile_roles_user_idx on public.profile_roles (user_id);

alter table public.profile_roles enable row level security;

-- Public — same "functional, not private" posture as follows
-- (0012_follows.sql): a role badge needs to render on any visitor's view
-- of a public profile, not just the owner's own view.
create policy "Roles are readable by everyone" on public.profile_roles
    for select using (true);

-- No insert/update/delete policy for any role — every write goes
-- through grant_profile_role()/revoke_profile_role() (0028), both
-- SECURITY DEFINER and both moderator/staff-gated internally.

create or replace function public.is_platform_moderator(p_user_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public, pg_temp
as $$
    select exists (
        select 1 from public.profile_roles
        where user_id = p_user_id and role in ('moderator', 'staff')
    );
$$;

revoke all on function public.is_platform_moderator(uuid) from public;
grant execute on function public.is_platform_moderator(uuid) to authenticated;

create or replace function public.is_platform_staff(p_user_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public, pg_temp
as $$
    select exists (
        select 1 from public.profile_roles
        where user_id = p_user_id and role = 'staff'
    );
$$;

revoke all on function public.is_platform_staff(uuid) from public;
grant execute on function public.is_platform_staff(uuid) to authenticated;

commit;
