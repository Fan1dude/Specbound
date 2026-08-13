-- Migration: 0036_resolve_report_atomic_status_guard
-- Milestone: 24 (Moderator Report Queue) — post-PR-review fix.
-- Depends on 0000-0035 being applied first.
--
-- Purpose: closes a confirmed double-resolution race in resolve_report()
-- (0028_moderation.sql). That function's UPDATE matched by report id
-- alone, with no status predicate, so it would silently re-resolve an
-- already-resolved report. Demonstrated directly against a local
-- disposable database during PR #19 review: two sequential
-- resolve_report() calls against the same report (simulating two
-- moderator sessions, the second acting on a status read taken before
-- the first call's UPDATE committed) both returned success, the second
-- silently overwrote the first's decision (status/reviewed_by), AND
-- produced two moderation_actions rows and two reporter notifications
-- for what should have been a single resolution event. See
-- docs/milestones/MILESTONE_24_MODERATOR_REPORT_QUEUE_SPECIFICATION.md
-- §4 for the full writeup.
--
-- Fix: CREATE OR REPLACE FUNCTION with the exact existing signature,
-- security mode, search_path, and grants — every behavior this function
-- had is preserved (status validation, moderator authorization check,
-- the moderation_actions insert, the reporter notification, the return
-- shape) except the UPDATE now atomically claims the row by adding
-- `and status = 'open'` to its WHERE clause and using `returning * into`
-- as the atomicity boundary itself, not a separate pre-check. Postgres's
-- normal row-level UPDATE locking under READ COMMITTED (the default,
-- unchanged here) is what makes this atomic: a second concurrent UPDATE
-- against the same row blocks until the first commits, then re-evaluates
-- `status = 'open'` against the now-updated row and correctly matches
-- zero rows — no new locking primitive, isolation level, or advisory
-- lock is needed. Same established pattern already used by
-- approve_component_submission()'s `for update` guard (Milestone 19).
--
-- When the UPDATE returns no row, the two previously-conflated failure
-- cases are now distinguished by message text, so the client can give
-- honest, specific feedback instead of a generic error:
--   - 'Report not found.' — unchanged wording, still raised only when no
--     row with that id exists at all.
--   - 'This report has already been resolved.' — new, raised when the
--     row exists but its status was no longer 'open' at claim time.
-- Both are ordinary RAISE EXCEPTION text, surfaced by supabase-js as
-- error.message verbatim — the same mechanism the existing client code
-- already relied on for the 'not found' case (see
-- js/pages/moderation/renderModerationPage.js's pre-existing
-- /not found/i match), so no new client-side error-parsing mechanism is
-- introduced, only a second distinct substring to match.
--
-- Rollback: see 0036_resolve_report_atomic_status_guard_rollback.sql in
-- supabase/rollbacks/ — restores the exact pre-0036 (unguarded) function
-- body. No table, column, or existing row data is touched by either this
-- migration or its rollback; only the function definition changes.
--
-- Local verification (against the local disposable Supabase/Docker
-- stack, not theoretical): after applying this migration, the identical
-- two-call sequence that produced conflicting/duplicate rows before this
-- fix now raises 'This report has already been resolved.' on the second
-- call, leaves the report at the first call's outcome, and leaves
-- exactly one moderation_actions row and one notification behind. See
-- supabase/tests/milestone_24_resolve_report_atomic_guard.test.sql for
-- the full automated coverage, including the not-found, unauthorized,
-- and both-outcome regression cases.

begin;

create or replace function public.resolve_report(
    p_report_id uuid,
    p_status text,
    p_note text default null
)
returns public.content_reports
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_report public.content_reports;
begin
    if not public.is_platform_moderator(auth.uid()) then
        raise exception 'Only moderators can resolve reports.';
    end if;

    if p_status not in ('reviewed', 'dismissed') then
        raise exception 'Invalid resolution status.';
    end if;

    -- The atomic claim: matching on `status = 'open'` in the same
    -- statement that performs the update, with `returning` as the only
    -- signal of success, is what makes this safe under concurrency — not
    -- a check beforehand. A second, overlapping call against the same
    -- row either blocks and then legitimately fails to match (status no
    -- longer 'open'), or — if it arrives after the first call already
    -- committed — simply fails to match outright. Either way it can
    -- never return a row here.
    update public.content_reports
        set status = p_status, reviewed_by = auth.uid(), reviewed_at = now()
        where id = p_report_id
          and status = 'open'
        returning * into v_report;

    if v_report is null then
        if exists (select 1 from public.content_reports where id = p_report_id) then
            raise exception 'This report has already been resolved.';
        else
            raise exception 'Report not found.';
        end if;
    end if;

    insert into public.moderation_actions (actor_id, action_type, target_type, target_id, note)
    values (auth.uid(), 'report_resolved', v_report.target_type, v_report.target_id, p_note);

    -- Notifies the reporter their report was actioned — build_id is
    -- intentionally omitted (defaults to null; see 0031's widening of
    -- create_notification() and notifications.build_id, since a report
    -- resolution isn't necessarily about a build at all).
    perform public.create_notification(v_report.reporter_id, auth.uid(), 'report_resolved');

    return v_report;
end;
$$;

revoke all on function public.resolve_report(uuid, text, text) from public;
grant execute on function public.resolve_report(uuid, text, text) to authenticated;

commit;
