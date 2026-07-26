-- Migration: 0013_activity_feed
-- Milestone: 7D (Activity Feed)
-- Status: PROPOSED — not yet applied. Depends on 0001-0012 being applied
-- first.
--
-- Purpose: Following/Explore activity feeds computed live from the
-- existing build_revisions log — no new table.
--
--   - No activity table exists because none is needed: build_revisions
--     is already an immutable, timestamped, RLS-correct event log of
--     every "project published"/"project updated" event (one row per
--     publish_draft() call, first publish or republish alike). This
--     function is a pure read-time join across build_revisions + builds
--     + follows.
--   - Only two activity types ship: 'new_project' and 'new_revision'.
--     A 'completed' type is deliberately NOT included — nothing in this
--     schema or application ever sets builds.status to anything but
--     'planning' (confirmed by audit), so there is no reliable
--     historical completion event to source it from. Status management
--     and a completion activity are a separate future feature, not
--     addressed here.
--   - activity_type is derived per row, not stored: a revision is
--     'new_project' if no OTHER revision for the same build sorts
--     earlier under a deterministic (created_at, id) ordering — NOT
--     min(created_at) alone, which could misclassify if two revisions
--     for the same build ever shared an identical created_at (same-
--     transaction timestamp equality is possible in Postgres).
--   - Pagination is a composite keyset cursor: p_before_created_at +
--     p_before_id, ordered by (created_at desc, id desc). Comparing only
--     created_at could skip or duplicate rows whenever two revisions
--     share the same timestamp — the id tiebreak makes the ordering (and
--     therefore the cursor) totally deterministic.
--   - p_scope is validated to exactly 'following' or 'explore' (raises
--     otherwise); p_limit is clamped to [1, 50], defaulting to 20 — a
--     caller can request an unreasonable limit but can never get more
--     than 50 rows back.
--   - SECURITY INVOKER, not DEFINER — the first RPC in this schema that
--     doesn't need elevated privilege. Every previous custom function
--     needed SECURITY DEFINER to enforce something beyond RLS (ownership,
--     business rules on a write). This one only reads build_revisions,
--     builds, and follows, all of which are already correctly readable
--     to the calling user under their own existing RLS policies (public
--     builds' revisions are public; follows is fully public) — there is
--     nothing to bypass, so running with the caller's own privilege is
--     the more correct, least-privilege choice, not just an equally
--     valid one.
--   - The 'following' scope naturally returns zero rows for a signed-out
--     caller (auth.uid() is null, so the follows.follower_id = auth.uid()
--     check never matches) — no exception raised, no special-casing
--     needed; the 'explore' scope works identically signed in or out.
--
-- Touches: none. Adds get_activity_feed() only — no new table, no new
-- columns, no new RLS policy.
--
-- Rollback: see 0013_activity_feed_rollback.sql in this folder.

begin;

create or replace function public.get_activity_feed(
    p_scope text,
    p_before_created_at timestamptz default null,
    p_before_id uuid default null,
    p_limit integer default 20
)
returns table (
    id uuid,
    build_id uuid,
    user_id uuid,
    activity_type text,
    version text,
    created_at timestamptz
)
language plpgsql
stable
security invoker
set search_path = public, pg_temp
as $$
declare
    v_limit integer;
begin
    if p_scope not in ('following', 'explore') then
        raise exception 'Invalid feed scope.';
    end if;

    v_limit := least(greatest(coalesce(p_limit, 20), 1), 50);

    return query
        select
            br.id,
            br.build_id,
            br.user_id,
            case
                when not exists (
                    select 1 from public.build_revisions br2
                    where br2.build_id = br.build_id
                      and (
                          br2.created_at < br.created_at
                          or (br2.created_at = br.created_at and br2.id < br.id)
                      )
                ) then 'new_project'
                else 'new_revision'
            end as activity_type,
            br.version,
            br.created_at
        from public.build_revisions br
        join public.builds b on b.id = br.build_id
        where b.visibility = 'public'
          and (
              p_before_created_at is null
              or br.created_at < p_before_created_at
              or (br.created_at = p_before_created_at and br.id < p_before_id)
          )
          and (
              p_scope = 'explore'
              or exists (
                  select 1 from public.follows f
                  where f.follower_id = auth.uid() and f.following_id = br.user_id
              )
          )
        order by br.created_at desc, br.id desc
        limit v_limit;
end;
$$;

revoke all on function public.get_activity_feed(text, timestamptz, uuid, integer) from public;
grant execute on function public.get_activity_feed(text, timestamptz, uuid, integer) to anon, authenticated;

commit;
