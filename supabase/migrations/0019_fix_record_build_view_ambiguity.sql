-- Migration: 0019_fix_record_build_view_ambiguity
-- Milestone: 11B (Confirmed Database Bug)
-- Status: PROPOSED — not yet applied. Depends on 0001-0018 being applied
-- first.
--
-- Purpose: fixes two confirmed issues in record_build_view() (introduced
-- in 0010_build_view_tracking.sql), both found and reproduced live
-- against the real backend during the 2026-07-28 implementation review.
--
-- Issue 1 — every call failed (the reason for this migration existing):
-- `returns table(views integer)` implicitly declares a PL/pgSQL variable
-- named `views` in the function's own scope. Inside
-- `update public.builds set views = coalesce(views, 0) + 1`, the
-- assignment target (`set views = ...`) is never ambiguous — Postgres
-- always resolves an UPDATE's SET-target against the table. But the read
-- on the right, `coalesce(views, 0)`, is ambiguous between that OUT
-- parameter and the builds.views column, and Postgres raises 42702
-- ("column reference \"views\" is ambiguous") rather than guessing. This
-- has almost certainly meant view counts never incremented since this
-- feature shipped — the failure was caught client-side in loadBuild.js
-- and only console.error'd, never surfaced to a visitor or noticed.
-- Fix: qualify the read with the table's own alias (`b.views`), the same
-- style the function's final SELECT already used two lines below it.
--
-- Issue 2 — found during the same investigation, approved for inclusion
-- in this migration: the function's final `return query` ran
-- unconditionally regardless of the visibility check above it, meaning
-- a caller with no RLS-authorized visibility into a private build could
-- still learn that build's current view count by calling this RPC
-- directly with its id — no RLS policy on `builds` would let them SELECT
-- that row directly, but this RPC leaked the one column anyway. Fix:
-- explicit three-way branch by visibility and ownership (see below).
--
-- Required behavior after this migration:
--   - Public build: eligible visits may increment; caller always
--     receives the current count.
--   - Private build, requested by its owner: never increments (viewing
--     your own unpublished work isn't a "view"), but the owner receives
--     the current count.
--   - Private build, requested by anyone else (anonymous or a different
--     authenticated user): never increments, and the count is not
--     revealed — returns NULL, not 0. 0 would be indistinguishable from
--     "this build genuinely has zero views," silently telling an
--     unauthorized caller something true about a build they have no
--     access to; NULL means "no information," not "zero."
--   - Nonexistent build: unchanged — still raises 'Project not found.'
--
-- Ownership is determined via auth.uid() — the same server-verified,
-- unspoofable JWT claim already used for this purpose in 0007
-- (comments), 0008 (likes), 0009 (saved builds), and 0011
-- (notifications)'s own `visibility <> 'public' and user_id <>
-- auth.uid()` unauthorized-access checks. This migration consolidates
-- that same check into one named v_is_owner boolean, used in two places
-- below, rather than restating the (De Morgan's-inverted) condition
-- twice.
--
-- Scope: RPC name (record_build_view), parameters, return shape
-- (table(views integer)), and grants (anon + authenticated) are all
-- unchanged from 0010. No table, column, index, policy, or grant is
-- added, dropped, or altered — RLS is untouched. CREATE OR REPLACE
-- FUNCTION preserves the existing function's ownership and ACL
-- automatically, so the grants are not re-stated here.
--
-- Touches: public.record_build_view() only.
--
-- Rollback: see 0019_fix_record_build_view_ambiguity_rollback.sql in
-- supabase/rollbacks/ — restores 0010's original (buggy, and view-count-leaking)
-- function body verbatim. That is deliberate rollback semantics: undo
-- only what this migration changed, not a "neutral" state.

begin;

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
    v_is_owner boolean;
begin
    select * into v_build from public.builds where id = p_build_id;

    if v_build is null then
        raise exception 'Project not found.';
    end if;

    v_is_owner := auth.uid() is not null and v_build.user_id = auth.uid();

    if v_build.visibility = 'public' then
        v_viewer_key := case
            when auth.uid() is not null then 'user:' || auth.uid()::text
            when p_anon_id is not null then 'anon:' || p_anon_id::text
            else null
        end;

        -- Skip entirely for the owner's own views, and for a caller we
        -- have no identity for at all (no session, no anon id supplied).
        if v_viewer_key is not null and not v_is_owner then
            select last_viewed_at into v_last
                from public.build_view_cooldowns
                where build_id = p_build_id and viewer_key = v_viewer_key
                for update;

            if v_last is null or v_last < now() - interval '30 minutes' then
                insert into public.build_view_cooldowns (build_id, viewer_key, last_viewed_at)
                values (p_build_id, v_viewer_key, now())
                on conflict (build_id, viewer_key)
                    do update set last_viewed_at = excluded.last_viewed_at;

                -- Fixed: qualified as b.views (was the bare `views`,
                -- ambiguous against the returns table(views integer) OUT
                -- parameter — see Issue 1 above).
                update public.builds b
                    set views = coalesce(b.views, 0) + 1
                    where b.id = p_build_id;
            end if;
        end if;

        return query
            select coalesce(
                (select b.views from public.builds b where b.id = p_build_id),
                0
            );
    elsif v_is_owner then
        -- Private build, owner asking: never increments, but the owner
        -- may see their own count.
        return query
            select coalesce(
                (select b.views from public.builds b where b.id = p_build_id),
                0
            );
    else
        -- Private build, not the owner: never increments, and the count
        -- is not revealed — see Issue 2 above.
        return query select null::integer;
    end if;
end;
$$;

commit;
