-- Migration 0034 test —
-- supabase/tests/migration_0034_guidelines_accepted_version.test.sql
--
-- Covers migration 0034 (profile_guidelines_accepted_version): proves
-- the new nullable public.profiles.guidelines_accepted_version column
-- exists with the intended type/constraint, that a pre-existing row
-- with a non-null guidelines_accepted_at (simulating a user who
-- accepted the earlier draft Guidelines page) is left with
-- guidelines_accepted_version = null after the migration — deliberately
-- NO backfill, unlike 0025's onboarding_welcomed_at backfill — that an
-- owner can still write the new column through the same pre-existing
-- "Users can update their own profile" RLS policy (0000) with no new
-- grant/policy needed, that the CHECK constraint accepts null and
-- well-formed YYYY-MM-DD values but rejects malformed ones, and that
-- the paired rollback drops the column cleanly while leaving
-- guidelines_accepted_at untouched.
--
-- STATUS: intended to run against the local disposable Supabase/Docker
-- stack only (`supabase db reset --local`) — never against a linked or
-- production project. Same fixture-safety posture as every other file
-- in this directory: fake auth.users rows, namespaced usernames, a
-- single outer transaction that ends in ROLLBACK, each test in its own
-- SAVEPOINT. Depends on migrations 0000-0034 already being applied.
--
-- Fail-closed design: every assertion raises a real PostgreSQL ERROR on
-- failure (via `raise exception ... using errcode = 'M0034'`), matching
-- migration_0033_function_execute_permissions.test.sql's convention —
-- `psql -v ON_ERROR_STOP=1` only stops on an actual ERROR, never a mere
-- WARNING/NOTICE.

begin;

insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-0000-0000-000000000501', 'm0034-user@example.invalid', '{"username": "m0034_user_test"}'::jsonb),
    ('00000000-0000-0000-0000-000000000502', 'm0034-other@example.invalid', '{"username": "m0034_other_test"}'::jsonb)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- Test 1: the column exists, is nullable, and is text-typed.
-- ---------------------------------------------------------------------
savepoint test_1;
do $$
declare
    v_is_nullable text;
    v_data_type text;
begin
    select is_nullable, data_type
    into v_is_nullable, v_data_type
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'profiles'
      and column_name = 'guidelines_accepted_version';

    if v_data_type is null then
        raise exception 'FAIL (test 1a): public.profiles.guidelines_accepted_version does not exist' using errcode = 'M0034';
    end if;

    if v_is_nullable <> 'YES' then
        raise exception 'FAIL (test 1b): guidelines_accepted_version is NOT NULL, expected nullable' using errcode = 'M0034';
    end if;

    if v_data_type <> 'text' then
        raise exception 'FAIL (test 1c): guidelines_accepted_version is type % , expected text', v_data_type using errcode = 'M0034';
    end if;

    raise notice 'PASS (test 1): guidelines_accepted_version exists, nullable, text-typed';
end $$;
rollback to savepoint test_1;

-- ---------------------------------------------------------------------
-- Test 2: no backfill — a pre-existing row with a non-null
-- guidelines_accepted_at (simulating draft-page acceptance) has
-- guidelines_accepted_version = null immediately after the column is
-- added, and guidelines_accepted_at itself is left untouched.
-- ---------------------------------------------------------------------
savepoint test_2;
do $$
declare
    v_version text;
    v_accepted_at timestamptz;
begin
    update public.profiles
        set guidelines_accepted_at = now() - interval '30 days'
        where id = '00000000-0000-0000-0000-000000000501';

    select guidelines_accepted_version, guidelines_accepted_at
    into v_version, v_accepted_at
    from public.profiles
    where id = '00000000-0000-0000-0000-000000000501';

    if v_version is not null then
        raise exception 'FAIL (test 2a): a row with a pre-existing guidelines_accepted_at unexpectedly has a non-null guidelines_accepted_version (%)', v_version using errcode = 'M0034';
    end if;

    if v_accepted_at is null then
        raise exception 'FAIL (test 2b): guidelines_accepted_at was unexpectedly cleared' using errcode = 'M0034';
    end if;

    raise notice 'PASS (test 2): draft-era guidelines_accepted_at survives with guidelines_accepted_version left null (no backfill)';
end $$;
rollback to savepoint test_2;

-- ---------------------------------------------------------------------
-- Test 3: an authenticated owner can write their own
-- guidelines_accepted_version through the existing "Users can update
-- their own profile" RLS policy — no new grant/policy needed. A
-- different authenticated user cannot write it on someone else's row.
-- ---------------------------------------------------------------------
savepoint test_3;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000501', true);
set local role authenticated;
do $$
declare
    v_version text;
begin
    update public.profiles
        set guidelines_accepted_at = now(), guidelines_accepted_version = '2026-08-11'
        where id = '00000000-0000-0000-0000-000000000501';

    select guidelines_accepted_version into v_version
    from public.profiles
    where id = '00000000-0000-0000-0000-000000000501';

    if v_version is distinct from '2026-08-11' then
        raise exception 'FAIL (test 3a): owner update of guidelines_accepted_version did not persist (got %)', v_version using errcode = 'M0034';
    end if;

    raise notice 'PASS (test 3a): an authenticated owner can write their own guidelines_accepted_version via the existing RLS policy';
end $$;
reset role;
rollback to savepoint test_3;

savepoint test_3_other;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000502', true);
set local role authenticated;
do $$
declare
    v_updated_rows int;
begin
    update public.profiles
        set guidelines_accepted_version = '2026-08-11'
        where id = '00000000-0000-0000-0000-000000000501';
    get diagnostics v_updated_rows = row_count;

    if v_updated_rows <> 0 then
        raise exception 'FAIL (test 3b): a different authenticated user updated guidelines_accepted_version on someone else''s profile (% rows)', v_updated_rows using errcode = 'M0034';
    end if;

    raise notice 'PASS (test 3b): a different authenticated user cannot write guidelines_accepted_version on another profile (RLS still owner-scoped)';
end $$;
reset role;
rollback to savepoint test_3_other;

-- ---------------------------------------------------------------------
-- Test 4: CHECK constraint — null and well-formed YYYY-MM-DD values are
-- accepted; malformed values are rejected.
-- ---------------------------------------------------------------------
savepoint test_4;
do $$
begin
    update public.profiles set guidelines_accepted_version = null where id = '00000000-0000-0000-0000-000000000501';
    update public.profiles set guidelines_accepted_version = '2026-08-11' where id = '00000000-0000-0000-0000-000000000501';
    raise notice 'PASS (test 4a): null and a well-formed YYYY-MM-DD value are both accepted';
exception when check_violation then
    raise exception 'FAIL (test 4a): a valid value (null or YYYY-MM-DD) was unexpectedly rejected by the CHECK constraint' using errcode = 'M0034';
end $$;
rollback to savepoint test_4;

savepoint test_5;
do $$
begin
    begin
        update public.profiles set guidelines_accepted_version = 'not-a-version' where id = '00000000-0000-0000-0000-000000000501';
        raise exception 'FAIL (test 5): a malformed guidelines_accepted_version value was accepted by the CHECK constraint' using errcode = 'M0034';
    exception when check_violation then
        raise notice 'PASS (test 5): a malformed guidelines_accepted_version value is rejected by the CHECK constraint';
    end;
end $$;
rollback to savepoint test_5;

-- ---------------------------------------------------------------------
-- Test 6: rollback behavior — dropping the column via the paired
-- rollback file's own statement removes it cleanly and does not touch
-- guidelines_accepted_at. Run inside its own savepoint so the dropped
-- column doesn't affect any later test in this file.
-- ---------------------------------------------------------------------
savepoint test_6;
do $$
begin
    update public.profiles
        set guidelines_accepted_at = now(), guidelines_accepted_version = '2026-08-11'
        where id = '00000000-0000-0000-0000-000000000501';
end $$;

alter table public.profiles drop column if exists guidelines_accepted_version;

do $$
declare
    v_column_exists boolean;
    v_accepted_at timestamptz;
begin
    select exists (
        select 1 from information_schema.columns
        where table_schema = 'public' and table_name = 'profiles' and column_name = 'guidelines_accepted_version'
    ) into v_column_exists;

    if v_column_exists then
        raise exception 'FAIL (test 6a): guidelines_accepted_version still exists after the rollback statement ran' using errcode = 'M0034';
    end if;

    select guidelines_accepted_at into v_accepted_at
    from public.profiles where id = '00000000-0000-0000-0000-000000000501';

    if v_accepted_at is null then
        raise exception 'FAIL (test 6b): guidelines_accepted_at was unexpectedly dropped/cleared by the rollback' using errcode = 'M0034';
    end if;

    raise notice 'PASS (test 6): rollback drops guidelines_accepted_version cleanly and leaves guidelines_accepted_at untouched';
end $$;
rollback to savepoint test_6;

rollback;
