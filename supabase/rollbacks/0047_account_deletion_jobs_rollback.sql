-- Rollback for: 0047_account_deletion_jobs
--
-- Drops the account_deletion_jobs table and its trigger. Destroys any
-- in-flight or historical orchestration records -- if a deletion is
-- currently in progress (state not yet 'storage_cleaned'/'failed'),
-- resolve or deliberately accept losing recoverability for it before
-- running this. Does not drop public.set_updated_at() -- that function
-- is shared with other tables (0001_project_drafts_and_media.sql) and
-- is not owned by this migration.

begin;

drop trigger if exists account_deletion_jobs_set_updated_at on public.account_deletion_jobs;
drop table if exists public.account_deletion_jobs;

commit;
