-- Migration: 0008_project_likes
-- Milestone: 6D (Project Likes)
-- Status: PROPOSED — not yet applied. Depends on 0001-0007 being applied
-- first.
--
-- Purpose: authenticated users can like/unlike a public project.
--
--   - likes.build_id (not revision_id) — likes belong to the build as a
--     whole, same reasoning as comments.build_id in 0007_comments.sql.
--   - unique (build_id, user_id) is the hard duplicate-prevention
--     guarantee — independent of any application logic, a race or a
--     retried request can never produce two rows for the same
--     (build, user) pair.
--   - SELECT is a direct RLS policy scoped to the caller's own row only
--     (user_id = auth.uid()) — narrower than comments' build-visibility
--     read policy, since nothing in this milestone exposes who liked a
--     project to anyone but that person. The public like *count* is read
--     off builds.likes_count instead (see below), not this table.
--   - No insert/update/delete policies — writes only through
--     set_build_like() below, same "no direct writes" posture as
--     comments.
--   - set_build_like(p_build_id, p_liked) is an idempotent desired-state
--     RPC, not a toggle: p_liked = true ensures a like row exists,
--     p_liked = false ensures it does not. A retried request with the
--     same p_liked value is always a no-op on the second call — it can
--     never reverse what the first call already did. auth.uid() is read
--     directly inside the function, never accepted as a parameter.
--   - Visibility check: builds.visibility must be exactly 'public' —
--     deliberately NOT the "public or owner" rule used elsewhere (e.g.
--     comments, builds' own SELECT policy). An owner previewing their own
--     unpublished/private project must not be able to like it. This
--     check applies to p_liked = true AND p_liked = false alike: once a
--     project is private, no like state changes are permitted at all
--     (existing like rows are left exactly as they are — only new writes
--     are blocked).
--   - builds.likes_count (a pre-existing column, previously unpopulated —
--     see docs from Milestone 6C) is now a trigger-maintained cache, not
--     computed dynamically. Every project-page load already fetches the
--     full build row, so the count comes for free with zero extra query.
--     coalesce(likes_count, 0) guards a null starting value; greatest(0,
--     ...) on decrement keeps the floor at zero regardless of any drift.
--   - Self-likes are allowed — a builder can like their own public
--     project. No restriction is applied.
--
-- Touches: none (new table only; builds.likes_count already existed as a
-- column, just never maintained). Adds likes, bump_likes_count(),
-- set_build_like().
--
-- Rollback: see 0008_project_likes_rollback.sql in this folder.

begin;

create table public.likes (
    id uuid primary key default gen_random_uuid(),
    build_id uuid not null references public.builds(id) on delete cascade,
    user_id uuid not null references auth.users(id) on delete cascade,
    created_at timestamptz not null default now(),
    unique (build_id, user_id)
);

alter table public.likes enable row level security;

create policy "Users can see their own likes" on public.likes
    for select using (user_id = auth.uid());

-- No insert/update/delete policies — with RLS enabled and no matching
-- policy, direct client writes are denied outright. Only
-- set_build_like() below can write to this table.

create or replace function public.bump_likes_count()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    if tg_op = 'INSERT' then
        update public.builds
            set likes_count = coalesce(likes_count, 0) + 1
            where id = new.build_id;

        return new;
    else
        update public.builds
            set likes_count = greatest(0, coalesce(likes_count, 0) - 1)
            where id = old.build_id;

        return old;
    end if;
end;
$$;

-- A trigger function, never called directly via RPC — revoked from
-- PUBLIC defensively (any function in the public schema is otherwise
-- callable through PostgREST by a role with execute privilege on it).
revoke all on function public.bump_likes_count() from public;

create trigger likes_bump_count
after insert or delete on public.likes
for each row execute function public.bump_likes_count();

create or replace function public.set_build_like(
    p_build_id uuid,
    p_liked boolean
)
returns table(liked boolean, likes_count integer)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_build public.builds;
begin
    if auth.uid() is null then
        raise exception 'You must be signed in to like a project.';
    end if;

    select * into v_build from public.builds where id = p_build_id;

    if v_build is null then
        raise exception 'Project not found.';
    end if;

    -- Deliberately strict: 'public' only, not "public or owner". An
    -- owner previewing their own unpublished project must not be able to
    -- change its like state either way.
    if v_build.visibility <> 'public' then
        raise exception 'This project is not available for likes.';
    end if;

    if p_liked then
        insert into public.likes (build_id, user_id)
        values (p_build_id, auth.uid())
        on conflict (build_id, user_id) do nothing;
    else
        delete from public.likes
            where build_id = p_build_id and user_id = auth.uid();
    end if;

    return query
        select
            exists(
                select 1 from public.likes l
                where l.build_id = p_build_id and l.user_id = auth.uid()
            ),
            coalesce(
                (select b.likes_count from public.builds b where b.id = p_build_id),
                0
            );
end;
$$;

revoke all on function public.set_build_like(uuid, boolean) from public;
grant execute on function public.set_build_like(uuid, boolean) to authenticated;

commit;
