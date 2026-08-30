-- Rollback for: 0051_account_deletion_jobs_wall_clock_updated_at
--
-- No data-loss guard needed: this migration never dropped or altered
-- any column or row, only which trigger function fires on UPDATE.
-- Rolling back restores 0047's original trigger (the shared
-- `public.set_updated_at()`, unaffected by this PR either way) and
-- drops the dedicated function this migration added — reintroducing,
-- for `account_deletion_jobs` specifically, the transaction-constant
-- `updated_at` behavior 0051's own header documents as a real (if
-- minor) loss of audit fidelity for this table's multi-write-per-
-- transaction cases. Every other table in this codebase already has
-- this same underlying behavior via the shared trigger regardless of
-- this rollback, since 0051 never touched `public.set_updated_at()`
-- itself.

begin;

drop trigger if exists account_deletion_jobs_set_updated_at on public.account_deletion_jobs;

create trigger account_deletion_jobs_set_updated_at
    before update on public.account_deletion_jobs
    for each row
    execute function public.set_updated_at();

drop function if exists public.set_account_deletion_jobs_updated_at();

commit;
