-- Migration 0047 test —
-- supabase/tests/migration_0047_account_deletion_jobs.test.sql
--
-- Covers migration 0047_account_deletion_jobs: zero client-readable RLS
-- policies, the updated_at trigger, the state CHECK constraint, the
-- unique index on former_user_id, and — the property this table exists
-- for — that a row SURVIVES deleting the auth.users row its
-- former_user_id names, because that column is deliberately not a
-- foreign key at all.
--
-- STATUS: intended to run against the local disposable Supabase/Docker
-- stack only — NOT executed in the authoring session (no `supabase`
-- CLI, no reachable Docker daemon, no `psql` were available). Depends
-- on migrations 0000-0047 already being applied.
--
-- Fail-closed: every assertion raises via `raise exception ... using
-- errcode = 'M0047'`.

begin;

insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-0000-0000-000000001201', 'm0047-user@example.invalid', '{"username": "m0047_user"}'::jsonb)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- Test 1: former_user_id is genuinely not a foreign key to anything —
-- the entire reason this table can outlive its own subject.
-- ---------------------------------------------------------------------
do $$
begin
    if exists (
        select 1 from pg_constraint
        where conrelid = 'public.account_deletion_jobs'::regclass and contype = 'f'
    ) then
        raise exception 'FAIL (test 1): account_deletion_jobs has a foreign key constraint -- former_user_id must be a plain uuid' using errcode = 'M0047';
    end if;
    raise notice 'PASS (test 1): account_deletion_jobs has zero foreign key constraints';
end $$;

-- ---------------------------------------------------------------------
-- Test 2: RLS enabled, zero policies for any role.
-- ---------------------------------------------------------------------
savepoint test_2;
do $$
begin
    insert into public.account_deletion_jobs (former_user_id, storage_paths)
    values ('00000000-0000-0000-0000-000000001201', array['avatars/00000000-0000-0000-0000-000000001201/512.jpg']);

    perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000001201', true);
    set local role authenticated;

    if exists (select 1 from public.account_deletion_jobs where former_user_id = '00000000-0000-0000-0000-000000001201') then
        raise exception 'FAIL (test 2): an authenticated session could read account_deletion_jobs directly' using errcode = 'M0047';
    end if;
    raise notice 'PASS (test 2): direct client SELECT on account_deletion_jobs returns nothing (RLS enabled, zero policies)';
end $$;
reset role;
rollback to savepoint test_2;

-- ---------------------------------------------------------------------
-- Test 3: state CHECK constraint rejects an unrecognized value.
-- ---------------------------------------------------------------------
savepoint test_3;
do $$
begin
    begin
        insert into public.account_deletion_jobs (former_user_id, state)
        values ('00000000-0000-0000-0000-000000001201', 'not_a_real_state');
        raise exception 'FAIL (test 3): an invalid state value was accepted' using errcode = 'M0047';
    exception when check_violation then
        raise notice 'PASS (test 3): invalid state value correctly rejected by the CHECK constraint';
    end;
end $$;
rollback to savepoint test_3;

-- ---------------------------------------------------------------------
-- Test 4: updated_at trigger fires on UPDATE, and genuinely advances
-- with real wall-clock time -- INCLUDING across a second UPDATE within
-- the SAME transaction (test 4b).
--
-- As of migration 0051_account_deletion_jobs_wall_clock_updated_at.sql,
-- account_deletion_jobs uses its OWN dedicated trigger function
-- (set_account_deletion_jobs_updated_at(), clock_timestamp()-based),
-- not the shared public.set_updated_at() every other updated_at column
-- in this codebase still uses (that one is transaction_timestamp()-
-- based -- see 0051's own header for why that matters and why the fix
-- was scoped to this table only, plus the review finding that produced
-- it: real local testing caught this test failing exactly because
-- public.set_updated_at()'s now() does not advance within one
-- transaction, no matter how much real time -- including a genuine
-- pg_sleep() -- passes in between).
-- ---------------------------------------------------------------------
savepoint test_4;
do $$
declare
    v_before timestamptz;
    v_after timestamptz;
    v_after_2 timestamptz;
begin
    insert into public.account_deletion_jobs (former_user_id)
    values ('00000000-0000-0000-0000-000000001201');

    select updated_at into v_before from public.account_deletion_jobs where former_user_id = '00000000-0000-0000-0000-000000001201';

    perform pg_sleep(0.01);

    update public.account_deletion_jobs set state = 'auth_deleted' where former_user_id = '00000000-0000-0000-0000-000000001201';

    select updated_at into v_after from public.account_deletion_jobs where former_user_id = '00000000-0000-0000-0000-000000001201';

    if v_after <= v_before then
        raise exception 'FAIL (test 4a): updated_at did not advance on UPDATE (before=%, after=%)', v_before, v_after using errcode = 'M0047';
    end if;
    raise notice 'PASS (test 4a): updated_at advances on UPDATE via the dedicated set_account_deletion_jobs_updated_at() trigger (0051)';

    -- Test 4b: a SECOND update, still inside this same top-level
    -- transaction (this whole file runs as one begin/rollback, and
    -- neither update above opened or closed a transaction of its own)
    -- -- this is the exact scenario 0051's own header documents as the
    -- real reason this table needed a wall-clock guarantee: this PR's
    -- own record_account_deletion_auth_result()/
    -- record_account_deletion_storage_result() (0050) can each perform
    -- two sequential UPDATEs against the same job row within one call.
    perform pg_sleep(0.01);

    update public.account_deletion_jobs set state = 'storage_cleaned' where former_user_id = '00000000-0000-0000-0000-000000001201';

    select updated_at into v_after_2 from public.account_deletion_jobs where former_user_id = '00000000-0000-0000-0000-000000001201';

    if v_after_2 <= v_after then
        raise exception 'FAIL (test 4b): updated_at did not advance on a SECOND UPDATE within the same transaction (after=%, after_2=%) -- this is exactly the multi-write-per-transaction guarantee 0051 exists to provide', v_after, v_after_2 using errcode = 'M0047';
    end if;
    raise notice 'PASS (test 4b): updated_at genuinely advances across a second UPDATE within the same transaction, not just across separate transactions';
end $$;
rollback to savepoint test_4;

-- ---------------------------------------------------------------------
-- Test 5: unique index on former_user_id.
-- ---------------------------------------------------------------------
savepoint test_5;
do $$
begin
    insert into public.account_deletion_jobs (former_user_id) values ('00000000-0000-0000-0000-000000001201');

    begin
        insert into public.account_deletion_jobs (former_user_id) values ('00000000-0000-0000-0000-000000001201');
        raise exception 'FAIL (test 5): a second row for the same former_user_id was accepted' using errcode = 'M0047';
    exception when unique_violation then
        raise notice 'PASS (test 5): unique index on former_user_id correctly rejects a duplicate';
    end;
end $$;
rollback to savepoint test_5;

-- ---------------------------------------------------------------------
-- Test 6: the row SURVIVES deleting the auth.users row it names — the
-- entire point of this table.
-- ---------------------------------------------------------------------
do $$
begin
    insert into public.account_deletion_jobs (former_user_id, state, storage_paths)
    values ('00000000-0000-0000-0000-000000001201', 'auth_deleted', array['avatars/00000000-0000-0000-0000-000000001201/512.jpg']);

    delete from auth.users where id = '00000000-0000-0000-0000-000000001201';

    if not exists (select 1 from public.account_deletion_jobs where former_user_id = '00000000-0000-0000-0000-000000001201') then
        raise exception 'FAIL (test 6): the job row was deleted along with auth.users -- it must survive' using errcode = 'M0047';
    end if;
    raise notice 'PASS (test 6): the job row survives deleting the auth.users row it names';

    if (select state from public.account_deletion_jobs where former_user_id = '00000000-0000-0000-0000-000000001201') <> 'auth_deleted' then
        raise exception 'FAIL (test 6b): the surviving row''s state was altered' using errcode = 'M0047';
    end if;
    raise notice 'PASS (test 6b): the surviving row''s own data is untouched';
end $$;

rollback;
