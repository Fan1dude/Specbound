-- Legacy-upgrade migration test —
-- supabase/tests/migration_0042_legacy_upgrade.test.sql
--
-- Verifies that migration 0042, applied on top of production-shaped
-- legacy data (supabase/tests/fixtures/legacy_build_status_fixture.sql),
-- performs the real, evidence-based current-state backfill described in
-- 0042's own header — never rewriting a single historical
-- build_revisions.progress value, reconciling a Completed build's
-- CURRENT progress to 100 without touching its historical 99, mirroring
-- each other build's own latest revision progress (including a
-- no-revision build correctly landing at 0), normalizing the one
-- documented legacy status alias, and backfilling linked drafts from
-- their already-reconciled build — all against build_revisions.progress
-- narrowed to `smallint` (the fixture's own final step), matching
-- production's real column type, not the `integer` the reconstructed
-- baseline claims.
--
-- Scenario 1 — normalization + backfill, expected to succeed:
--
--   1. Reset local db to exactly 0000-0041 (the pre-0042 foundation):
--        npx supabase db reset --local --no-seed --version 0041
--
--   2. Inject the legacy fixture (5 builds, 6 revisions across a real
--      spread of historical progress values, 3 drafts, and a final
--      ALTER narrowing build_revisions.progress to smallint) — run
--      BEFORE 0042 exists to normalize/backfill/constrain anything:
--        docker exec -i <local-db-container> psql -U postgres -d postgres \
--            -v ON_ERROR_STOP=1 -f - < supabase/tests/fixtures/legacy_build_status_fixture.sql
--
--   3. Apply the one remaining pending migration (0042) WITHOUT wiping
--      the fixture data just inserted:
--        npx supabase migration up --local
--
--   4. Run this file's Scenario 1 assertions (below) against the result:
--        docker exec -i <local-db-container> psql -U postgres -d postgres \
--            -v ON_ERROR_STOP=1 -f - < supabase/tests/migration_0042_legacy_upgrade.test.sql
--
-- Scenario 2 — an unrelated unexpected value aborts the migration,
-- expected to FAIL — run entirely separately from Scenario 1, since a
-- failed migration leaves the database in a state nothing else in this
-- file should build on:
--
--   1. npx supabase db reset --local --no-seed --version 0041
--   2. Manually insert one more builds row with status = 'archived' (or
--      any value outside planning/in_progress/paused/completed/building)
--      using the same shape as legacy_build_status_fixture.sql's own
--      INSERT statements.
--   3. npx supabase migration up --local
--   4. Expected result: the command FAILS, printing migration 0042's own
--      RAISE EXCEPTION message ("... hold unexpected value(s) [archived]
--      ..."), and `npx supabase migration list --local` still shows 0042
--      as NOT applied, with zero partial schema change (no new column
--      exists on any of the three tables). This is the desired outcome —
--      confirms "fail migration verification clearly rather than
--      silently rewriting unknown values" holds, not a test bug.
--
-- STATUS: intended to run against the local disposable Supabase/Docker
-- stack only — never against a linked or production project.
--
-- Fail-closed design: every assertion raises a real PostgreSQL ERROR on
-- failure (via `raise exception ... using errcode = 'M0042L'`), matching
-- every other file in this directory's convention.

begin;

-- ---------------------------------------------------------------------
-- Test 1: historical build_revisions.progress is byte/value-identical
-- for every fixture revision — 0042 never rewrites a single one.
-- ---------------------------------------------------------------------
savepoint test_1;
do $$
declare
    v_mismatch_count integer;
begin
    select count(*) into v_mismatch_count
    from (values
        ('00000000-0000-0000-0000-0000000000e1'::uuid, 50),
        ('00000000-0000-0000-0000-0000000000e2'::uuid, 0),
        ('00000000-0000-0000-0000-0000000000e3'::uuid, 58),
        ('00000000-0000-0000-0000-0000000000e4'::uuid, 51),
        ('00000000-0000-0000-0000-0000000000e5'::uuid, 75),
        ('00000000-0000-0000-0000-0000000000e6'::uuid, 99)
    ) as expected(revision_id, expected_progress)
    join public.build_revisions br on br.id = expected.revision_id
    where br.progress <> expected.expected_progress;

    if v_mismatch_count > 0 then
        raise exception 'FAIL (test 1): % historical build_revisions.progress value(s) were altered by migration 0042 -- history must never be rewritten', v_mismatch_count using errcode = 'M0042L';
    end if;

    raise notice 'PASS (test 1): all 6 historical build_revisions.progress values (0, 50, 51, 58, 75, 99) are byte/value-identical after migration';
end $$;
rollback to savepoint test_1;

-- ---------------------------------------------------------------------
-- Test 2: the Completed build's historical latest revision stays 99;
-- its CURRENT builds.progress becomes exactly 100.
-- ---------------------------------------------------------------------
savepoint test_2;
do $$
declare
    v_revision_progress integer;
    v_build_progress integer;
    v_build_status text;
begin
    select progress into v_revision_progress
    from public.build_revisions where id = '00000000-0000-0000-0000-0000000000e6';

    if v_revision_progress <> 99 then
        raise exception 'FAIL (test 2a): the Completed build''s historical revision progress changed (got %, expected 99)', v_revision_progress using errcode = 'M0042L';
    end if;

    select progress, status into v_build_progress, v_build_status
    from public.builds where id = '00000000-0000-0000-0000-0000000000c1';

    if v_build_status <> 'completed' or v_build_progress <> 100 then
        raise exception 'FAIL (test 2b): the Completed build did not reconcile to progress=100 (got status=%, progress=%)', v_build_status, v_build_progress using errcode = 'M0042L';
    end if;

    raise notice 'PASS (test 2): the Completed build''s historical revision stays 99; its current builds.progress reconciles to exactly 100';
end $$;
rollback to savepoint test_2;

-- ---------------------------------------------------------------------
-- Test 3: the Completed build's linked draft becomes completed/100,
-- copied from the already-reconciled builds row (never 99).
-- ---------------------------------------------------------------------
savepoint test_3;
do $$
declare
    v_draft_progress integer;
    v_draft_status text;
begin
    select progress, status into v_draft_progress, v_draft_status
    from public.project_drafts where id = '00000000-0000-0000-0000-0000000000d1';

    if v_draft_status <> 'completed' or v_draft_progress <> 100 then
        raise exception 'FAIL (test 3): the Completed build''s linked draft is status=%, progress=% -- expected completed/100', v_draft_status, v_draft_progress using errcode = 'M0042L';
    end if;

    raise notice 'PASS (test 3): the Completed build''s linked draft correctly backfills to completed/100';
end $$;
rollback to savepoint test_3;

-- ---------------------------------------------------------------------
-- Test 4: the legacy 'building' build normalizes to 'in_progress', with
-- its current progress mirroring its own latest revision (75, not 51).
-- ---------------------------------------------------------------------
savepoint test_4;
do $$
declare
    v_status text;
    v_progress integer;
begin
    select status, progress into v_status, v_progress
    from public.builds where id = '00000000-0000-0000-0000-0000000000b1';

    if v_status <> 'in_progress' then
        raise exception 'FAIL (test 4a): the legacy ''building'' build did not normalize to ''in_progress'' (got %)', v_status using errcode = 'M0042L';
    end if;

    if v_progress <> 75 then
        raise exception 'FAIL (test 4b): the normalized build''s current progress is % -- expected 75 (its own latest revision, not the earlier 51)', v_progress using errcode = 'M0042L';
    end if;

    raise notice 'PASS (test 4): the legacy ''building'' build normalizes to in_progress with its current progress correctly mirroring its own latest revision (75)';
end $$;
rollback to savepoint test_4;

-- Its linked draft mirrors the same reconciled values.
savepoint test_4b;
do $$
declare
    v_status text;
    v_progress integer;
begin
    select status, progress into v_status, v_progress
    from public.project_drafts where id = '00000000-0000-0000-0000-0000000000d2';

    if v_status <> 'in_progress' or v_progress <> 75 then
        raise exception 'FAIL (test 4b): the building build''s linked draft is status=%, progress=% -- expected in_progress/75', v_status, v_progress using errcode = 'M0042L';
    end if;

    raise notice 'PASS (test 4b): the building build''s linked draft correctly backfills to in_progress/75';
end $$;
rollback to savepoint test_4b;

-- ---------------------------------------------------------------------
-- Test 5: planning builds mirror their own latest historical progress,
-- never forced to 0 just because they're not Completed -- including the
-- deterministic-ordering case (two revisions, newest wins: 58 not 0).
-- ---------------------------------------------------------------------
savepoint test_5;
do $$
declare
    v_progress_one_revision integer;
    v_progress_two_revisions integer;
begin
    select progress into v_progress_one_revision
    from public.builds where id = '00000000-0000-0000-0000-0000000000a2';

    if v_progress_one_revision <> 50 then
        raise exception 'FAIL (test 5a): planning build with one revision (progress=50) backfilled to % instead', v_progress_one_revision using errcode = 'M0042L';
    end if;

    select progress into v_progress_two_revisions
    from public.builds where id = '00000000-0000-0000-0000-0000000000a3';

    if v_progress_two_revisions <> 58 then
        raise exception 'FAIL (test 5b): planning build with two revisions (0 then 58) backfilled to % instead of the latest (58) -- deterministic ordering broke', v_progress_two_revisions using errcode = 'M0042L';
    end if;

    raise notice 'PASS (test 5): planning builds correctly mirror their own latest historical progress (50, and 58 not the earlier 0)';
end $$;
rollback to savepoint test_5;

-- ---------------------------------------------------------------------
-- Test 6: a build with zero revisions backfills to progress 0 -- the
-- only case where 0 is actually correct, not merely a default.
-- ---------------------------------------------------------------------
savepoint test_6;
do $$
declare
    v_progress integer;
begin
    select progress into v_progress
    from public.builds where id = '00000000-0000-0000-0000-0000000000a1';

    if v_progress <> 0 then
        raise exception 'FAIL (test 6): a build with no revisions backfilled to % instead of 0', v_progress using errcode = 'M0042L';
    end if;

    raise notice 'PASS (test 6): a build with zero revisions correctly backfills to progress 0';
end $$;
rollback to savepoint test_6;

-- ---------------------------------------------------------------------
-- Test 7: existing revisions receive status NULL, not a fabricated
-- 'planning' — "not recorded" is a distinct, honest state.
-- ---------------------------------------------------------------------
savepoint test_7;
do $$
declare
    v_non_null_count integer;
begin
    select count(*) into v_non_null_count
    from public.build_revisions
    where id in (
        '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000e2',
        '00000000-0000-0000-0000-0000000000e3', '00000000-0000-0000-0000-0000000000e4',
        '00000000-0000-0000-0000-0000000000e5', '00000000-0000-0000-0000-0000000000e6'
    )
    and status is not null;

    if v_non_null_count > 0 then
        raise exception 'FAIL (test 7): % pre-existing revision(s) got a non-null status invented for them -- expected all 6 to remain NULL', v_non_null_count using errcode = 'M0042L';
    end if;

    raise notice 'PASS (test 7): all 6 pre-existing revisions correctly remain status = NULL ("not recorded"), none fabricated as planning';
end $$;
rollback to savepoint test_7;

-- ---------------------------------------------------------------------
-- Test 8: the standalone (never-published) draft defaults to
-- planning/0, never inventing a value from an unrelated build.
-- ---------------------------------------------------------------------
savepoint test_8;
do $$
declare
    v_status text;
    v_progress integer;
begin
    select status, progress into v_status, v_progress
    from public.project_drafts where id = '00000000-0000-0000-0000-0000000000d3';

    if v_status <> 'planning' or v_progress <> 0 then
        raise exception 'FAIL (test 8): the standalone draft is status=%, progress=% -- expected the safe default planning/0', v_status, v_progress using errcode = 'M0042L';
    end if;

    raise notice 'PASS (test 8): the standalone (never-published) draft correctly defaults to planning/0';
end $$;
rollback to savepoint test_8;

-- ---------------------------------------------------------------------
-- Test 9: every 0042 constraint holds against the fully-migrated legacy
-- data (re-confirms the migration's own ALTER TABLE ... ADD CONSTRAINT
-- statements actually succeeded against this real-shaped data, not just
-- that the migration command exited 0).
-- ---------------------------------------------------------------------
savepoint test_9;
do $$
declare
    v_violation_count integer;
begin
    select count(*) into v_violation_count
    from public.builds
    where status not in ('planning', 'in_progress', 'paused', 'completed')
       or progress < 0 or progress > 100
       or (status = 'completed' and progress <> 100);

    if v_violation_count > 0 then
        raise exception 'FAIL (test 9a): % builds row(s) violate a 0042 constraint after migration', v_violation_count using errcode = 'M0042L';
    end if;

    select count(*) into v_violation_count
    from public.build_revisions
    where progress < 0 or progress > 100
       or (status is not null and status not in ('planning', 'in_progress', 'paused', 'completed'))
       or (status = 'completed' and progress <> 100);

    if v_violation_count > 0 then
        raise exception 'FAIL (test 9b): % build_revisions row(s) violate a 0042 constraint after migration', v_violation_count using errcode = 'M0042L';
    end if;

    raise notice 'PASS (test 9): every builds/build_revisions row satisfies all 0042 constraints against real, production-shaped legacy data';
end $$;
rollback to savepoint test_9;

-- ---------------------------------------------------------------------
-- Test 10: build_revisions.progress's actual column type after
-- migration is unchanged from what the fixture set it to (smallint) --
-- 0042 never alters it, confirming the smallint-vs-integer agnosticism
-- claim against a REAL smallint column, not just integer.
-- ---------------------------------------------------------------------
savepoint test_10;
do $$
declare
    v_data_type text;
begin
    select data_type into v_data_type
    from information_schema.columns
    where table_schema = 'public' and table_name = 'build_revisions' and column_name = 'progress';

    if v_data_type <> 'smallint' then
        raise exception 'FAIL (test 10): build_revisions.progress''s type changed to % -- 0042 must never alter this column''s existing type', v_data_type using errcode = 'M0042L';
    end if;

    raise notice 'PASS (test 10): build_revisions.progress remains smallint (its fixture-set, production-matching type) -- 0042 never touched it';
end $$;
rollback to savepoint test_10;

rollback;
