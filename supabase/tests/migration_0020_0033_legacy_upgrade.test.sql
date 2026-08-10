-- Legacy-upgrade migration test —
-- supabase/tests/migration_0020_0033_legacy_upgrade.test.sql
--
-- Verifies that migrations 0020-0033, applied on top of a
-- production-shaped legacy fixture (9 components + 6 aliases), leave
-- every existing row byte-for-byte intact, converge legacy and new
-- columns, keep RLS/policies working, and leave both the legacy
-- search_components() RPC and the moderation RPCs functional. This is
-- the "does the corrected chain safely upgrade a database that already
-- has production's populated catalog" half of the compatibility fix —
-- see migration_0020_0033_fresh_install.test.sql for the other half.
--
-- Renamed from migration_0020_0032_*.test.sql when 0033 (function
-- EXECUTE permission hardening) was added — 0033 changes no schema or
-- data, only grants, so none of the assertions below needed to change;
-- only the harness range and this file's own name did. Function-level
-- EXECUTE/permission assertions live in their own dedicated file,
-- migration_0033_function_execute_permissions.test.sql.
--
-- Harness — three ordered steps, all against the LOCAL Docker stack
-- only (never --linked, never a real project connection string):
--
--   1. Reset local db to exactly 0000-0019 (the pre-upgrade foundation):
--        npx supabase db reset --local --no-seed --version 0019
--
--   2. Inject the legacy fixture (creates the OLD-shaped
--      components/component_aliases tables + 9/6 rows + snapshot
--      tables, BEFORE 0020 exists to redefine anything):
--        docker exec -i <local-db-container> psql -U postgres -d postgres \
--            -v ON_ERROR_STOP=1 -f - < supabase/tests/fixtures/legacy_catalog_fixture.sql
--
--   3. Apply the remaining pending migrations (0020-0033) WITHOUT
--      wiping the fixture data just inserted — this is exactly what
--      `migration up` does differently from `db reset` (reset always
--      wipes and replays from scratch; `up` applies only what the
--      local migration-history table doesn't already have recorded,
--      leaving existing data alone):
--        npx supabase migration up --local
--
--   4. Run this file's assertions:
--        docker exec -i <local-db-container> psql -U postgres -d postgres \
--            -v ON_ERROR_STOP=1 -f - < supabase/tests/migration_0020_0033_legacy_upgrade.test.sql
--
-- (Find the local db container name with
-- `docker ps --format "{{.Names}}"` — look for the one whose image is
-- supabase/postgres.)
--
-- Plain SQL only — no psql meta-commands, and no SET/set_config() call
-- ever appears inside a `do $$ ... $$` block, matching this repo's
-- established SQL test convention (milestone_19_parts_catalog.test.sql)
-- of issuing role-switch statements top-level only.
--
-- The DML portion is wrapped in begin/rollback (nothing here should
-- persist); the final cleanup of the fixture's own snapshot tables
-- happens afterward, as plain top-level DROP TABLE statements outside
-- that transaction, so cleanup always happens regardless of whether any
-- assertion above it failed.

begin;

insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-0000-0000-000000000301', 'legacy-mod@example.invalid', '{"username": "legacy_mod_test"}'::jsonb),
    ('00000000-0000-0000-0000-000000000302', 'legacy-submitter@example.invalid', '{"username": "legacy_submitter_test"}'::jsonb)
on conflict (id) do nothing;

insert into public.catalog_moderators (user_id, granted_by)
values ('00000000-0000-0000-0000-000000000301', '00000000-0000-0000-0000-000000000301');

do $$
declare
    v_count int;
    v_mismatch_count int;
    v_component_type text;
    v_canonical_key text;
begin
    -- Test 1: row counts unchanged.
    select count(*) into v_count from public.components;
    if v_count = 9 then
        raise notice 'PASS (legacy test 1a): components row count is still 9';
    else
        raise warning 'FAIL (legacy test 1a): expected 9 components, found %', v_count;
    end if;

    select count(*) into v_count from public.component_aliases;
    if v_count = 6 then
        raise notice 'PASS (legacy test 1b): component_aliases row count is still 6';
    else
        raise warning 'FAIL (legacy test 1b): expected 6 aliases, found %', v_count;
    end if;

    -- Test 2: exact ids and legacy column values survived unchanged —
    -- catches a delete-and-reinsert bug that a row-count check alone
    -- would miss.
    select count(*) into v_mismatch_count
        from public._legacy_upgrade_pre_components pre
        full outer join public.components cur using (id)
        where pre.id is null
           or cur.id is null
           or pre.technology_id is distinct from cur.technology_id
           or pre.component_type is distinct from cur.component_type
           or pre.canonical_name is distinct from cur.canonical_name
           or pre.manufacturer is distinct from cur.manufacturer
           or pre.canonical_key is distinct from cur.canonical_key;
    if v_mismatch_count = 0 then
        raise notice 'PASS (legacy test 2a): every pre-migration component id and legacy column value is unchanged';
    else
        raise warning 'FAIL (legacy test 2a): % component rows have a changed id or legacy column value', v_mismatch_count;
    end if;

    select count(*) into v_mismatch_count
        from public._legacy_upgrade_pre_aliases pre
        full outer join public.component_aliases cur using (id)
        where pre.id is null
           or cur.id is null
           or pre.component_id is distinct from cur.component_id
           or pre.alias is distinct from cur.alias
           or pre.alias_key is distinct from cur.alias_key;
    if v_mismatch_count = 0 then
        raise notice 'PASS (legacy test 2b): every pre-migration alias id and legacy column value is unchanged';
    else
        raise warning 'FAIL (legacy test 2b): % alias rows have a changed id or legacy column value', v_mismatch_count;
    end if;

    -- Test 3: no duplicate or orphaned rows introduced.
    select count(*) into v_count from public.component_aliases ca
        left join public.components c on c.id = ca.component_id
        where c.id is null;
    if v_count = 0 then
        raise notice 'PASS (legacy test 3a): no orphaned aliases';
    else
        raise warning 'FAIL (legacy test 3a): % aliases reference a non-existent component', v_count;
    end if;

    select count(*) into v_count from (
        select id from public.components group by id having count(*) > 1
    ) dupes;
    if v_count = 0 then
        raise notice 'PASS (legacy test 3b): no duplicate component ids';
    else
        raise warning 'FAIL (legacy test 3b): % duplicate component ids found', v_count;
    end if;

    -- Test 4: legacy and new columns contain consistent values for
    -- every one of the 9/6 pre-existing rows.
    select count(*) into v_mismatch_count from public.components
        where field_key is distinct from component_type
           or normalized_name is distinct from canonical_key;
    if v_mismatch_count = 0 then
        raise notice 'PASS (legacy test 4a): field_key/normalized_name match component_type/canonical_key on every component';
    else
        raise warning 'FAIL (legacy test 4a): % components have inconsistent legacy/new column values', v_mismatch_count;
    end if;

    select count(*) into v_mismatch_count from public.component_aliases
        where normalized_alias is distinct from alias_key;
    if v_mismatch_count = 0 then
        raise notice 'PASS (legacy test 4b): normalized_alias matches alias_key on every alias';
    else
        raise warning 'FAIL (legacy test 4b): % aliases have inconsistent legacy/new column values', v_mismatch_count;
    end if;

    select count(*) into v_mismatch_count from public.component_aliases ca
        join public.components c on c.id = ca.component_id
        where ca.technology_id is distinct from c.technology_id
           or ca.field_key is distinct from c.field_key;
    if v_mismatch_count = 0 then
        raise notice 'PASS (legacy test 4c): every alias technology_id/field_key matches its parent component';
    else
        raise warning 'FAIL (legacy test 4c): % aliases have technology_id/field_key that disagrees with their parent component', v_mismatch_count;
    end if;

    -- Test 5: RLS and required policies exist — both the pre-existing
    -- legacy-named policy (left untouched) and 0020/0021's own named
    -- policy (added alongside it) should be present.
    if (select relrowsecurity from pg_class where oid = 'public.components'::regclass)
        and (select relrowsecurity from pg_class where oid = 'public.component_aliases'::regclass)
    then
        raise notice 'PASS (legacy test 5a): RLS is still enabled on both tables';
    else
        raise warning 'FAIL (legacy test 5a): RLS is not enabled on one or both tables';
    end if;

    select count(*) into v_count from pg_policies
        where schemaname = 'public' and tablename = 'components'
          and policyname in ('components_legacy_public_read', 'Components catalog is readable by everyone');
    if v_count = 2 then
        raise notice 'PASS (legacy test 5b): both the pre-existing legacy policy and the new named policy are present on components';
    else
        raise warning 'FAIL (legacy test 5b): expected 2 read policies on components, found %', v_count;
    end if;

    select count(*) into v_count from pg_policies
        where schemaname = 'public' and tablename = 'component_aliases'
          and policyname in ('component_aliases_legacy_public_read', 'Component aliases are readable by everyone');
    if v_count = 2 then
        raise notice 'PASS (legacy test 5c): both the pre-existing legacy policy and the new named policy are present on component_aliases';
    else
        raise warning 'FAIL (legacy test 5c): expected 2 read policies on component_aliases, found %', v_count;
    end if;

    -- Test 6: legacy unique constraint/index from the fixture (stand-in
    -- for production's own real one) survived untouched.
    select count(*) into v_count from pg_constraint
        where conrelid = 'public.components'::regclass and conname = 'components_legacy_unique_key';
    if v_count = 1 then
        raise notice 'PASS (legacy test 6a): the pre-existing legacy unique constraint on components is untouched';
    else
        raise warning 'FAIL (legacy test 6a): the pre-existing legacy unique constraint on components is missing';
    end if;

    select count(*) into v_count from pg_constraint
        where conrelid = 'public.component_aliases'::regclass and conname = 'component_aliases_legacy_alias_key_key';
    if v_count = 1 then
        raise notice 'PASS (legacy test 6b): the pre-existing legacy unique constraint on component_aliases is untouched';
    else
        raise warning 'FAIL (legacy test 6b): the pre-existing legacy unique constraint on component_aliases is missing';
    end if;

    -- Test 7: the legacy search_components(text,text,text,integer) RPC
    -- still exists (not dropped/redefined) and is still callable with
    -- its original signature, returning a component that predates 0020.
    select component_type, canonical_key into v_component_type, v_canonical_key
        from public.search_components('pc_build', 'cpu', '7800x3d', 10)
        where id = '10000000-0000-0000-0000-000000000001';
    if v_component_type = 'cpu' and v_canonical_key = 'amdryzen77800x3d' then
        raise notice 'PASS (legacy test 7): search_components(text,text,text,integer) still works and still returns pre-existing legacy rows';
    else
        raise warning 'FAIL (legacy test 7): search_components() did not return the expected pre-existing row';
    end if;
end $$;

-- Test 8: submission approval, new-component path, against the
-- upgraded legacy schema. Role switch is top-level, DO block below
-- only calls the already-privileged function.
insert into public.component_submissions (technology_id, field_key, submitted_name, submitted_by)
values ('pc_build', 'gpu', 'Legacy Test GPU', '00000000-0000-0000-0000-000000000302');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000301', true);
set local role authenticated;

do $$
declare
    v_submission_id uuid;
    v_resolved_component_id uuid;
    v_component_type text;
    v_canonical_key text;
begin
    select id into v_submission_id from public.component_submissions where submitted_name = 'Legacy Test GPU';
    v_resolved_component_id := public.approve_component_submission(v_submission_id);

    select component_type, canonical_key into v_component_type, v_canonical_key
        from public.components where id = v_resolved_component_id;

    if v_component_type = 'gpu' and v_canonical_key = 'legacytestgpu' then
        raise notice 'PASS (legacy test 8): approve_component_submission() works post-upgrade and populates legacy fields consistently (% / %)', v_component_type, v_canonical_key;
    else
        raise warning 'FAIL (legacy test 8): component_type=%, canonical_key=% (expected gpu / legacytestgpu)', v_component_type, v_canonical_key;
    end if;
end $$;

reset role;

-- Test 9: submission approval via the alias path, attaching to a
-- pre-existing, pre-migration legacy component. Deliberately NOT
-- "7800 X3D" — that normalizes to "7800x3d", which collides with the
-- fixture's own pre-existing alias "7800X3D" on this same component
-- (id ...0001) and correctly gets rejected by the alias uniqueness
-- constraint. "Ryzen 7 7800X3D CPU" normalizes to "ryzen77800x3dcpu",
-- distinct from every canonical_key/alias_key already in the fixture.
insert into public.component_submissions (technology_id, field_key, submitted_name, submitted_by)
values ('pc_build', 'cpu', 'Ryzen 7 7800X3D CPU', '00000000-0000-0000-0000-000000000302');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000301', true);
set local role authenticated;

do $$
declare
    v_submission_id uuid;
    v_resolved_component_id uuid;
begin
    select id into v_submission_id from public.component_submissions where submitted_name = 'Ryzen 7 7800X3D CPU';
    v_resolved_component_id := public.approve_component_submission(
        v_submission_id, '10000000-0000-0000-0000-000000000001'
    );

    if v_resolved_component_id = '10000000-0000-0000-0000-000000000001' then
        raise notice 'PASS (legacy test 9): alias-path approval correctly resolved to the pre-existing legacy component';
    else
        raise warning 'FAIL (legacy test 9): alias-path approval resolved to % instead of the pre-existing legacy component', v_resolved_component_id;
    end if;
end $$;

reset role;

-- Test 10: rejection, post-upgrade.
insert into public.component_submissions (technology_id, field_key, submitted_name, submitted_by)
values ('pc_build', 'gpu', 'Legacy Test GPU Reject', '00000000-0000-0000-0000-000000000302');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000301', true);
set local role authenticated;

do $$
declare
    v_submission_id uuid;
    v_count int;
begin
    select id into v_submission_id from public.component_submissions where submitted_name = 'Legacy Test GPU Reject';
    perform public.reject_component_submission(v_submission_id, 'legacy-upgrade test rejection');

    select count(*) into v_count from public.component_submissions
        where id = v_submission_id and status = 'rejected';
    if v_count = 1 then
        raise notice 'PASS (legacy test 10): reject_component_submission() works post-upgrade';
    else
        raise warning 'FAIL (legacy test 10): submission was not marked rejected';
    end if;
end $$;

reset role;

rollback;

-- Cleanup: the fixture's own snapshot tables aren't part of any real
-- schema — drop them regardless of pass/fail above. Top-level,
-- deliberately outside the rolled-back transaction (a DROP TABLE
-- inside a rolled-back transaction would itself be rolled back).
drop table if exists public._legacy_upgrade_pre_components;
drop table if exists public._legacy_upgrade_pre_aliases;
