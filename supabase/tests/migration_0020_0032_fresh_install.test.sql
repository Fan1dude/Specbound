-- Fresh-install migration test —
-- supabase/tests/migration_0020_0032_fresh_install.test.sql
--
-- Verifies the parts-catalog portion (0020-0022) of the migration chain
-- ends up in the shape this app's code expects, once the FULL chain
-- (0000-0032) has been applied to a database that never saw any of it
-- before. This is the "does the corrected chain still work on a brand
-- new database" half of the production-compatibility fix for
-- 0020-0022 — see migration_0020_0032_legacy_upgrade.test.sql (plus its
-- companion fixtures/legacy_catalog_fixture.sql) for the other half.
--
-- Harness: this file assumes migrations 0000-0032 are ALREADY applied —
-- it does not apply them itself. Actually applying the chain is the
-- Supabase CLI's job, not psql's:
--
--   npx supabase db reset --local --no-seed
--   docker exec -i <local-db-container> psql -U postgres -d postgres \
--       -v ON_ERROR_STOP=1 -f - < supabase/tests/migration_0020_0032_fresh_install.test.sql
--
-- (`supabase db reset --local` re-applies every file in
-- supabase/migrations/ in order against a freshly wiped local
-- database — this genuinely is "apply 0000-0032 to an empty disposable
-- database," just performed by the CLI instead of a hand-rolled \i
-- loop. Find the local db container name with
-- `docker ps --format "{{.Names}}"` — look for the one whose image is
-- supabase/postgres.) NEVER point this at anything but the local
-- Docker stack started by `supabase start` — never `--linked`, never a
-- real project's connection string.
--
-- Plain SQL only, deliberately — no psql meta-commands (\i, \echo,
-- \set), and no SET/set_config() call ever appears inside a
-- `do $$ ... $$` block. Both are because this repo's established SQL
-- test convention (milestone_19_parts_catalog.test.sql) issues all
-- role-switch statements top-level, never from inside a DO block —
-- keeping that convention here too, on top of it also being required
-- for portability to a plain psql-over-stdin harness.
--
-- Wrapped in begin/rollback: nothing here is meant to persist — this
-- only reads the schema and exercises inserts/RPCs to prove the
-- triggers and functions behave correctly, then reverts all of it.

begin;

insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-0000-0000-000000000201', 'fresh-mod@example.invalid', '{"username": "fresh_mod_test"}'::jsonb),
    ('00000000-0000-0000-0000-000000000202', 'fresh-submitter@example.invalid', '{"username": "fresh_submitter_test"}'::jsonb)
on conflict (id) do nothing;

insert into public.catalog_moderators (user_id, granted_by)
values ('00000000-0000-0000-0000-000000000201', '00000000-0000-0000-0000-000000000201');

do $$
declare
    v_count int;
    v_component_id uuid;
    v_component_type text;
    v_canonical_key text;
    v_alias_key text;
begin
    -- Test 1: components/component_aliases exist with every column this
    -- app's code and legacy-compat both need.
    select count(*) into v_count from information_schema.columns
        where table_schema = 'public' and table_name = 'components'
          and column_name in ('id', 'technology_id', 'field_key', 'component_type',
              'canonical_name', 'normalized_name', 'canonical_key', 'manufacturer',
              'metadata', 'created_by', 'created_at', 'updated_at');
    if v_count = 12 then
        raise notice 'PASS (fresh test 1): public.components has all 12 expected columns';
    else
        raise warning 'FAIL (fresh test 1): expected 12 matching columns on public.components, found %', v_count;
    end if;

    select count(*) into v_count from information_schema.columns
        where table_schema = 'public' and table_name = 'component_aliases'
          and column_name in ('id', 'component_id', 'alias', 'alias_key',
              'normalized_alias', 'technology_id', 'field_key', 'created_at');
    if v_count = 8 then
        raise notice 'PASS (fresh test 2): public.component_aliases has all 8 expected columns';
    else
        raise warning 'FAIL (fresh test 2): expected 8 matching columns on public.component_aliases, found %', v_count;
    end if;

    -- Test 3: RLS enabled + expected policies exist.
    if (select relrowsecurity from pg_class where oid = 'public.components'::regclass)
        and (select relrowsecurity from pg_class where oid = 'public.component_aliases'::regclass)
    then
        raise notice 'PASS (fresh test 3): RLS is enabled on both tables';
    else
        raise warning 'FAIL (fresh test 3): RLS is not enabled on one or both tables';
    end if;

    select count(*) into v_count from pg_policies
        where schemaname = 'public' and tablename = 'components'
          and policyname in ('Components catalog is readable by everyone', 'Catalog moderators can add catalog components');
    if v_count = 2 then
        raise notice 'PASS (fresh test 4): both expected components policies exist';
    else
        raise warning 'FAIL (fresh test 4): expected 2 named policies on components, found %', v_count;
    end if;

    -- Test 5: inserting a component auto-populates the
    -- legacy-compatibility columns via the sync trigger. No role switch
    -- needed here — this is a plain insert exercising the trigger, not
    -- an RLS or auth.uid()-gated path.
    insert into public.components (technology_id, field_key, canonical_name, created_by)
    values ('pc_build', 'gpu', 'RTX 5090 Fresh Test', '00000000-0000-0000-0000-000000000201')
    returning id, component_type, canonical_key into v_component_id, v_component_type, v_canonical_key;

    if v_component_type = 'gpu' and v_canonical_key = 'rtx5090freshtest' then
        raise notice 'PASS (fresh test 5): component_type/canonical_key were auto-populated correctly on insert (% / %)', v_component_type, v_canonical_key;
    else
        raise warning 'FAIL (fresh test 5): component_type=%, canonical_key=% (expected gpu / rtx5090freshtest)', v_component_type, v_canonical_key;
    end if;

    -- Test 6: same, for component_aliases.
    insert into public.component_aliases (component_id, alias)
    values (v_component_id, '5090 Fresh')
    returning alias_key into v_alias_key;

    if v_alias_key = '5090fresh' then
        raise notice 'PASS (fresh test 6): alias_key was auto-populated correctly on insert (%)', v_alias_key;
    else
        raise warning 'FAIL (fresh test 6): alias_key=% (expected 5090fresh)', v_alias_key;
    end if;
end $$;

-- Test 7: submission approval (new-component path). The role switch is
-- top-level, per the established convention — the DO block below only
-- calls the already-privileged function and reports, it never issues
-- SET/set_config itself.
insert into public.component_submissions (technology_id, field_key, submitted_name, submitted_by)
values ('pc_build', 'cpu', 'Fresh Test CPU', '00000000-0000-0000-0000-000000000202');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000201', true);
set local role authenticated;

do $$
declare
    v_submission_id uuid;
    v_component_id uuid;
    v_component_type text;
    v_canonical_key text;
begin
    select id into v_submission_id from public.component_submissions where submitted_name = 'Fresh Test CPU';
    v_component_id := public.approve_component_submission(v_submission_id);

    select component_type, canonical_key into v_component_type, v_canonical_key
        from public.components where id = v_component_id;

    if v_component_type = 'cpu' and v_canonical_key = 'freshtestcpu' then
        raise notice 'PASS (fresh test 7): approve_component_submission() populated legacy fields consistently (% / %)', v_component_type, v_canonical_key;
    else
        raise warning 'FAIL (fresh test 7): component_type=%, canonical_key=% (expected cpu / freshtestcpu)', v_component_type, v_canonical_key;
    end if;
end $$;

reset role;

-- Test 8: rejection.
insert into public.component_submissions (technology_id, field_key, submitted_name, submitted_by)
values ('pc_build', 'cpu', 'Fresh Test CPU Reject', '00000000-0000-0000-0000-000000000202');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000201', true);
set local role authenticated;

do $$
declare
    v_submission_id uuid;
    v_count int;
begin
    select id into v_submission_id from public.component_submissions where submitted_name = 'Fresh Test CPU Reject';
    perform public.reject_component_submission(v_submission_id, 'fresh-install test rejection');

    select count(*) into v_count from public.component_submissions
        where id = v_submission_id and status = 'rejected';

    if v_count = 1 then
        raise notice 'PASS (fresh test 8): reject_component_submission() still works';
    else
        raise warning 'FAIL (fresh test 8): submission was not marked rejected';
    end if;
end $$;

reset role;

rollback;
