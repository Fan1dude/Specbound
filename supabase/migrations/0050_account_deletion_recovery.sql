-- Migration: 0050_account_deletion_recovery
-- Milestone: none — Launch Readiness self-service account deletion,
-- second security-review fix. Status: PROPOSED — not yet applied.
-- Depends on 0000-0049 being applied first.
--
-- Purpose: closes a real, previously-disclosed gap in the delete-account
-- flow (0049's own PR review): once `supabase.auth.admin.deleteUser()`
-- succeeds, the former user has no valid session — `auth.getUser()`
-- inside the delete-account Edge Function can never succeed for them
-- again. If Storage cleanup then fails, or the function's own execution
-- is interrupted between Auth deletion and Storage cleanup, there was
-- previously NO way to resume that work — the account_deletion_jobs row
-- was structurally ready to support a resume mechanism (state,
-- storage_paths, storage_cleanup_attempts all already existed, 0047),
-- but nothing in the codebase ever read it back. This migration adds
-- the server-side, service-role-only primitives a recovery worker needs;
-- supabase/functions/account-deletion-recovery is that worker (its own
-- header documents invocation/scheduling and the secret that protects
-- it — this migration is the database half only).
--
-- Also fixes two real bugs found while building this, both in the
-- ORIGINAL (non-recovery) delete-account Edge Function's own Storage
-- step, present since it was first implemented:
--
--   1. Storage cleanup failure was marking the job COMPLETE. The
--      original index.ts always set `state: "storage_cleaned"` after
--      attempting Storage removal, REGARDLESS of whether the removal
--      actually succeeded — a failed `storage.remove()` call only set
--      `last_error_code`, never kept the job in a still-pending state.
--      A job that hit this path could never be retried by anything,
--      including this migration's own new recovery worker, since its
--      state already claimed "cleaned." Fixed by moving the actual
--      completion decision into `record_account_deletion_storage_result()`
--      below: the job only reaches `storage_cleaned` when the caller
--      reports zero remaining paths.
--   2. `storage_cleanup_attempts` was hardcoded to the literal `1` on
--      every call, never actually incremented — a job that failed
--      Storage cleanup three times would still show `1`, not `3`, in
--      its own retry-count column. Fixed the same way, by moving the
--      increment into the function below (`storage_cleanup_attempts =
--      storage_cleanup_attempts + 1`), the single place that column is
--      now ever written.
--
-- Both fixes apply to the ORIGINAL delete-account Edge Function's own
-- first attempt too (supabase/functions/delete-account/index.ts), not
-- only to retries — see that function's own updated header. The actual
-- per-path Storage removal logic (retry remaining paths individually,
-- rather than one all-or-nothing batch call) lives in
-- supabase/functions/delete-account/lib.ts's
-- `removeStoragePathsIndividually()`, shared by both Edge Functions so
-- the two paths cannot silently drift apart on what counts as success.
--
--   `account_deletion_jobs` gains three columns:
--     `claimed_at`/`claimed_by` — a lease: a worker "claims" a job by
--       setting both, and a claim older than its own lease window is
--       treated as abandoned (a crashed worker) and reclaimable by
--       anyone. Not a lock in the SQL sense by itself — the actual
--       concurrency guarantee comes from `claim_account_deletion_jobs()`
--       below using `FOR UPDATE SKIP LOCKED` inside the same statement
--       that sets these columns, so two workers calling it
--       simultaneously can never claim the same row (one's row lock
--       makes `SKIP LOCKED` skip it for the other, even before either
--       transaction commits — the lease is only needed to recover from a
--       worker that claimed a row and then crashed or timed out before
--       ever releasing it).
--     `recovery_attempts` — bounded retry counter for the Auth-deletion
--       phase specifically (mirrors `storage_cleanup_attempts`, 0047,
--       which already existed for the Storage phase). A job that
--       exhausts either bound moves to `state = 'failed'` — the existing
--       "requires manual (adult-operator/support) attention" terminal
--       state 0047's own header already defines; this migration does not
--       change what `'failed'` means, and the recovery worker
--       deliberately never claims a `'failed'` job automatically (see
--       `claim_account_deletion_jobs()` below).
--
--   `claim_account_deletion_jobs(p_worker_id, p_limit, p_lease_seconds,
--   p_max_attempts)` — the atomic claim operation. Selects only
--   `'db_prepared'` (Auth deletion still pending) and `'auth_deleted'`
--   (Storage cleanup still pending) jobs, only those under their own
--   phase's attempt bound, only those not currently claimed by a live
--   lease, locks them with `FOR UPDATE SKIP LOCKED`, and marks them
--   claimed in the same statement. Two concurrent callers can never
--   receive the same row — this is the standard, well-established
--   Postgres job-queue claim idiom (`UPDATE ... WHERE id IN (SELECT ...
--   FOR UPDATE SKIP LOCKED) RETURNING *`), not a novel mechanism.
--
--   `record_account_deletion_auth_result(p_job_id, p_success,
--   p_error_code, p_max_attempts)` — records the outcome of a claimed
--   job's Auth-deletion attempt. On success: `'db_prepared' ->
--   'auth_deleted'`, clears the claim. On failure: increments
--   `recovery_attempts`, clears the claim (so the NEXT scheduled run can
--   reclaim it — the run interval itself is the retry backoff, see the
--   Edge Function's own header), and moves to `'failed'` only once the
--   bound is reached. Every update is additionally gated on the job
--   still being in the expected starting state (`where ... and state =
--   'db_prepared'`), so a call against a job that has already moved on
--   (a race, or a job an operator has manually touched) is a safe no-op,
--   not a corrupting write — the function returns `false` in that case
--   so a caller can log it, rather than silently assuming success.
--
--   `record_account_deletion_storage_result(p_job_id, p_remaining_paths,
--   p_error_code, p_max_attempts)` — same shape, for the Storage phase.
--   `p_remaining_paths` is the FULL set of paths still not confirmed
--   removed after this attempt (not a delta) — the caller (either Edge
--   Function) is expected to have already tried every path individually
--   via `removeStoragePathsIndividually()` and pass back only what is
--   still outstanding. An empty array here is what actually completes
--   the job (`state = 'storage_cleaned'`); anything else keeps it in
--   `'auth_deleted'` (or moves it to `'failed'` once
--   `storage_cleanup_attempts` reaches the bound) with `storage_paths`
--   updated to the real remainder, never the original full list —
--   this is the "preserve paths that still failed instead of marking
--   the entire job complete" property directly.
--
--   ACL, for all three functions: `revoke all ... from public`, then
--   `grant execute ... to service_role` ONLY — never `anon`, never
--   `authenticated`. This project's own Data API auto-exposure default
--   is OFF (supabase/config.toml's own comment on this), so no role gets
--   implicit access either. Combined with
--   `account-deletion-recovery`'s own shared-secret gate (its own
--   header) and the fact that it is never invoked with a normal user
--   session at all, this means an ordinary signed-in user cannot reach
--   these functions through any path: not through PostgREST directly
--   (no EXECUTE grant for their role), and not through the recovery Edge
--   Function (it never forwards a caller's own JWT to anything — it
--   holds only the service-role key, read once from its own environment,
--   same posture as delete-account's adminClient).
--
-- Touches: `public.account_deletion_jobs` (0047) — adds three columns
-- only, no existing column changed or dropped. Does not modify
-- `0044`-`0049`'s own files, and does not touch
-- `public.self_delete_account()`/`public.request_account_deletion_challenge()`
-- (0049) at all — the recovery worker never calls either; it operates
-- entirely through the service-role-only functions defined here.
--
-- Rollback: see 0050_account_deletion_recovery_rollback.sql in
-- supabase/rollbacks/.

begin;

alter table public.account_deletion_jobs
    add column claimed_at timestamptz,
    add column claimed_by text,
    add column recovery_attempts integer not null default 0
        check (recovery_attempts >= 0);

create or replace function public.claim_account_deletion_jobs(
    p_worker_id text,
    p_limit integer default 5,
    p_lease_seconds integer default 120,
    p_max_attempts integer default 20
)
returns setof public.account_deletion_jobs
language sql
security definer
set search_path = public, pg_temp
as $$
    update public.account_deletion_jobs
    set claimed_at = now(),
        claimed_by = p_worker_id
    where id in (
        select id
        from public.account_deletion_jobs
        where (
                (state = 'db_prepared' and recovery_attempts < p_max_attempts)
                or (state = 'auth_deleted' and storage_cleanup_attempts < p_max_attempts)
              )
          and (claimed_at is null or claimed_at < now() - make_interval(secs => p_lease_seconds))
        order by created_at asc
        limit greatest(p_limit, 0)
        for update skip locked
    )
    returning *;
$$;

revoke all on function public.claim_account_deletion_jobs(text, integer, integer, integer) from public;
grant execute on function public.claim_account_deletion_jobs(text, integer, integer, integer) to service_role;

create or replace function public.record_account_deletion_auth_result(
    p_job_id uuid,
    p_success boolean,
    p_error_code text default null,
    p_max_attempts integer default 20
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_rows integer;
    v_new_attempts integer;
begin
    if p_success then
        -- Idempotent Auth deletion (see the recovery worker's own
        -- header for the "already-deleted counts as success" case) also
        -- lands here — the caller decides success, this function only
        -- ever records it.
        update public.account_deletion_jobs
            set state = 'auth_deleted',
                claimed_at = null,
                claimed_by = null,
                last_error_code = null
            where id = p_job_id and state = 'db_prepared';
        get diagnostics v_rows = row_count;
        return v_rows > 0;
    end if;

    update public.account_deletion_jobs
        set recovery_attempts = recovery_attempts + 1,
            claimed_at = null,
            claimed_by = null,
            last_error_code = p_error_code
        where id = p_job_id and state = 'db_prepared'
        returning recovery_attempts into v_new_attempts;
    get diagnostics v_rows = row_count;

    if v_rows = 0 then
        return false;
    end if;

    if v_new_attempts >= p_max_attempts then
        update public.account_deletion_jobs
            set state = 'failed'
            where id = p_job_id;
    end if;

    return true;
end;
$$;

revoke all on function public.record_account_deletion_auth_result(uuid, boolean, text, integer) from public;
grant execute on function public.record_account_deletion_auth_result(uuid, boolean, text, integer) to service_role;

create or replace function public.record_account_deletion_storage_result(
    p_job_id uuid,
    p_remaining_paths text[],
    p_error_code text default null,
    p_max_attempts integer default 20
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_rows integer;
    v_new_attempts integer;
begin
    if coalesce(array_length(p_remaining_paths, 1), 0) = 0 then
        update public.account_deletion_jobs
            set state = 'storage_cleaned',
                storage_paths = '{}',
                storage_cleanup_attempts = storage_cleanup_attempts + 1,
                claimed_at = null,
                claimed_by = null,
                last_error_code = null,
                completed_at = now()
            where id = p_job_id and state = 'auth_deleted';
        get diagnostics v_rows = row_count;
        return v_rows > 0;
    end if;

    update public.account_deletion_jobs
        set storage_paths = p_remaining_paths,
            storage_cleanup_attempts = storage_cleanup_attempts + 1,
            claimed_at = null,
            claimed_by = null,
            last_error_code = p_error_code
        where id = p_job_id and state = 'auth_deleted'
        returning storage_cleanup_attempts into v_new_attempts;
    get diagnostics v_rows = row_count;

    if v_rows = 0 then
        return false;
    end if;

    if v_new_attempts >= p_max_attempts then
        update public.account_deletion_jobs
            set state = 'failed'
            where id = p_job_id;
    end if;

    return true;
end;
$$;

revoke all on function public.record_account_deletion_storage_result(uuid, text[], text, integer) from public;
grant execute on function public.record_account_deletion_storage_result(uuid, text[], text, integer) to service_role;

commit;
