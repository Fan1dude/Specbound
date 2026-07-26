-- Migration: 0009_saved_builds
-- Milestone: 6E (Saved Projects)
-- Status: PROPOSED — not yet applied. Depends on 0001-0008 being applied
-- first.
--
-- Purpose: authenticated users can privately save/unsave a public project
-- to revisit later.
--
--   - saved_builds.build_id (not revision_id) — saves belong to the build
--     as a whole, same reasoning as likes.build_id in
--     0008_project_likes.sql.
--   - unique (build_id, user_id) is the hard duplicate-prevention
--     guarantee, same as likes.
--   - SELECT is a direct RLS policy scoped to the caller's own row only
--     (user_id = auth.uid()) — this IS "private to the owner": nobody,
--     including a build's own creator, can see who saved their project.
--     No insert/update/delete policies — writes only through
--     set_build_saved() below.
--   - set_build_saved(p_build_id, p_saved) is an idempotent desired-state
--     RPC, same shape as set_build_like() in 0008: p_saved = true ensures
--     a save row exists, p_saved = false ensures it doesn't. A retried
--     call with the same p_saved is always a safe no-op.
--   - Visibility rule is DELIBERATELY ASYMMETRIC, per explicit direction
--     (unlike set_build_like(), which blocks changes in both directions
--     while private):
--       - p_saved = true requires builds.visibility = 'public' — you
--         can't save a project you shouldn't be able to see as a
--         stranger.
--       - p_saved = false has NO visibility check — a save is a private
--         bookmark the user manages for themselves, not an engagement
--         signal on someone else's content. If a saved project later
--         goes private, the user can still remove it from their own
--         list; otherwise "Saved Projects" could accumulate entries a
--         user is permanently stuck with until the original owner
--         republishes.
--   - No trigger/cached counter — there is no public "N saves" count
--     anywhere in this milestone's scope, unlike builds.likes_count.
--
-- Touches: none (new table only). Adds saved_builds, set_build_saved().
--
-- Rollback: see 0009_saved_builds_rollback.sql in this folder.

begin;

create table public.saved_builds (
    id uuid primary key default gen_random_uuid(),
    build_id uuid not null references public.builds(id) on delete cascade,
    user_id uuid not null references auth.users(id) on delete cascade,
    created_at timestamptz not null default now(),
    unique (build_id, user_id)
);

create index saved_builds_user_id_created_at_idx
    on public.saved_builds (user_id, created_at desc);

alter table public.saved_builds enable row level security;

create policy "Users can see their own saved builds" on public.saved_builds
    for select using (user_id = auth.uid());

-- No insert/update/delete policies — with RLS enabled and no matching
-- policy, direct client writes are denied outright. Only
-- set_build_saved() below can write to this table.

create or replace function public.set_build_saved(
    p_build_id uuid,
    p_saved boolean
)
returns table(saved boolean)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_build public.builds;
begin
    if auth.uid() is null then
        raise exception 'You must be signed in to save a project.';
    end if;

    select * into v_build from public.builds where id = p_build_id;

    if v_build is null then
        raise exception 'Project not found.';
    end if;

    if p_saved then
        -- Strict 'public' only, not "public or owner" — same reasoning
        -- as set_build_like(): a stranger can't save what they can't
        -- see, and an owner previewing their own unpublished project has
        -- no reason to "save" it either.
        if v_build.visibility <> 'public' then
            raise exception 'This project is not available to save.';
        end if;

        insert into public.saved_builds (build_id, user_id)
        values (p_build_id, auth.uid())
        on conflict (build_id, user_id) do nothing;
    else
        -- Deliberately no visibility check here — see header comment.
        -- Removing your own private bookmark is always allowed,
        -- regardless of the build's current visibility.
        delete from public.saved_builds
            where build_id = p_build_id and user_id = auth.uid();
    end if;

    return query
        select exists(
            select 1 from public.saved_builds s
            where s.build_id = p_build_id and s.user_id = auth.uid()
        );
end;
$$;

revoke all on function public.set_build_saved(uuid, boolean) from public;
grant execute on function public.set_build_saved(uuid, boolean) to authenticated;

commit;
