-- Migration: 0012_follows
-- Milestone: 7C (Following Builders)
-- Status: PROPOSED — not yet applied. Depends on 0001-0011 being applied
-- first.
--
-- Purpose: users can follow/unfollow other builders, with cached
-- follower/following counts on profiles.
--
--   - follows.follower_id/following_id both reference auth.users, not
--     profiles — same reasoning as every other user_id column in this
--     schema (no FK to profiles exists anywhere, so PostgREST can never
--     embed a profiles join through this table either; the client
--     batch-fetches profiles separately, same as comments/likes/saves).
--   - unique (follower_id, following_id) is the hard duplicate-follow
--     guarantee. check (follower_id <> following_id) is the hard
--     self-follow guarantee — both enforced at the database level,
--     independent of any application or function logic.
--   - SELECT is PUBLIC (using (true)) — a deliberate, explicit departure
--     from every other table added since 0008 (likes, saved_builds,
--     notifications), all of which were private-to-self. Private
--     accounts are explicitly out of scope for this milestone, and the
--     dedicated Followers/Following pages need to be visible to any
--     visitor, not just the two people in the relationship — the same
--     way GitHub/Twitter followers lists work.
--   - No insert/update/delete policies — writes only through
--     set_follow() below, same "no direct writes" posture as everything
--     else in this schema.
--   - profiles.followers_count/following_count are trigger-maintained
--     caches, same reasoning as builds.likes_count in
--     0008_project_likes.sql: the profile row is already fetched in full
--     on every profile-page load, so both counts come back for free.
--     Both new columns default to 0, which is already correct (no
--     follows have ever existed) — no backfill needed.
--   - set_follow(p_following_id, p_followed) is an idempotent
--     desired-state RPC, same shape as set_build_like()/
--     set_build_saved(): p_followed = true ensures a follow row exists,
--     p_followed = false ensures it doesn't. auth.uid() is read directly
--     as the follower, never accepted as a parameter. Explicitly rejects
--     following yourself (on top of the table's own CHECK constraint) for
--     a friendly error message. Returns the authoritative followed state
--     plus both the followed profile's followers_count and the caller's
--     own following_count, so the client can reconcile immediately
--     without a second fetch.
--   - No create_notification() call — "Follow notifications" is
--     explicitly out of scope for this milestone. notifications.type is
--     not widened for a 'follow' type.
--
-- Touches: public.profiles (2 new columns, additive only). Adds follows,
-- bump_follow_counts(), set_follow().
--
-- Rollback: see 0012_follows_rollback.sql in supabase/rollbacks/.

begin;

alter table public.profiles
    add column followers_count integer not null default 0,
    add column following_count integer not null default 0;

create table public.follows (
    id uuid primary key default gen_random_uuid(),
    follower_id uuid not null references auth.users(id) on delete cascade,
    following_id uuid not null references auth.users(id) on delete cascade,
    created_at timestamptz not null default now(),
    unique (follower_id, following_id),
    check (follower_id <> following_id)
);

create index follows_follower_id_idx on public.follows (follower_id);
create index follows_following_id_idx on public.follows (following_id);

alter table public.follows enable row level security;

create policy "Follow relationships are public" on public.follows
    for select using (true);

-- No insert/update/delete policies — with RLS enabled and no matching
-- policy, direct client writes are denied outright. Only set_follow()
-- below can write to this table.

create or replace function public.bump_follow_counts()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    if tg_op = 'INSERT' then
        update public.profiles
            set following_count = coalesce(following_count, 0) + 1
            where id = new.follower_id;

        update public.profiles
            set followers_count = coalesce(followers_count, 0) + 1
            where id = new.following_id;

        return new;
    else
        update public.profiles
            set following_count = greatest(0, coalesce(following_count, 0) - 1)
            where id = old.follower_id;

        update public.profiles
            set followers_count = greatest(0, coalesce(followers_count, 0) - 1)
            where id = old.following_id;

        return old;
    end if;
end;
$$;

-- A trigger function, never called directly via RPC — revoked from
-- PUBLIC defensively, same posture as bump_likes_count().
revoke all on function public.bump_follow_counts() from public;

create trigger follows_bump_counts
after insert or delete on public.follows
for each row execute function public.bump_follow_counts();

create or replace function public.set_follow(
    p_following_id uuid,
    p_followed boolean
)
returns table(followed boolean, followers_count integer, following_count integer)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_follower_id uuid := auth.uid();
begin
    if v_follower_id is null then
        raise exception 'You must be signed in to follow a builder.';
    end if;

    if v_follower_id = p_following_id then
        raise exception 'You cannot follow yourself.';
    end if;

    if not exists (select 1 from public.profiles where id = p_following_id) then
        raise exception 'Builder not found.';
    end if;

    if p_followed then
        insert into public.follows (follower_id, following_id)
        values (v_follower_id, p_following_id)
        on conflict (follower_id, following_id) do nothing;
    else
        delete from public.follows
            where follower_id = v_follower_id and following_id = p_following_id;
    end if;

    return query
        select
            exists(
                select 1 from public.follows f
                where f.follower_id = v_follower_id and f.following_id = p_following_id
            ),
            coalesce(
                (select p.followers_count from public.profiles p where p.id = p_following_id),
                0
            ),
            coalesce(
                (select p.following_count from public.profiles p where p.id = v_follower_id),
                0
            );
end;
$$;

revoke all on function public.set_follow(uuid, boolean) from public;
grant execute on function public.set_follow(uuid, boolean) to authenticated;

commit;
