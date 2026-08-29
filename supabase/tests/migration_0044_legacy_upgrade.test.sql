-- Migration 0044 test — production-shaped legacy upgrade —
-- supabase/tests/migration_0044_legacy_upgrade.test.sql
--
-- Verifies 0044_normalize_user_deletion_fks is a correct no-op when
-- applied against a database that ALREADY has production's real shape
-- (no FK on profiles.id/builds.user_id, build_revisions.user_id present
-- with NO ACTION under a historically-different constraint name) —
-- proving 0044 converges correctly starting from EITHER possible shape,
-- not only the reconstructed baseline's.
--
-- Run:
--   1. npx supabase db reset --local --no-seed --version 0043
--   2. docker exec -i <local-db-container> psql -U postgres -d postgres \
--          -v ON_ERROR_STOP=1 -f - < supabase/tests/fixtures/production_shaped_user_deletion_fks_fixture.sql
--   3. npx supabase migration up --local   (applies 0044 on top of the
--      now-production-shaped database)
--   4. docker exec -i <local-db-container> psql -U postgres -d postgres \
--          -v ON_ERROR_STOP=1 -f - < supabase/tests/migration_0044_legacy_upgrade.test.sql
--
-- STATUS: intended to run against the local disposable Supabase/Docker
-- stack only — NOT executed in the authoring session (same disclosed
-- environmental limitation as migration_0044_fresh_install.test.sql).
--
-- Fail-closed: every assertion raises via `raise exception ... using
-- errcode = 'M0044L'`.

begin;

do $$
declare
    v_profiles_fk_count integer;
    v_builds_fk_count integer;
    v_revisions_conname text;
    v_revisions_confdeltype "char";
    v_revisions_fk_count integer;
begin
    select count(*) into v_profiles_fk_count
    from pg_constraint
    where conrelid = 'public.profiles'::regclass
      and contype = 'f'
      and confrelid = 'auth.users'::regclass;

    if v_profiles_fk_count <> 0 then
        raise exception 'FAIL (test 1): profiles still has % FK(s) to auth.users after 0044 on a legacy-shaped database', v_profiles_fk_count using errcode = 'M0044L';
    end if;
    raise notice 'PASS (test 1): profiles has no FK to auth.users (unchanged from the fixture, correctly left alone)';

    select count(*) into v_builds_fk_count
    from pg_constraint
    where conrelid = 'public.builds'::regclass
      and contype = 'f'
      and confrelid = 'auth.users'::regclass;

    if v_builds_fk_count <> 0 then
        raise exception 'FAIL (test 2): builds still has % FK(s) to auth.users after 0044 on a legacy-shaped database', v_builds_fk_count using errcode = 'M0044L';
    end if;
    raise notice 'PASS (test 2): builds has no FK to auth.users (unchanged from the fixture, correctly left alone)';

    select conname, confdeltype, count(*) over ()
    into v_revisions_conname, v_revisions_confdeltype, v_revisions_fk_count
    from pg_constraint
    where conrelid = 'public.build_revisions'::regclass
      and contype = 'f'
      and confrelid = 'auth.users'::regclass;

    if v_revisions_fk_count <> 1 then
        raise exception 'FAIL (test 3a): build_revisions has % FK(s) to auth.users, expected exactly 1', v_revisions_fk_count using errcode = 'M0044L';
    end if;
    if v_revisions_confdeltype <> 'a' then
        raise exception 'FAIL (test 3b): build_revisions -> auth.users confdeltype is % (expected ''a'' / NO ACTION)', v_revisions_confdeltype using errcode = 'M0044L';
    end if;
    raise notice 'PASS (test 3): build_revisions -> auth.users FK still exists with NO ACTION (constraint name: %) — 0044 correctly found and normalized the fixture''s historically-named constraint by inspecting confrelid, not by assuming a specific name', v_revisions_conname;
end $$;

rollback;
