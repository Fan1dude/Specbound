-- Migration 0044 test — fresh install —
-- supabase/tests/migration_0044_fresh_install.test.sql
--
-- Verifies 0044_normalize_user_deletion_fks converges the reconstructed-
-- baseline shape (0000_baseline_pre_tracked_tables.sql's ON DELETE
-- CASCADE on profiles.id/builds.user_id/build_revisions.user_id) to the
-- production-confirmed target: no FK on profiles.id or builds.user_id,
-- build_revisions.user_id present but NO ACTION. Also confirms
-- build_revisions.build_id (CASCADE) and profiles.featured_build_id
-- (SET NULL) are left untouched, since both sources already agree on
-- those.
--
-- Run:
--   1. npx supabase db reset --local (applies 0000-latest, including 0044)
--   2. docker exec -i <local-db-container> psql -U postgres -d postgres \
--          -v ON_ERROR_STOP=1 -f - < supabase/tests/migration_0044_fresh_install.test.sql
--
-- STATUS: intended to run against the local disposable Supabase/Docker
-- stack only — NOT executed in the authoring session (no `supabase`
-- CLI, no reachable Docker daemon, no `psql` were available; see this
-- PR's own report for the exact environmental limitation). Depends on
-- migrations 0000-0044 already being applied.
--
-- Fail-closed: every assertion raises via `raise exception ... using
-- errcode = 'M0044'`.

begin;

do $$
declare
    v_profiles_fk_count integer;
    v_builds_fk_count integer;
    v_revisions_confdeltype "char";
    v_revisions_fk_count integer;
begin
    select count(*) into v_profiles_fk_count
    from pg_constraint
    where conrelid = 'public.profiles'::regclass
      and contype = 'f'
      and confrelid = 'auth.users'::regclass;

    if v_profiles_fk_count <> 0 then
        raise exception 'FAIL (test 1): profiles still has % FK(s) to auth.users after 0044', v_profiles_fk_count using errcode = 'M0044';
    end if;
    raise notice 'PASS (test 1): profiles has no FK to auth.users';

    select count(*) into v_builds_fk_count
    from pg_constraint
    where conrelid = 'public.builds'::regclass
      and contype = 'f'
      and confrelid = 'auth.users'::regclass;

    if v_builds_fk_count <> 0 then
        raise exception 'FAIL (test 2): builds still has % FK(s) to auth.users after 0044', v_builds_fk_count using errcode = 'M0044';
    end if;
    raise notice 'PASS (test 2): builds has no FK to auth.users';

    select count(*), max(confdeltype) into v_revisions_fk_count, v_revisions_confdeltype
    from pg_constraint
    where conrelid = 'public.build_revisions'::regclass
      and contype = 'f'
      and confrelid = 'auth.users'::regclass;

    if v_revisions_fk_count <> 1 then
        raise exception 'FAIL (test 3a): build_revisions has % FK(s) to auth.users, expected exactly 1', v_revisions_fk_count using errcode = 'M0044';
    end if;
    if v_revisions_confdeltype <> 'a' then
        raise exception 'FAIL (test 3b): build_revisions -> auth.users confdeltype is % (expected ''a'' / NO ACTION)', v_revisions_confdeltype using errcode = 'M0044';
    end if;
    raise notice 'PASS (test 3): build_revisions -> auth.users FK exists with NO ACTION';

    -- Untouched, per this migration's explicit scope.
    if not exists (
        select 1 from pg_constraint
        where conrelid = 'public.build_revisions'::regclass
          and contype = 'f'
          and confrelid = 'public.builds'::regclass
          and confdeltype = 'c'
    ) then
        raise exception 'FAIL (test 4): build_revisions.build_id -> builds CASCADE FK is missing or altered' using errcode = 'M0044';
    end if;
    raise notice 'PASS (test 4): build_revisions.build_id -> builds ON DELETE CASCADE untouched';

    if not exists (
        select 1 from pg_constraint
        where conrelid = 'public.profiles'::regclass
          and contype = 'f'
          and confrelid = 'public.builds'::regclass
          and confdeltype = 'n'
    ) then
        raise exception 'FAIL (test 5): profiles.featured_build_id -> builds SET NULL FK is missing or altered' using errcode = 'M0044';
    end if;
    raise notice 'PASS (test 5): profiles.featured_build_id -> builds ON DELETE SET NULL untouched';
end $$;

rollback;
