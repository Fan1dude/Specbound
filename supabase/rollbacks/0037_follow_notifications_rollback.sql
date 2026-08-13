-- Rollback for: 0037_follow_notifications
--
-- *** IMPORTANT: this is a BEHAVIORAL rollback, not a full schema
-- *** reversal, by deliberate design — not an oversight. It restores
-- *** set_follow() to its pre-0037 body, so no NEW follow will ever
-- *** create a notification again, but it does NOT narrow
-- *** notifications_type_check back to exclude 'follow', and it does
-- *** NOT delete, rewrite, or invalidate any existing 'follow'-typed
-- *** notification row.
--
-- Why data preservation wins over a "clean" full reversal: once this
-- migration has run in production and any real follow has happened,
-- notifications rows with type = 'follow' exist and belong to real
-- users. Narrowing the CHECK constraint back to its pre-0037 set would
-- either:
--   (a) fail outright with a constraint-violation error, if any
--       'follow' row still exists at rollback time, or
--   (b) require first deleting those rows to succeed — which means
--       deleting real users' legitimate, already-delivered
--       notifications merely to make a constraint narrower again.
-- Neither is acceptable. A rollback's job is to undo the BEHAVIOR this
-- migration introduced (new follows silently creating notifications),
-- not to erase evidence that the behavior worked correctly while it was
-- active. This file does the former only.
--
-- Confirmed safe to leave the CHECK widened and existing 'follow' rows
-- in place: the pre-0037 frontend's formatNotificationText() has a
-- generic `default:` case ("{actor} interacted with {build}") that
-- already runs today, in production, for the 'role_awarded' type —
-- that type has existed since 0031_guidelines_and_notification_types.sql
-- but was never given its own case in notificationFormat.js, so a
-- role_awarded notification already falls through this exact same
-- default path live today with no reported issue. A 'follow' row
-- (build always null) hits the identical safe fallback: readable
-- placeholder text, a link to a build page with an empty slug (renders
-- that page's own existing "not found" state, not a crash), no thrown
-- error, no data exposed beyond what the row's own RLS already permits
-- its recipient to see. This is direct evidence from the current
-- codebase, not an assumption — see 0037_follow_notifications.sql's own
-- header for the same reasoning.
--
-- Restores set_follow(uuid, boolean) to its exact pre-0037 body,
-- verbatim from 0012_follows.sql (migration-evidenced, not
-- reconstructed) — same signature, RETURNS TABLE shape, SECURITY
-- DEFINER mode, search_path, self-follow rejection, and grants.

begin;

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
