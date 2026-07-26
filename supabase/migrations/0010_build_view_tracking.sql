-- Migration: 0010_build_view_tracking
-- Milestone: 7A (Project View Tracking)
-- Status: PROPOSED — not yet applied. Depends on 0001-0009 being applied
-- first.
--
-- Purpose: reliable, cooldown-deduped view counting on builds.views (a
-- pre-existing column, previously unpopulated by anything — same starting
-- position as builds.likes_count before 0008).
--
--   - build_view_cooldowns is a bounded UPSERT table, not an append-only
--     events log: one row per (build_id, viewer_key) pair, holding only
--     the last time that viewer counted. Its size is bounded by (distinct
--     builds) x (distinct viewers who've ever viewed them), not by total
--     view volume — it never grows per-view the way a log table would.
--   - viewer_key is either 'user:<auth.uid()>' (signed-in — unspoofable,
--     server-verified via the JWT) or 'anon:<client-generated uuid>'
--     (signed-out — persisted client-side in localStorage, sent as an RPC
--     parameter). Never trusted as a real identity beyond that — used
--     only as an opaque cooldown key, never stored or exposed elsewhere.
--   - No RLS SELECT policy at all on this table (RLS is enabled, but zero
--     policies exist) — unlike every other new table added so far, there
--     is no legitimate reason for a client to ever read this table
--     directly; it exists purely as record_build_view()'s own internal
--     bookkeeping.
--   - record_build_view(p_build_id, p_anon_id) is the only way to write
--     to either build_view_cooldowns or builds.views going forward for
--     this purpose. Unlike the write RPCs in 0007-0009 (all
--     authenticated-only), this one is granted to `anon` as well as
--     `authenticated` — view tracking must work for signed-out visitors
--     too. Silently no-ops (returns the unchanged current count, no
--     exception) for every expected/routine skip case — private project,
--     the owner viewing their own project, or within the 30-minute
--     cooldown — since none of those are error conditions. Raises only
--     if the build doesn't exist at all.
--   - No trigger — unlike likes (which need both increment and
--     decrement), views are increment-only, so builds.views is updated
--     inline in the same transaction as the cooldown upsert.
--
-- Known limitation (accepted, not fixed by this migration): an anonymous
-- caller can bypass the cooldown by fabricating a fresh p_anon_id on every
-- call. This is a "reasonable cooldown" against ordinary refresh
-- inflation, not a bot/adversary-proof guarantee — see project chat
-- history for the full discussion.
--
-- Touches: none — builds.views already existed as a column (unpopulated);
-- this migration starts maintaining it but adds no new column to builds.
-- Adds build_view_cooldowns, record_build_view().
--
-- Rollback: see 0010_build_view_tracking_rollback.sql in this folder.

begin;

create table public.build_view_cooldowns (
    build_id uuid not null references public.builds(id) on delete cascade,
    viewer_key text not null,
    last_viewed_at timestamptz not null default now(),
    primary key (build_id, viewer_key)
);

alter table public.build_view_cooldowns enable row level security;

-- Deliberately zero policies — RLS enabled with no matching policy denies
-- every direct client read/write outright. Only record_build_view() (as
-- SECURITY DEFINER, which bypasses RLS) ever touches this table.

create or replace function public.record_build_view(
    p_build_id uuid,
    p_anon_id uuid default null
)
returns table(views integer)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_build public.builds;
    v_viewer_key text;
    v_last timestamptz;
begin
    select * into v_build from public.builds where id = p_build_id;

    if v_build is null then
        raise exception 'Project not found.';
    end if;

    if v_build.visibility = 'public' then
        v_viewer_key := case
            when auth.uid() is not null then 'user:' || auth.uid()::text
            when p_anon_id is not null then 'anon:' || p_anon_id::text
            else null
        end;

        -- Skip entirely for the owner's own views, and for a caller we
        -- have no identity for at all (no session, no anon id supplied).
        if v_viewer_key is not null
            and (auth.uid() is null or v_build.user_id <> auth.uid())
        then
            select last_viewed_at into v_last
                from public.build_view_cooldowns
                where build_id = p_build_id and viewer_key = v_viewer_key
                for update;

            if v_last is null or v_last < now() - interval '30 minutes' then
                insert into public.build_view_cooldowns (build_id, viewer_key, last_viewed_at)
                values (p_build_id, v_viewer_key, now())
                on conflict (build_id, viewer_key)
                    do update set last_viewed_at = excluded.last_viewed_at;

                update public.builds
                    set views = coalesce(views, 0) + 1
                    where id = p_build_id;
            end if;
        end if;
    end if;

    return query
        select coalesce(
            (select b.views from public.builds b where b.id = p_build_id),
            0
        );
end;
$$;

revoke all on function public.record_build_view(uuid, uuid) from public;
grant execute on function public.record_build_view(uuid, uuid) to anon, authenticated;

commit;
