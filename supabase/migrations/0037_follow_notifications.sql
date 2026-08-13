-- Migration: 0037_follow_notifications
-- Milestone: 25 (Follow Notifications)
-- Depends on 0000-0036 being applied first.
--
-- Purpose: closes a gap deliberately deferred since 0012_follows.sql
-- shipped (Milestone 7C) — that migration's own header comment says so
-- explicitly: "No create_notification() call — 'Follow notifications' is
-- explicitly out of scope for this milestone." A builder who gets
-- followed currently has no signal that it happened at all.
--
-- Full design: docs/milestones/MILESTONE_25_FOLLOW_NOTIFICATIONS_SPECIFICATION.md
--
-- Two changes, both to already-existing objects — no new table:
--
--   1. notifications_type_check widened to add 'follow', same shape as
--      0031_guidelines_and_notification_types.sql's own widening
--      (drop-and-recreate the same auto-named constraint). Verified live
--      against production before writing this file (not assumed from
--      the migration source alone): the constraint's real name is
--      confirmed `notifications_type_check`, current values confirmed
--      `('comment','like','save','reply','role_awarded','report_resolved')`
--      — matches 0031's source exactly, no drift.
--
--   2. set_follow(p_following_id, p_followed) — CREATE OR REPLACE, exact
--      same signature, RETURNS TABLE shape, SECURITY DEFINER mode,
--      search_path, self-follow rejection (both the app-level check and
--      the table's own CHECK constraint are untouched), and grants.
--      The only addition is on the p_followed = true branch: the INSERT
--      now captures whether a row was genuinely newly created via
--      `on conflict (follower_id, following_id) do nothing returning id
--      into v_inserted_id`, and calls create_notification() only when
--      v_inserted_id is not null — the exact same pattern already
--      proven correct in production by set_build_like()/
--      set_build_saved() (0011_notifications.sql) for the identical
--      "notify only on a genuinely new row, never on a no-op repeat"
--      requirement. The p_followed = false (unfollow) branch is
--      untouched — no notification call added there, per product
--      decision. This is also what makes duplicate/concurrent follow
--      requests safe for free: the unique(follower_id, following_id)
--      constraint (0012_follows.sql, unchanged) guarantees at most one
--      row can ever exist for a given pair, so at most one caller can
--      ever observe a non-null v_inserted_id, regardless of how many
--      requests race. A genuine unfollow-then-refollow is a genuinely
--      new INSERT (nothing left to conflict against after the DELETE),
--      so it correctly produces a new notification with zero extra
--      logic.
--
--      Notification metadata: type = 'follow', recipient =
--      p_following_id (the builder being followed), actor =
--      v_follower_id (auth.uid(), the follower — already read at the
--      top of the function), build_id = null, comment_id = null (a
--      follow has no associated build — create_notification()'s
--      p_build_id already defaults to null since 0031, so no change to
--      that function is needed or made).
--
-- create_notification() itself is NOT modified — its existing signature
-- (p_recipient_id, p_actor_id, p_type, p_build_id default null,
-- p_comment_id default null) already supports this call verbatim, proven
-- live today by report_resolved's identical buildless usage.
--
-- Rollback: see 0037_follow_notifications_rollback.sql in
-- supabase/rollbacks/ — DELIBERATELY NOT a full schema reversal. It
-- restores set_follow() to its pre-0037 body (so no NEW follow ever
-- creates a notification again) but does NOT narrow
-- notifications_type_check back to exclude 'follow', and does not
-- delete or alter any existing follow-typed notification row. Narrowing
-- the CHECK back would either fail outright (if any 'follow' row already
-- exists by then) or require deleting real users' legitimate
-- notifications to succeed — both unacceptable once this has run in
-- production. This is a considered, intentional asymmetry (behavioral
-- rollback, not a full reversal), not an oversight — see that file's own
-- header for the full reasoning.
--
-- Old-frontend compatibility with an existing 'follow' row (verified by
-- direct code reading, not assumed): the pre-0037 formatNotificationText()
-- has a generic `default:` case ("{actor} interacted with {build}") that
-- already runs today, in production, for the 'role_awarded' type — that
-- type has existed since 0031 but was NEVER given its own case in
-- notificationFormat.js, so any role_awarded notification already falls
-- through this exact same default path live today with no reported
-- issue. A 'follow' row (build always null) hits the same safe fallback:
-- readable placeholder text, a link to a build page with an empty slug
-- (renders that page's own existing "not found" state, not a crash), no
-- thrown error, no exposed data beyond what the row's own RLS already
-- permits its recipient to see. Confirmed safe to leave the CHECK
-- widened during a behavioral-only rollback.

begin;

alter table public.notifications
    drop constraint notifications_type_check;

alter table public.notifications
    add constraint notifications_type_check
    check (type in ('comment', 'like', 'save', 'reply', 'role_awarded', 'report_resolved', 'follow'));

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
    v_inserted_id uuid;
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
        on conflict (follower_id, following_id) do nothing
        returning id into v_inserted_id;

        -- Only a genuinely new follow (not a no-op repeat of an already-
        -- active follow) generates a notification — same "returning
        -- into, check not null" pattern already proven by
        -- set_build_like()/set_build_saved() above in this schema.
        if v_inserted_id is not null then
            perform public.create_notification(p_following_id, v_follower_id, 'follow');
        end if;
    else
        -- Unchanged: unfollowing never notifies, by product decision.
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
