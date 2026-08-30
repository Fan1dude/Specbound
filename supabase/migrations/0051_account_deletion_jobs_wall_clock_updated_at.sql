-- Migration: 0051_account_deletion_jobs_wall_clock_updated_at
-- Milestone: none — Launch Readiness self-service account deletion,
-- third security-review fix (real local Supabase/Docker testing this
-- time, not static review). Status: PROPOSED — not yet applied.
-- Depends on 0000-0050 being applied first.
--
-- Purpose: fixes a real bug real local testing found —
-- `migration_0047_account_deletion_jobs.test.sql`'s own test 4 failed:
--
--   FAIL (test 4): updated_at did not advance on UPDATE
--   before=2026-08-30 20:55:19.940503+00
--   after=2026-08-30 20:55:19.940503+00
--
-- Root cause: `public.set_updated_at()` (0001_project_drafts_and_media.sql,
-- the shared trigger function every `updated_at` column in this codebase
-- uses) sets `new.updated_at = now()`. In Postgres, `now()` is an alias
-- for `transaction_timestamp()` — it returns the SAME value for every
-- call within one transaction, no matter how much real wall-clock time
-- passes or how many statements run in between (confirmed directly:
-- `pg_sleep()` genuinely blocks for real time, but does not advance
-- `now()`'s return value inside the transaction that called it — only
-- `clock_timestamp()` reads the actual OS clock on each call). This is
-- not a new bug introduced by this PR — it has been latent in
-- `public.set_updated_at()`, for every table using it, since migration
-- 0001. `account_deletion_jobs`'s own test (0047, part of the original
-- self-service-deletion implementation, not this review's own new code)
-- is simply the first test in this codebase to perform a genuine
-- multi-statement, same-transaction check of whether `updated_at`
-- actually advances — every other table's own tests happened not to
-- exercise this specific case.
--
-- THE INTENDED GUARANTEE, decided and documented here per the review
-- that found this: for `account_deletion_jobs` specifically — durable
-- deletion/recovery orchestration bookkeeping, read by support
-- operators and (0050) the recovery worker to answer "when was this job
-- last genuinely touched" — `updated_at` MUST represent the actual
-- wall-clock time of the write, including the case where a single
-- transaction performs more than one UPDATE against the same row (this
-- happens for real in this PR's own code: `record_account_deletion_auth_result()`/
-- `record_account_deletion_storage_result()`, 0050, can each perform a
-- second UPDATE — moving a job to `'failed'` — immediately after a
-- first UPDATE that recorded the attempt, within the same function call/
-- transaction). An operator or the recovery worker seeing two real,
-- distinct writes collapse to one identical timestamp would be a
-- genuine, if minor, loss of audit fidelity for exactly the kind of
-- record this table exists to keep faithfully.
--
-- THE FIX, scoped deliberately to this ONE table, not the shared
-- function: `public.set_updated_at()` (0001) is used by many other,
-- already-shipped tables entirely outside this PR's scope (`project_drafts`,
-- `builds`, the catalog tables, `retailers`, etc.). Changing ITS
-- behavior globally, as a side effect of an account-deletion PR review,
-- would silently change `updated_at` semantics for every one of those
-- tables too — a bigger, cross-cutting decision that deserves its own
-- dedicated review, not one bundled quietly in here. `set_updated_at()`
-- itself is therefore left completely untouched by this migration.
-- Instead, `account_deletion_jobs` gets its OWN dedicated trigger
-- function, `set_account_deletion_jobs_updated_at()`, using
-- `clock_timestamp()`, and its existing trigger (0047) is dropped and
-- recreated to call it instead of the shared one.
--
--   DISCLOSED, NOT FIXED HERE: this same latent bug affects every other
--   `updated_at` column in this codebase that uses the shared
--   `public.set_updated_at()` trigger (i.e., everywhere else `updated_at`
--   exists) — none of them are known to depend on multi-write-same-
--   transaction advancement the way this review specifically checked
--   for here, so this migration does not change them, but this is a
--   real, systemic finding worth its own separate decision, not a claim
--   that no other table could ever be affected.
--
--   `claimed_at` (0050) is DELIBERATELY left using `now()`, not changed
--   here: a single `claim_account_deletion_jobs()` call can claim
--   several rows in one UPDATE statement, and every row claimed in that
--   one batch SHOULD share the identical claim timestamp (they were all
--   claimed "at the same moment," not several microseconds apart by
--   evaluation order) — `clock_timestamp()` here would add spurious
--   per-row precision that doesn't reflect anything meaningful, and
--   `claimed_at` is never compared against another value written within
--   the SAME transaction (the lease check in the SAME function compares
--   against a claim written by a PREVIOUS, already-committed
--   transaction, so `now()`'s transaction-constant behavior does not
--   affect it either way).
--
--   `created_at`/`completed_at`/`account_deletion_challenges.expires_at`
--   are each written exactly once per row, never compared against a
--   second write to the same row within the same transaction — `now()`
--   remains correct and unchanged for all of them.
--
--   Retry ordering: `claim_account_deletion_jobs()` orders by
--   `created_at asc` (0050), never by `updated_at` — this migration
--   does not change that, and confirms it was never exposed to this bug
--   in the first place.
--
-- Touches: `public.account_deletion_jobs` (0047) — replaces its trigger
-- only; the table's own columns are unchanged. Does not modify `0001`'s
-- or `0047`'s own files, and does not touch `public.set_updated_at()`.
--
-- Rollback: see 0051_account_deletion_jobs_wall_clock_updated_at_rollback.sql
-- in supabase/rollbacks/. Restores the 0047-original trigger (the
-- shared `public.set_updated_at()`), reintroducing this bug for this
-- table specifically.

begin;

create or replace function public.set_account_deletion_jobs_updated_at()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
    new.updated_at = clock_timestamp();
    return new;
end;
$$;

-- Same posture as public.set_updated_at() (0016_security_definer_hygiene.sql):
-- a trigger function's invocation, fired implicitly by the DML statement
-- that activates it, is governed by table-level privileges on
-- account_deletion_jobs (RLS enabled, zero policies, 0047), not by
-- EXECUTE grants on the trigger function itself -- revoking EXECUTE here
-- does not stop the trigger from firing for any role permitted to UPDATE
-- the table (in practice, only the SECURITY DEFINER functions in 0049/
-- 0050 and the service-role Edge Functions ever do).
revoke all on function public.set_account_deletion_jobs_updated_at() from public;

drop trigger if exists account_deletion_jobs_set_updated_at on public.account_deletion_jobs;

create trigger account_deletion_jobs_set_updated_at
    before update on public.account_deletion_jobs
    for each row
    execute function public.set_account_deletion_jobs_updated_at();

commit;
