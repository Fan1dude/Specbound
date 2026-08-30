-- Rollback for: 0050_account_deletion_recovery
--
-- Lighter guard than 0046/0047/0045's own rollbacks: the three columns
-- and three functions this migration adds are pure retry/orchestration
-- bookkeeping, not irreplaceable audit history (unlike legal_holds or
-- moderation_actions) — losing a `recovery_attempts`/
-- `storage_cleanup_attempts` counter on rollback, when nothing is
-- actually mid-claim, is just resetting a retry count, not destroying a
-- record anything else depends on. Still refuses to proceed if any job
-- is CURRENTLY claimed (`claimed_at is not null`) — rolling back while a
-- recovery worker genuinely believes it holds a lease on a row would
-- silently orphan that in-flight attempt with no trace of which worker
-- had it or why. Resolve or wait out any live claim first.
--
-- After this rollback, supabase/functions/account-deletion-recovery can
-- no longer do anything (its own claim/record RPCs are gone) — its own
-- header's disclosed limitation (no resume path once the original
-- user's JWT stops working) is reintroduced. Do not run this rollback
-- with that Edge Function still deployed and scheduled without also
-- disabling its schedule first, or its next scheduled invocation will
-- fail loudly (a missing function, not silent data loss) the moment it
-- tries to call `claim_account_deletion_jobs()`.

begin;

do $$
begin
    if exists (select 1 from public.account_deletion_jobs where claimed_at is not null) then
        raise exception 'Cannot roll back 0050: at least one account_deletion_jobs row is currently claimed (claimed_at is not null). Wait for the claim''s lease to be released or expire, or resolve it manually, before rolling back -- this refuses to silently orphan an in-flight recovery attempt.';
    end if;
end $$;

drop function if exists public.record_account_deletion_storage_result(uuid, text[], text, integer);
drop function if exists public.record_account_deletion_auth_result(uuid, boolean, text, integer);
drop function if exists public.claim_account_deletion_jobs(text, integer, integer, integer);

alter table public.account_deletion_jobs
    drop column if exists recovery_attempts,
    drop column if exists claimed_by,
    drop column if exists claimed_at;

commit;
