-- Rollback for: 0047_account_deletion_jobs
--
-- Security-review requirement: refuses to proceed (raises, does not
-- drop anything) if any row exists in account_deletion_jobs — silently
-- dropping real orchestration/audit history (including a job that is
-- mid-flight, not yet 'storage_cleaned'/'failed') is exactly the kind
-- of unsafe reversal this guard exists to prevent, matching
-- 0045_moderation_actions_preserve_audit_rollback.sql's identical
-- posture for a structurally similar situation. If rows genuinely need
-- to be cleared first (e.g. only long-'storage_cleaned'/'failed' rows
-- remain and are deliberately being retired), do that explicitly and
-- separately, with its own review, before running this rollback — this
-- file does not do it implicitly.
--
-- Does not drop public.set_updated_at() -- that function is shared with
-- other tables (0001_project_drafts_and_media.sql) and is not owned by
-- this migration.

begin;

do $$
begin
    if exists (select 1 from public.account_deletion_jobs limit 1) then
        raise exception 'Cannot roll back 0047: account_deletion_jobs contains at least one row. Resolve or deliberately clear it in its own reviewed step first -- this rollback refuses to silently destroy orchestration/audit history.';
    end if;
end $$;

drop trigger if exists account_deletion_jobs_set_updated_at on public.account_deletion_jobs;
drop table if exists public.account_deletion_jobs;

commit;
