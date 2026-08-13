-- Rollback for: 0036_resolve_report_atomic_status_guard
--
-- *** WARNING: running this restores the double-resolution race that
-- *** 0036 was written to fix — resolve_report() goes back to matching
-- *** by report id alone, with no status guard, and a second call
-- *** against an already-resolved report will once again silently
-- *** succeed, overwrite the prior decision, and create a duplicate
-- *** moderation_actions row and reporter notification. Do not run this
-- *** without a specific, reviewed reason.
--
-- Restores resolve_report(uuid, text, text) to its exact pre-0036 body —
-- verbatim from 0028_moderation.sql (migration-evidenced, not
-- reconstructed). Same signature, security mode, search_path, and
-- grants as before; only the function body changes. No table, column,
-- or existing content_reports/moderation_actions/notifications row is
-- touched by this rollback — resolutions already recorded under 0036's
-- guarded behavior are left exactly as they are.

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

    update public.content_reports
        set status = p_status, reviewed_by = auth.uid(), reviewed_at = now()
        where id = p_report_id
        returning * into v_report;

    if v_report is null then
        raise exception 'Report not found.';
    end if;

    insert into public.moderation_actions (actor_id, action_type, target_type, target_id, note)
    values (auth.uid(), 'report_resolved', v_report.target_type, v_report.target_id, p_note);

    perform public.create_notification(v_report.reporter_id, auth.uid(), 'report_resolved');

    return v_report;
end;
$$;

revoke all on function public.resolve_report(uuid, text, text) from public;
grant execute on function public.resolve_report(uuid, text, text) to authenticated;

commit;
