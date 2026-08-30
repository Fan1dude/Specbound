-- Migration 0051 test —
-- supabase/tests/migration_0051_account_deletion_jobs_wall_clock_updated_at.test.sql
--
-- Covers migration 0051_account_deletion_jobs_wall_clock_updated_at:
-- that account_deletion_jobs' trigger now points at the dedicated
-- set_account_deletion_jobs_updated_at() function (not the shared
-- public.set_updated_at()), that this function is clock_timestamp()-
-- based (advances even within one transaction — the actual bug real
-- local testing found; see migration_0047_account_deletion_jobs.test.sql's
-- own test 4a/4b for the direct multi-write-in-one-transaction proof,
-- not duplicated here), and that public.set_updated_at() itself was
-- left completely untouched (every OTHER table's trigger is unaffected).
--
-- STATUS: intended to run against the local disposable Supabase/Docker
-- stack only — NOT executed in the authoring session (no `supabase`
-- CLI, no reachable Docker daemon, no `psql` were available; see this
-- PR's own report for the exact environmental limitation). Depends on
-- migrations 0000-0051 already being applied.
--
-- Fail-closed: every assertion raises via `raise exception ... using
-- errcode = 'M0051'`.

begin;

-- ---------------------------------------------------------------------
-- Test 1: account_deletion_jobs' own trigger now calls the dedicated
-- function, not the shared public.set_updated_at().
-- ---------------------------------------------------------------------
do $$
declare
    v_trigger_function text;
begin
    select p.proname
    into v_trigger_function
    from pg_trigger t
    join pg_proc p on p.oid = t.tgfoid
    where t.tgrelid = 'public.account_deletion_jobs'::regclass
      and t.tgname = 'account_deletion_jobs_set_updated_at'
      and not t.tgisinternal;

    if v_trigger_function is distinct from 'set_account_deletion_jobs_updated_at' then
        raise exception 'FAIL (test 1): account_deletion_jobs_set_updated_at trigger calls %, expected set_account_deletion_jobs_updated_at', v_trigger_function using errcode = 'M0051';
    end if;
    raise notice 'PASS (test 1): the trigger now calls the dedicated set_account_deletion_jobs_updated_at() function';
end $$;

-- ---------------------------------------------------------------------
-- Test 2: the dedicated function is genuinely clock_timestamp()-based —
-- confirmed by inspecting the function's own source, not just its
-- behavior (behavior is proven directly, with real elapsed time, in
-- migration_0047_account_deletion_jobs.test.sql's test 4b).
-- ---------------------------------------------------------------------
do $$
declare
    v_source text;
begin
    select prosrc into v_source
    from pg_proc
    where pronamespace = 'public'::regnamespace
      and proname = 'set_account_deletion_jobs_updated_at';

    if v_source is null then
        raise exception 'FAIL (test 2): set_account_deletion_jobs_updated_at() does not exist' using errcode = 'M0051';
    end if;
    if v_source not like '%clock_timestamp()%' then
        raise exception 'FAIL (test 2): set_account_deletion_jobs_updated_at() does not reference clock_timestamp() -- got: %', v_source using errcode = 'M0051';
    end if;
    raise notice 'PASS (test 2): set_account_deletion_jobs_updated_at() uses clock_timestamp(), not now()/transaction_timestamp()';
end $$;

-- ---------------------------------------------------------------------
-- Test 3: public.set_updated_at() (the shared trigger, 0001) is
-- completely untouched by this migration -- still now()-based, still
-- attached to every OTHER table's own trigger unaffected. Spot-checks
-- one other table (project_drafts, 0001 itself) to prove this migration
-- did not accidentally touch the shared function or its other callers.
-- ---------------------------------------------------------------------
do $$
declare
    v_source text;
    v_other_trigger_function text;
begin
    select prosrc into v_source
    from pg_proc
    where pronamespace = 'public'::regnamespace
      and proname = 'set_updated_at';

    if v_source is null or v_source not like '%now()%' then
        raise exception 'FAIL (test 3a): public.set_updated_at() is missing or was changed away from now() -- this migration must not touch it' using errcode = 'M0051';
    end if;
    raise notice 'PASS (test 3a): public.set_updated_at() is unchanged (still now()-based)';

    select p.proname
    into v_other_trigger_function
    from pg_trigger t
    join pg_proc p on p.oid = t.tgfoid
    where t.tgrelid = 'public.project_drafts'::regclass
      and t.tgname = 'set_project_drafts_updated_at'
      and not t.tgisinternal;

    if v_other_trigger_function is distinct from 'set_updated_at' then
        raise exception 'FAIL (test 3b): project_drafts'' own trigger was unexpectedly changed to %', v_other_trigger_function using errcode = 'M0051';
    end if;
    raise notice 'PASS (test 3b): an unrelated table (project_drafts) still uses the shared public.set_updated_at() trigger, unaffected by this migration';
end $$;

-- ---------------------------------------------------------------------
-- Test 4: ACL -- EXECUTE revoked from public on the new dedicated
-- function (matching public.set_updated_at()'s own posture,
-- 0016_security_definer_hygiene.sql). Trigger firing itself is governed
-- by table-level privileges, not this grant -- see 0051's own header.
-- ---------------------------------------------------------------------
do $$
declare
    v_authenticated_exec boolean;
begin
    v_authenticated_exec := has_function_privilege('authenticated', 'public.set_account_deletion_jobs_updated_at()', 'EXECUTE');
    if v_authenticated_exec then
        raise exception 'FAIL (test 4): authenticated unexpectedly has direct EXECUTE on set_account_deletion_jobs_updated_at()' using errcode = 'M0051';
    end if;
    raise notice 'PASS (test 4): EXECUTE is not directly grantable to authenticated on the dedicated trigger function';
end $$;

rollback;
