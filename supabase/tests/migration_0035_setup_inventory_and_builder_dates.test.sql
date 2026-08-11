-- Migration 0035 test —
-- supabase/tests/migration_0035_setup_inventory_and_builder_dates.test.sql
--
-- Covers migration 0035 (setup_inventory_and_builder_dates): the new
-- setup_inventory jsonb column on project_drafts/builds/build_revisions,
-- the new public.saved_setup_categories table (owner-only RLS, no public
-- read, case/whitespace-insensitive per-user uniqueness, name length
-- CHECK), profiles.building_since_year (nullable integer, bounded CHECK,
-- writable only through the existing owner-scoped profiles RLS policy),
-- and that publish_draft()/restore_revision_to_draft() correctly
-- copy/restore setup_inventory alongside every field they already
-- handled before this migration.
--
-- STATUS: intended to run against the local disposable Supabase/Docker
-- stack only (`supabase db reset --local`) — never against a linked or
-- production project. Same fixture-safety posture as every other file
-- in this directory: fake auth.users rows, namespaced usernames, a
-- single outer transaction that ends in ROLLBACK, each test in its own
-- SAVEPOINT. Depends on migrations 0000-0035 already being applied.
--
-- Fail-closed design: every assertion raises a real PostgreSQL ERROR on
-- failure (via `raise exception ... using errcode = 'M0035'`), matching
-- migration_0034_guidelines_accepted_version.test.sql's convention —
-- `psql -v ON_ERROR_STOP=1` only stops on an actual ERROR, never a mere
-- WARNING/NOTICE.

begin;

insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-0000-0000-000000000601', 'm0035-owner@example.invalid', '{"username": "m0035_owner_test"}'::jsonb),
    ('00000000-0000-0000-0000-000000000602', 'm0035-other@example.invalid', '{"username": "m0035_other_test"}'::jsonb)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- Test 1: setup_inventory exists on all three tables, jsonb, not null,
-- with the expected default shape.
-- ---------------------------------------------------------------------
savepoint test_1;
do $$
declare
    v_data_type text;
    v_is_nullable text;
begin
    foreach v_data_type in array array['project_drafts', 'builds', 'build_revisions']
    loop
        select data_type, is_nullable
        into v_data_type, v_is_nullable
        from information_schema.columns
        where table_schema = 'public' and table_name = v_data_type and column_name = 'setup_inventory';

        if v_data_type is null then
            raise exception 'FAIL (test 1a): %.setup_inventory does not exist', v_data_type using errcode = 'M0035';
        end if;

        if v_data_type <> 'jsonb' then
            raise exception 'FAIL (test 1b): setup_inventory is type %, expected jsonb', v_data_type using errcode = 'M0035';
        end if;

        if v_is_nullable <> 'NO' then
            raise exception 'FAIL (test 1c): setup_inventory is nullable, expected NOT NULL' using errcode = 'M0035';
        end if;
    end loop;

    raise notice 'PASS (test 1): setup_inventory exists as a not-null jsonb column on all three tables';
end $$;
rollback to savepoint test_1;

savepoint test_1b;
do $$
declare
    v_draft_id uuid;
    v_inventory jsonb;
begin
    insert into public.project_drafts (id, user_id, title, category)
    values (gen_random_uuid(), '00000000-0000-0000-0000-000000000601', 'M0035 Default Test', 'setup')
    returning id into v_draft_id;

    select setup_inventory into v_inventory from public.project_drafts where id = v_draft_id;

    if v_inventory is null or v_inventory->>'schemaVersion' is null or (v_inventory->'categories') is null then
        raise exception 'FAIL (test 1b): a new draft''s default setup_inventory is not the expected empty-inventory shape (got %)', v_inventory using errcode = 'M0035';
    end if;

    if jsonb_array_length(v_inventory->'categories') <> 0 then
        raise exception 'FAIL (test 1b): a new draft''s default setup_inventory has non-empty categories' using errcode = 'M0035';
    end if;

    raise notice 'PASS (test 1b): a new project_drafts row gets the default empty-inventory shape with no explicit value';
end $$;
rollback to savepoint test_1b;

-- ---------------------------------------------------------------------
-- Test 2: saved_setup_categories — owner-only RLS (select/insert/
-- update/delete), no public/other-user access.
-- ---------------------------------------------------------------------
savepoint test_2;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000601', true);
set local role authenticated;
do $$
declare
    v_id uuid;
begin
    insert into public.saved_setup_categories (id, user_id, name)
    values (gen_random_uuid(), '00000000-0000-0000-0000-000000000601', 'Desk Accessories')
    returning id into v_id;

    if v_id is null then
        raise exception 'FAIL (test 2a): owner insert of saved_setup_categories did not succeed' using errcode = 'M0035';
    end if;

    raise notice 'PASS (test 2a): an authenticated owner can insert their own saved_setup_categories row';
end $$;
reset role;
rollback to savepoint test_2;

savepoint test_2_isolation;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000601', true);
set local role authenticated;
do $$
begin
    insert into public.saved_setup_categories (id, user_id, name)
    values ('00000000-0000-0000-0000-000000000701', '00000000-0000-0000-0000-000000000601', 'Desk Accessories');
end $$;
reset role;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000602', true);
set local role authenticated;
do $$
declare
    v_visible_count int;
    v_updated_rows int;
begin
    select count(*) into v_visible_count
    from public.saved_setup_categories
    where id = '00000000-0000-0000-0000-000000000701';

    if v_visible_count <> 0 then
        raise exception 'FAIL (test 2b): a different authenticated user can SELECT another owner''s saved_setup_categories row' using errcode = 'M0035';
    end if;

    update public.saved_setup_categories
        set name = 'Hijacked'
        where id = '00000000-0000-0000-0000-000000000701';
    get diagnostics v_updated_rows = row_count;

    if v_updated_rows <> 0 then
        raise exception 'FAIL (test 2c): a different authenticated user can UPDATE another owner''s saved_setup_categories row' using errcode = 'M0035';
    end if;

    raise notice 'PASS (test 2b/2c): saved_setup_categories is genuinely owner-scoped — a different user can neither read nor write another owner''s row';
end $$;
reset role;
rollback to savepoint test_2_isolation;

savepoint test_2_no_public;
do $$
declare
    v_select_policy_count int;
    v_permissive_select_exists boolean;
begin
    -- Every policy in this schema (including every pre-existing one
    -- already proven safe, e.g. "Users can update their own profile")
    -- is created with no explicit `to <role>` clause, which Postgres
    -- reports back as roles = {public} — that means "applies regardless
    -- of which DB role connects," NOT "unconditionally readable by
    -- anyone." The real gate is the USING/WITH CHECK expression. What
    -- would actually make this table publicly readable is a SELECT
    -- policy with a trivial/always-true (or null) qual — that's what
    -- this checks for, rather than the harmless {public} role list.
    select count(*) into v_select_policy_count
    from pg_policies
    where schemaname = 'public' and tablename = 'saved_setup_categories' and cmd = 'SELECT';

    if v_select_policy_count <> 1 then
        raise exception 'FAIL (test 2d): expected exactly 1 SELECT policy on saved_setup_categories, found %', v_select_policy_count using errcode = 'M0035';
    end if;

    select exists (
        select 1 from pg_policies
        where schemaname = 'public'
          and tablename = 'saved_setup_categories'
          and cmd = 'SELECT'
          and (qual is null or qual = 'true' or qual !~ 'user_id')
    ) into v_permissive_select_exists;

    if v_permissive_select_exists then
        raise exception 'FAIL (test 2d): saved_setup_categories'' SELECT policy has no owner-scoped (user_id-based) condition — reusable category templates must never be publicly readable' using errcode = 'M0035';
    end if;

    raise notice 'PASS (test 2d): the single SELECT policy on saved_setup_categories is owner-scoped, not publicly permissive';
end $$;
rollback to savepoint test_2_no_public;

-- ---------------------------------------------------------------------
-- Test 3: saved_setup_categories — case/whitespace-insensitive per-user
-- uniqueness, and a non-empty-name CHECK constraint.
-- ---------------------------------------------------------------------
savepoint test_3;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000601', true);
set local role authenticated;
do $$
begin
    insert into public.saved_setup_categories (id, user_id, name)
    values (gen_random_uuid(), '00000000-0000-0000-0000-000000000601', 'Cable Management');

    begin
        insert into public.saved_setup_categories (id, user_id, name)
        values (gen_random_uuid(), '00000000-0000-0000-0000-000000000601', '  cable management  ');
        raise exception 'FAIL (test 3a): a near-duplicate name (different case/whitespace) was NOT rejected by the uniqueness constraint' using errcode = 'M0035';
    exception when unique_violation then
        raise notice 'PASS (test 3a): a case/whitespace-normalized duplicate saved-category name is rejected';
    end;
end $$;
reset role;
rollback to savepoint test_3;

savepoint test_3_blank;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000601', true);
set local role authenticated;
do $$
begin
    begin
        insert into public.saved_setup_categories (id, user_id, name)
        values (gen_random_uuid(), '00000000-0000-0000-0000-000000000601', '   ');
        raise exception 'FAIL (test 3b): a blank/whitespace-only category name was accepted' using errcode = 'M0035';
    exception when check_violation then
        raise notice 'PASS (test 3b): a blank/whitespace-only category name is rejected by the CHECK constraint';
    end;
end $$;
reset role;
rollback to savepoint test_3_blank;

-- ---------------------------------------------------------------------
-- Test 4: profiles.building_since_year — nullable integer, bounded
-- CHECK constraint, writable only through the existing owner-scoped RLS
-- policy.
-- ---------------------------------------------------------------------
savepoint test_4;
do $$
declare
    v_data_type text;
    v_is_nullable text;
begin
    select data_type, is_nullable
    into v_data_type, v_is_nullable
    from information_schema.columns
    where table_schema = 'public' and table_name = 'profiles' and column_name = 'building_since_year';

    if v_data_type is null then
        raise exception 'FAIL (test 4a): profiles.building_since_year does not exist' using errcode = 'M0035';
    end if;

    if v_data_type <> 'integer' then
        raise exception 'FAIL (test 4b): building_since_year is type %, expected integer', v_data_type using errcode = 'M0035';
    end if;

    if v_is_nullable <> 'YES' then
        raise exception 'FAIL (test 4c): building_since_year is NOT NULL, expected nullable (existing users must get null, never a backfilled guess)' using errcode = 'M0035';
    end if;

    raise notice 'PASS (test 4): building_since_year exists, nullable, integer-typed';
end $$;
rollback to savepoint test_4;

savepoint test_5;
do $$
begin
    update public.profiles set building_since_year = null where id = '00000000-0000-0000-0000-000000000601';
    update public.profiles set building_since_year = 2019 where id = '00000000-0000-0000-0000-000000000601';
    raise notice 'PASS (test 5a): null and a valid past year are both accepted';
exception when check_violation then
    raise exception 'FAIL (test 5a): a valid building_since_year (null or a past year) was unexpectedly rejected' using errcode = 'M0035';
end $$;
rollback to savepoint test_5;

savepoint test_6;
do $$
begin
    begin
        update public.profiles set building_since_year = extract(year from now())::integer + 1 where id = '00000000-0000-0000-0000-000000000601';
        raise exception 'FAIL (test 6a): a future building_since_year was accepted' using errcode = 'M0035';
    exception when check_violation then
        raise notice 'PASS (test 6a): a future building_since_year is rejected by the CHECK constraint';
    end;

    begin
        update public.profiles set building_since_year = 1979 where id = '00000000-0000-0000-0000-000000000601';
        raise exception 'FAIL (test 6b): a building_since_year below the lower bound (1979) was accepted' using errcode = 'M0035';
    exception when check_violation then
        raise notice 'PASS (test 6b): a building_since_year below the lower bound is rejected by the CHECK constraint';
    end;
end $$;
rollback to savepoint test_6;

savepoint test_7;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000601', true);
set local role authenticated;
do $$
declare
    v_year int;
begin
    update public.profiles set building_since_year = 2021 where id = '00000000-0000-0000-0000-000000000601';
    select building_since_year into v_year from public.profiles where id = '00000000-0000-0000-0000-000000000601';

    if v_year <> 2021 then
        raise exception 'FAIL (test 7): owner write of building_since_year did not persist (got %)', v_year using errcode = 'M0035';
    end if;

    raise notice 'PASS (test 7): an authenticated owner can write their own building_since_year via the existing profiles RLS policy — no new policy needed';
end $$;
reset role;
rollback to savepoint test_7;

-- ---------------------------------------------------------------------
-- Test 8: publish_draft() copies setup_inventory into both builds (on
-- first publish) and build_revisions.
-- ---------------------------------------------------------------------
savepoint test_8;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000601', true);
set local role authenticated;
do $$
declare
    v_draft_id uuid;
    v_media_id uuid;
    v_build public.builds;
    v_inventory jsonb := '{"schemaVersion":1,"currency":"USD","categories":[{"id":"cat-1","name":"Desk","templateId":null,"sortOrder":0,"items":[{"id":"item-1","title":"Standing Desk","originalUrl":null,"retailerName":null,"listedPriceCents":null,"listedPriceCurrency":null,"metadataFetchedAt":null,"pricePaid":{"cents":45000,"isFree":false},"sourceType":"retailer","sourceName":"IKEA","sortOrder":0}]}]}'::jsonb;
    v_build_inventory jsonb;
    v_revision_inventory jsonb;
begin
    insert into public.project_drafts (id, user_id, title, description, category, setup_inventory)
    values (gen_random_uuid(), '00000000-0000-0000-0000-000000000601', 'M0035 Publish Test', 'A setup with real content for readiness.', 'setup', v_inventory)
    returning id into v_draft_id;

    -- publish_draft() requires readiness (a cover image among other
    -- things) — not this migration's own concern, but a real
    -- precondition of calling it at all.
    insert into public.project_media (id, draft_id, storage_path)
    values (gen_random_uuid(), v_draft_id, 'test-fixtures/cover.jpg')
    returning id into v_media_id;

    update public.project_drafts set cover_media_id = v_media_id where id = v_draft_id;

    v_build := public.publish_draft(v_draft_id);

    select setup_inventory into v_build_inventory from public.builds where id = v_build.id;
    select setup_inventory into v_revision_inventory from public.build_revisions where build_id = v_build.id order by created_at desc limit 1;

    if v_build_inventory <> v_inventory then
        raise exception 'FAIL (test 8a): publish_draft() did not copy setup_inventory into builds (got %)', v_build_inventory using errcode = 'M0035';
    end if;

    if v_revision_inventory <> v_inventory then
        raise exception 'FAIL (test 8b): publish_draft() did not copy setup_inventory into the new build_revisions row (got %)', v_revision_inventory using errcode = 'M0035';
    end if;

    raise notice 'PASS (test 8): publish_draft() copies setup_inventory into both builds and build_revisions';
end $$;
reset role;
rollback to savepoint test_8;

-- ---------------------------------------------------------------------
-- Test 9: restore_revision_to_draft() restores a revision's
-- setup_inventory snapshot back onto the draft.
-- ---------------------------------------------------------------------
savepoint test_9;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000601', true);
set local role authenticated;
do $$
declare
    v_draft_id uuid;
    v_media_id uuid;
    v_build public.builds;
    v_revision_id uuid;
    v_restored_draft public.project_drafts;
    v_expected_updated_at timestamptz;
    v_snapshot_inventory jsonb := '{"schemaVersion":1,"currency":"USD","categories":[{"id":"cat-2","name":"Lighting","templateId":null,"sortOrder":0,"items":[]}]}'::jsonb;
    v_empty_inventory jsonb := '{"schemaVersion":1,"currency":"USD","categories":[]}'::jsonb;
begin
    insert into public.project_drafts (id, user_id, title, description, category, setup_inventory)
    values (gen_random_uuid(), '00000000-0000-0000-0000-000000000601', 'M0035 Restore Test', 'A setup with real content for readiness.', 'setup', v_snapshot_inventory)
    returning id into v_draft_id;

    insert into public.project_media (id, draft_id, storage_path)
    values (gen_random_uuid(), v_draft_id, 'test-fixtures/cover.jpg')
    returning id into v_media_id;

    update public.project_drafts set cover_media_id = v_media_id where id = v_draft_id;

    v_build := public.publish_draft(v_draft_id);

    select id into v_revision_id from public.build_revisions where build_id = v_build.id order by created_at desc limit 1;

    -- Simulate later drift: the draft's inventory changes after publish,
    -- and should be overwritten back to the revision's snapshot on restore.
    update public.project_drafts set setup_inventory = v_empty_inventory where id = v_draft_id;

    -- restore_revision_to_draft()'s optimistic-concurrency check requires
    -- the draft's real current updated_at, not null (null is only valid
    -- when no draft is linked to the build at all — not this case).
    select updated_at into v_expected_updated_at from public.project_drafts where id = v_draft_id;

    v_restored_draft := public.restore_revision_to_draft(v_revision_id, v_expected_updated_at);

    if v_restored_draft.setup_inventory <> v_snapshot_inventory then
        raise exception 'FAIL (test 9): restore_revision_to_draft() did not restore setup_inventory from the revision snapshot (got %)', v_restored_draft.setup_inventory using errcode = 'M0035';
    end if;

    raise notice 'PASS (test 9): restore_revision_to_draft() restores the revision''s setup_inventory snapshot back onto the draft';
end $$;
reset role;
rollback to savepoint test_9;

-- ---------------------------------------------------------------------
-- Test 10: rollback behavior — the paired rollback file's statements
-- remove every 0035 addition cleanly.
-- ---------------------------------------------------------------------
savepoint test_10;
do $$
begin
    insert into public.saved_setup_categories (id, user_id, name)
    values ('00000000-0000-0000-0000-000000000702', '00000000-0000-0000-0000-000000000601', 'Rollback Check');

    update public.profiles set building_since_year = 2020 where id = '00000000-0000-0000-0000-000000000601';
end $$;

alter table public.project_drafts drop column if exists setup_inventory;
alter table public.builds drop column if exists setup_inventory;
alter table public.build_revisions drop column if exists setup_inventory;
alter table public.profiles drop column if exists building_since_year;
drop table if exists public.saved_setup_categories;
drop function if exists public.set_saved_setup_category_normalized_name();

do $$
declare
    v_any_column_exists boolean;
    v_table_exists boolean;
begin
    select exists (
        select 1 from information_schema.columns
        where table_schema = 'public'
          and ((table_name = 'project_drafts' and column_name = 'setup_inventory')
            or (table_name = 'builds' and column_name = 'setup_inventory')
            or (table_name = 'build_revisions' and column_name = 'setup_inventory')
            or (table_name = 'profiles' and column_name = 'building_since_year'))
    ) into v_any_column_exists;

    if v_any_column_exists then
        raise exception 'FAIL (test 10a): one or more 0035 columns still exist after the rollback statements ran' using errcode = 'M0035';
    end if;

    select exists (
        select 1 from information_schema.tables
        where table_schema = 'public' and table_name = 'saved_setup_categories'
    ) into v_table_exists;

    if v_table_exists then
        raise exception 'FAIL (test 10b): saved_setup_categories still exists after the rollback statement ran' using errcode = 'M0035';
    end if;

    raise notice 'PASS (test 10): rollback drops every 0035 column/table/trigger-function cleanly';
end $$;
rollback to savepoint test_10;

rollback;
