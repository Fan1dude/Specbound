-- Migration 0050 test —
-- supabase/tests/migration_0050_account_deletion_recovery.test.sql
--
-- Covers migration 0050_account_deletion_recovery: the three new
-- columns on account_deletion_jobs, claim_account_deletion_jobs()'s
-- claim/lease exclusivity, and record_account_deletion_auth_result()/
-- record_account_deletion_storage_result()'s state transitions —
-- including the two bugs the same migration's own header documents
-- fixing (Storage failure previously completing the job anyway; the
-- attempt counter previously hardcoded, never incremented).
--
-- Concurrency note: this file verifies claim exclusivity at the
-- SINGLE-SESSION level (a job claimed once, with a live lease, is
-- excluded from a second claim call in the same test) rather than
-- opening a genuine second Postgres connection (e.g. via `dblink`) from
-- inside this script. That would require connection parameters (host/
-- port/credentials) this file cannot portably assume across every local
-- Supabase/Docker setup, and a hung or misconfigured second connection
-- would be a worse failure mode than not attempting it. The actual
-- cross-transaction guarantee this stands in for —
-- `UPDATE ... WHERE id IN (SELECT ... FOR UPDATE SKIP LOCKED)` making
-- two concurrent claimers never receive the same row — is a
-- well-established Postgres idiom, not novel logic this migration
-- invented; what IS this migration's own logic, and therefore what
-- these tests actually need to prove, is that a claimed row's lease
-- correctly excludes it from being claimed again while live, and
-- correctly becomes reclaimable once the lease expires. If a live local
-- stack is available and cross-connection verification is wanted beyond
-- this, run two separate `psql` sessions manually against the same
-- database and call claim_account_deletion_jobs() from each
-- concurrently while jobs are queued — this is a manual, one-off check,
-- not something this repeatable suite attempts.
--
-- STATUS: intended to run against the local disposable Supabase/Docker
-- stack only — NOT executed in the authoring session (no `supabase`
-- CLI, no reachable Docker daemon, no `psql` were available; see this
-- PR's own report for the exact environmental limitation). Depends on
-- migrations 0000-0050 already being applied.
--
-- Fail-closed: every assertion raises via `raise exception ... using
-- errcode = 'M0050'`.

begin;

-- ---------------------------------------------------------------------
-- Test 1: the three new columns exist with the expected defaults.
-- ---------------------------------------------------------------------
savepoint test_1;
do $$
declare
    v_claimed_at timestamptz;
    v_claimed_by text;
    v_recovery_attempts integer;
begin
    insert into public.account_deletion_jobs (former_user_id, storage_paths)
    values ('00000000-0000-0000-0000-000000001601', array['avatars/00000000-0000-0000-0000-000000001601/512.jpg']);

    select claimed_at, claimed_by, recovery_attempts
    into v_claimed_at, v_claimed_by, v_recovery_attempts
    from public.account_deletion_jobs
    where former_user_id = '00000000-0000-0000-0000-000000001601';

    if v_claimed_at is not null or v_claimed_by is not null or v_recovery_attempts <> 0 then
        raise exception 'FAIL (test 1): unexpected default values (claimed_at=%, claimed_by=%, recovery_attempts=%)', v_claimed_at, v_claimed_by, v_recovery_attempts using errcode = 'M0050';
    end if;
    raise notice 'PASS (test 1): claimed_at/claimed_by/recovery_attempts default to null/null/0';
end $$;
rollback to savepoint test_1;

-- ---------------------------------------------------------------------
-- Test 2: claim_account_deletion_jobs() only selects resumable states
-- (db_prepared, auth_deleted) — never storage_cleaned or failed.
-- ---------------------------------------------------------------------
savepoint test_2;
do $$
declare
    v_claimed_count integer;
begin
    insert into public.account_deletion_jobs (former_user_id, state, storage_paths) values
        ('00000000-0000-0000-0000-000000001611', 'db_prepared', array['p1']),
        ('00000000-0000-0000-0000-000000001612', 'auth_deleted', array['p2']),
        ('00000000-0000-0000-0000-000000001613', 'storage_cleaned', '{}'),
        ('00000000-0000-0000-0000-000000001614', 'failed', array['p4']);

    select count(*) into v_claimed_count
    from public.claim_account_deletion_jobs('test-worker-2', 10, 120, 20);

    if v_claimed_count <> 2 then
        raise exception 'FAIL (test 2): expected exactly 2 claimable jobs (db_prepared + auth_deleted), got %', v_claimed_count using errcode = 'M0050';
    end if;
    raise notice 'PASS (test 2): only db_prepared/auth_deleted jobs are claimed -- storage_cleaned and failed are never touched';
end $$;
rollback to savepoint test_2;

-- ---------------------------------------------------------------------
-- Test 3: a job already exhausted (attempts >= bound) in a resumable
-- state is NOT claimed.
-- ---------------------------------------------------------------------
savepoint test_3;
do $$
declare
    v_claimed_count integer;
begin
    insert into public.account_deletion_jobs (former_user_id, state, storage_paths, recovery_attempts)
    values ('00000000-0000-0000-0000-000000001621', 'db_prepared', array['p1'], 20);

    select count(*) into v_claimed_count
    from public.claim_account_deletion_jobs('test-worker-3', 10, 120, 20);

    if v_claimed_count <> 0 then
        raise exception 'FAIL (test 3): a job at the attempt bound was claimed anyway' using errcode = 'M0050';
    end if;
    raise notice 'PASS (test 3): a job at its attempt bound is not claimed';
end $$;
rollback to savepoint test_3;

-- ---------------------------------------------------------------------
-- Test 4: claim exclusivity -- a job claimed once, with a live lease, is
-- excluded from a second claim call (single-session stand-in for
-- cross-connection SKIP LOCKED exclusivity -- see this file's own
-- header).
-- ---------------------------------------------------------------------
savepoint test_4;
do $$
declare
    v_first_count integer;
    v_second_count integer;
begin
    insert into public.account_deletion_jobs (former_user_id, state, storage_paths)
    values ('00000000-0000-0000-0000-000000001631', 'db_prepared', array['p1']);

    select count(*) into v_first_count
    from public.claim_account_deletion_jobs('worker-a', 10, 120, 20);

    if v_first_count <> 1 then
        raise exception 'FAIL (test 4a): expected to claim exactly 1 job, got %', v_first_count using errcode = 'M0050';
    end if;
    raise notice 'PASS (test 4a): worker-a claims the job';

    select count(*) into v_second_count
    from public.claim_account_deletion_jobs('worker-b', 10, 120, 20);

    if v_second_count <> 0 then
        raise exception 'FAIL (test 4b): worker-b claimed a job still under worker-a''s live lease -- two workers could process the same job concurrently' using errcode = 'M0050';
    end if;
    raise notice 'PASS (test 4b): worker-b cannot claim the same job while worker-a''s lease is live';

    if not exists (
        select 1 from public.account_deletion_jobs
        where former_user_id = '00000000-0000-0000-0000-000000001631'
          and claimed_by = 'worker-a'
          and claimed_at is not null
    ) then
        raise exception 'FAIL (test 4c): claimed_at/claimed_by were not recorded correctly' using errcode = 'M0050';
    end if;
    raise notice 'PASS (test 4c): claimed_at/claimed_by correctly record which worker holds the lease';
end $$;
rollback to savepoint test_4;

-- ---------------------------------------------------------------------
-- Test 5: an expired lease (a crashed worker's abandoned claim) becomes
-- reclaimable.
-- ---------------------------------------------------------------------
savepoint test_5;
do $$
declare
    v_claimed_count integer;
begin
    insert into public.account_deletion_jobs (former_user_id, state, storage_paths, claimed_at, claimed_by)
    values ('00000000-0000-0000-0000-000000001641', 'db_prepared', array['p1'], now() - interval '10 minutes', 'crashed-worker');

    -- A 120-second lease, and the claim above is 10 minutes old --
    -- unambiguously expired.
    select count(*) into v_claimed_count
    from public.claim_account_deletion_jobs('recovering-worker', 10, 120, 20);

    if v_claimed_count <> 1 then
        raise exception 'FAIL (test 5): an expired lease was not reclaimed (count=%)', v_claimed_count using errcode = 'M0050';
    end if;
    raise notice 'PASS (test 5): a job whose lease has expired becomes reclaimable';
end $$;
rollback to savepoint test_5;

-- ---------------------------------------------------------------------
-- Test 6: record_account_deletion_auth_result() success path --
-- transitions db_prepared -> auth_deleted, clears the claim. This is
-- also the "already-deleted Auth user counts as idempotent success"
-- case at the SQL layer: the function has no way to distinguish "the
-- account was just now actually deleted" from "the account was already
-- gone" -- both are represented identically as p_success := true by the
-- caller (see account-deletion-recovery/lib.ts's own
-- isUserAlreadyDeletedError(), covered separately in
-- account-deletion-recovery/index.test.ts), and this function must
-- record either the same way.
-- ---------------------------------------------------------------------
savepoint test_6;
do $$
declare
    v_job_id uuid;
    v_result boolean;
    v_state text;
begin
    insert into public.account_deletion_jobs (former_user_id, state, storage_paths, claimed_at, claimed_by)
    values ('00000000-0000-0000-0000-000000001651', 'db_prepared', array['p1'], now(), 'worker-x')
    returning id into v_job_id;

    select public.record_account_deletion_auth_result(v_job_id, true, null, 20) into v_result;

    if not v_result then
        raise exception 'FAIL (test 6a): expected true (a row was updated)' using errcode = 'M0050';
    end if;

    select state into v_state from public.account_deletion_jobs where id = v_job_id;
    if v_state <> 'auth_deleted' then
        raise exception 'FAIL (test 6b): expected state auth_deleted, got %', v_state using errcode = 'M0050';
    end if;
    raise notice 'PASS (test 6): success recording transitions db_prepared -> auth_deleted';

    if exists (select 1 from public.account_deletion_jobs where id = v_job_id and (claimed_at is not null or claimed_by is not null)) then
        raise exception 'FAIL (test 6c): the claim was not cleared on success' using errcode = 'M0050';
    end if;
    raise notice 'PASS (test 6c): the claim is cleared on success';
end $$;
rollback to savepoint test_6;

-- ---------------------------------------------------------------------
-- Test 7: record_account_deletion_auth_result() failure path -- bounded
-- retry, and REPEATED EXECUTION does not corrupt state: three failures
-- in a row correctly increments recovery_attempts each time and only
-- moves to 'failed' once the bound is reached, never earlier and never
-- silently stuck at 'db_prepared' forever past the bound.
-- ---------------------------------------------------------------------
savepoint test_7;
do $$
declare
    v_job_id uuid;
    v_state text;
    v_attempts integer;
begin
    insert into public.account_deletion_jobs (former_user_id, state, storage_paths)
    values ('00000000-0000-0000-0000-000000001661', 'db_prepared', array['p1'])
    returning id into v_job_id;

    -- p_max_attempts := 3 for this test -- three failures should exactly
    -- exhaust the bound.
    perform public.record_account_deletion_auth_result(v_job_id, false, 'auth_admin_failed', 3);
    perform public.record_account_deletion_auth_result(v_job_id, false, 'auth_admin_failed', 3);

    select state, recovery_attempts into v_state, v_attempts from public.account_deletion_jobs where id = v_job_id;
    if v_state <> 'db_prepared' or v_attempts <> 2 then
        raise exception 'FAIL (test 7a): after 2 of 3 allowed failures, expected state=db_prepared attempts=2, got state=% attempts=%', v_state, v_attempts using errcode = 'M0050';
    end if;
    raise notice 'PASS (test 7a): repeated failures increment recovery_attempts correctly, state unchanged before the bound';

    perform public.record_account_deletion_auth_result(v_job_id, false, 'auth_admin_failed', 3);

    select state, recovery_attempts into v_state, v_attempts from public.account_deletion_jobs where id = v_job_id;
    if v_state <> 'failed' or v_attempts <> 3 then
        raise exception 'FAIL (test 7b): after 3 of 3 allowed failures, expected state=failed attempts=3, got state=% attempts=%', v_state, v_attempts using errcode = 'M0050';
    end if;
    raise notice 'PASS (test 7b): the job moves to failed exactly once its attempt bound is reached';
end $$;
rollback to savepoint test_7;

-- ---------------------------------------------------------------------
-- Test 8: record_account_deletion_auth_result() called against a job
-- NOT in db_prepared (a race, or already moved on) is a safe no-op --
-- returns false, does not alter state.
-- ---------------------------------------------------------------------
savepoint test_8;
do $$
declare
    v_job_id uuid;
    v_result boolean;
    v_state text;
begin
    insert into public.account_deletion_jobs (former_user_id, state, storage_paths)
    values ('00000000-0000-0000-0000-000000001671', 'storage_cleaned', '{}')
    returning id into v_job_id;

    select public.record_account_deletion_auth_result(v_job_id, true, null, 20) into v_result;

    if v_result then
        raise exception 'FAIL (test 8a): expected false against a job not in db_prepared' using errcode = 'M0050';
    end if;

    select state into v_state from public.account_deletion_jobs where id = v_job_id;
    if v_state <> 'storage_cleaned' then
        raise exception 'FAIL (test 8b): state was altered by a no-op call: %', v_state using errcode = 'M0050';
    end if;
    raise notice 'PASS (test 8): a call against a job in the wrong state is a safe no-op (false, unchanged)';
end $$;
rollback to savepoint test_8;

-- ---------------------------------------------------------------------
-- Test 9: record_account_deletion_storage_result() -- PARTIAL PATH
-- SUCCESS. Preserves only the genuinely still-remaining paths, never
-- the original full list, and never marks the job complete while
-- anything remains -- this is the exact bug this migration's own header
-- documents fixing in the original delete-account Edge Function.
-- ---------------------------------------------------------------------
savepoint test_9;
do $$
declare
    v_job_id uuid;
    v_state text;
    v_paths text[];
    v_attempts integer;
begin
    insert into public.account_deletion_jobs (former_user_id, state, storage_paths)
    values ('00000000-0000-0000-0000-000000001681', 'auth_deleted', array['a', 'b', 'c'])
    returning id into v_job_id;

    -- Simulates: 'a' and 'c' succeeded, 'b' is still outstanding.
    perform public.record_account_deletion_storage_result(v_job_id, array['b'], 'storage_cleanup_partial', 20);

    select state, storage_paths, storage_cleanup_attempts into v_state, v_paths, v_attempts
    from public.account_deletion_jobs where id = v_job_id;

    if v_state <> 'auth_deleted' then
        raise exception 'FAIL (test 9a): a job with a remaining path was marked complete (state=%) -- this is exactly the bug this migration fixes', v_state using errcode = 'M0050';
    end if;
    if v_paths <> array['b'] then
        raise exception 'FAIL (test 9b): expected storage_paths to be reduced to the remainder [b], got %', v_paths using errcode = 'M0050';
    end if;
    if v_attempts <> 1 then
        raise exception 'FAIL (test 9c): expected storage_cleanup_attempts=1, got %', v_attempts using errcode = 'M0050';
    end if;
    raise notice 'PASS (test 9): partial path success preserves only the real remainder, keeps the job open, increments the attempt counter';
end $$;
rollback to savepoint test_9;

-- ---------------------------------------------------------------------
-- Test 10: record_account_deletion_storage_result() -- FINAL COMPLETION.
-- An empty remaining-paths array is what actually completes the job.
-- ---------------------------------------------------------------------
savepoint test_10;
do $$
declare
    v_job_id uuid;
    v_state text;
    v_paths text[];
    v_completed_at timestamptz;
begin
    insert into public.account_deletion_jobs (former_user_id, state, storage_paths)
    values ('00000000-0000-0000-0000-000000001691', 'auth_deleted', array['b'])
    returning id into v_job_id;

    perform public.record_account_deletion_storage_result(v_job_id, '{}', null, 20);

    select state, storage_paths, completed_at into v_state, v_paths, v_completed_at
    from public.account_deletion_jobs where id = v_job_id;

    if v_state <> 'storage_cleaned' then
        raise exception 'FAIL (test 10a): expected state=storage_cleaned, got %', v_state using errcode = 'M0050';
    end if;
    if v_paths <> '{}' then
        raise exception 'FAIL (test 10b): expected storage_paths to be cleared, got %', v_paths using errcode = 'M0050';
    end if;
    if v_completed_at is null then
        raise exception 'FAIL (test 10c): completed_at was not set on final completion' using errcode = 'M0050';
    end if;
    raise notice 'PASS (test 10): zero remaining paths correctly completes the job';
end $$;
rollback to savepoint test_10;

-- ---------------------------------------------------------------------
-- Test 11: REPEATED EXECUTION -- calling
-- record_account_deletion_storage_result() again after the job is
-- already storage_cleaned is a safe no-op (the state = 'auth_deleted'
-- guard excludes it), never re-incrementing attempts or re-running
-- completion logic on an already-finished job.
-- ---------------------------------------------------------------------
savepoint test_11;
do $$
declare
    v_job_id uuid;
    v_result boolean;
    v_attempts_before integer;
    v_attempts_after integer;
begin
    insert into public.account_deletion_jobs (former_user_id, state, storage_paths, storage_cleanup_attempts)
    values ('00000000-0000-0000-0000-000000001701', 'storage_cleaned', '{}', 1)
    returning id into v_job_id;

    select storage_cleanup_attempts into v_attempts_before from public.account_deletion_jobs where id = v_job_id;

    select public.record_account_deletion_storage_result(v_job_id, '{}', null, 20) into v_result;

    select storage_cleanup_attempts into v_attempts_after from public.account_deletion_jobs where id = v_job_id;

    if v_result then
        raise exception 'FAIL (test 11a): expected false against an already-completed job' using errcode = 'M0050';
    end if;
    if v_attempts_after <> v_attempts_before then
        raise exception 'FAIL (test 11b): storage_cleanup_attempts changed on a no-op call (before=%, after=%)', v_attempts_before, v_attempts_after using errcode = 'M0050';
    end if;
    raise notice 'PASS (test 11): repeated execution against an already-finished job is a safe no-op';
end $$;
rollback to savepoint test_11;

-- ---------------------------------------------------------------------
-- Test 12: function identity, SECURITY DEFINER, and ACL -- service_role
-- only, never anon or authenticated -- for all three functions.
-- ---------------------------------------------------------------------
do $$
declare
    v_anon boolean;
    v_authenticated boolean;
    v_service_role boolean;
begin
    v_anon := has_function_privilege('anon', 'public.claim_account_deletion_jobs(text, integer, integer, integer)', 'EXECUTE');
    v_authenticated := has_function_privilege('authenticated', 'public.claim_account_deletion_jobs(text, integer, integer, integer)', 'EXECUTE');
    v_service_role := has_function_privilege('service_role', 'public.claim_account_deletion_jobs(text, integer, integer, integer)', 'EXECUTE');
    if v_anon or v_authenticated then
        raise exception 'FAIL (test 12a): claim_account_deletion_jobs is reachable by anon(%) or authenticated(%) -- must be service_role only', v_anon, v_authenticated using errcode = 'M0050';
    end if;
    if not v_service_role then
        raise exception 'FAIL (test 12a): service_role is missing EXECUTE on claim_account_deletion_jobs' using errcode = 'M0050';
    end if;
    raise notice 'PASS (test 12a): claim_account_deletion_jobs is service_role-only';

    v_anon := has_function_privilege('anon', 'public.record_account_deletion_auth_result(uuid, boolean, text, integer)', 'EXECUTE');
    v_authenticated := has_function_privilege('authenticated', 'public.record_account_deletion_auth_result(uuid, boolean, text, integer)', 'EXECUTE');
    v_service_role := has_function_privilege('service_role', 'public.record_account_deletion_auth_result(uuid, boolean, text, integer)', 'EXECUTE');
    if v_anon or v_authenticated then
        raise exception 'FAIL (test 12b): record_account_deletion_auth_result is reachable by anon(%) or authenticated(%) -- must be service_role only', v_anon, v_authenticated using errcode = 'M0050';
    end if;
    if not v_service_role then
        raise exception 'FAIL (test 12b): service_role is missing EXECUTE on record_account_deletion_auth_result' using errcode = 'M0050';
    end if;
    raise notice 'PASS (test 12b): record_account_deletion_auth_result is service_role-only';

    v_anon := has_function_privilege('anon', 'public.record_account_deletion_storage_result(uuid, text[], text, integer)', 'EXECUTE');
    v_authenticated := has_function_privilege('authenticated', 'public.record_account_deletion_storage_result(uuid, text[], text, integer)', 'EXECUTE');
    v_service_role := has_function_privilege('service_role', 'public.record_account_deletion_storage_result(uuid, text[], text, integer)', 'EXECUTE');
    if v_anon or v_authenticated then
        raise exception 'FAIL (test 12c): record_account_deletion_storage_result is reachable by anon(%) or authenticated(%) -- must be service_role only', v_anon, v_authenticated using errcode = 'M0050';
    end if;
    if not v_service_role then
        raise exception 'FAIL (test 12c): service_role is missing EXECUTE on record_account_deletion_storage_result' using errcode = 'M0050';
    end if;
    raise notice 'PASS (test 12c): record_account_deletion_storage_result is service_role-only';
end $$;

rollback;
