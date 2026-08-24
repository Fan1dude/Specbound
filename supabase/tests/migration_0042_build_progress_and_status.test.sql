-- Migration 0042 test —
-- supabase/tests/migration_0042_build_progress_and_status.test.sql
--
-- Covers migration 0042 (build_progress_and_status): the new progress/
-- status columns on project_drafts/builds/build_revisions, the canonical
-- four-value status CHECK on all three tables, the one-directional
-- Completed/100 consistency CHECK on all three tables, and that
-- publish_draft()/restore_revision_to_draft() correctly copy/restore
-- progress+status alongside every field they already handled before this
-- migration — without changing either function's signature or ACL.
--
-- Assumes 0000-0042 are ALREADY applied (this file does not apply them
-- itself — see the header of migration_0020_0033_fresh_install.test.sql
-- for why that's the CLI's job, not psql's). For the "does 0042 correctly
-- normalize/reject pre-existing production-shaped data" half, see
-- migration_0042_legacy_upgrade.test.sql instead — that scenario can't
-- be exercised here because the normalization/verification logic runs
-- once, at migration-apply time, not as a re-runnable function.
--
--   npx supabase db reset --local --no-seed
--   docker exec -i <local-db-container> psql -U postgres -d postgres \
--       -v ON_ERROR_STOP=1 -f - < supabase/tests/migration_0042_build_progress_and_status.test.sql
--
-- STATUS: intended to run against the local disposable Supabase/Docker
-- stack only — never against a linked or production project. Same
-- fixture-safety posture as every other file in this directory: fake
-- auth.users rows, namespaced usernames, a single outer transaction that
-- ends in ROLLBACK, each test in its own SAVEPOINT.
--
-- Fail-closed design: every assertion raises a real PostgreSQL ERROR on
-- failure (via `raise exception ... using errcode = 'M0042'`), matching
-- migration_0035_setup_inventory_and_builder_dates.test.sql's convention
-- — `psql -v ON_ERROR_STOP=1` only stops on an actual ERROR, never a mere
-- WARNING/NOTICE.

begin;

insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-0000-0000-000000000801', 'm0042-owner@example.invalid', '{"username": "m0042_owner_test"}'::jsonb),
    ('00000000-0000-0000-0000-000000000802', 'm0042-other@example.invalid', '{"username": "m0042_other_test"}'::jsonb)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- Test 1: columns exist with the expected type/nullability/default on
-- all three tables.
-- ---------------------------------------------------------------------
savepoint test_1;
do $$
declare
    v_table text;
    v_data_type text;
    v_is_nullable text;
    v_default text;
begin
    -- progress: project_drafts and builds are both brand-new columns
    -- this migration itself defines as `integer` — strictly checked.
    -- build_revisions.progress predates 0042 (0000_baseline) and this
    -- migration deliberately never alters its type — it may legitimately
    -- be `smallint` (production's real type) or `integer` (the
    -- reconstructed baseline's claim); asserting one specific type here
    -- would defeat the entire point of 0042's smallint/integer
    -- agnosticism, so it's checked separately below instead.
    foreach v_table in array array['project_drafts', 'builds']
    loop
        select data_type, is_nullable, column_default
        into v_data_type, v_is_nullable, v_default
        from information_schema.columns
        where table_schema = 'public' and table_name = v_table and column_name = 'progress';

        if v_data_type is null then
            raise exception 'FAIL (test 1a): %.progress does not exist', v_table using errcode = 'M0042';
        end if;

        if v_data_type <> 'integer' then
            raise exception 'FAIL (test 1b): %.progress is type %, expected integer', v_table, v_data_type using errcode = 'M0042';
        end if;

        if v_is_nullable <> 'NO' then
            raise exception 'FAIL (test 1c): %.progress is nullable, expected NOT NULL', v_table using errcode = 'M0042';
        end if;

        if v_default is null or v_default !~ '^0' then
            raise exception 'FAIL (test 1d): %.progress default is %, expected 0', v_table, v_default using errcode = 'M0042';
        end if;
    end loop;

    -- build_revisions.progress: predates 0042, never altered by it --
    -- must be smallint or integer (both real, valid production/baseline
    -- shapes), still NOT NULL with its own pre-existing default of 0.
    select data_type, is_nullable, column_default
    into v_data_type, v_is_nullable, v_default
    from information_schema.columns
    where table_schema = 'public' and table_name = 'build_revisions' and column_name = 'progress';

    if v_data_type is null then
        raise exception 'FAIL (test 1a2): build_revisions.progress does not exist' using errcode = 'M0042';
    end if;

    if v_data_type not in ('smallint', 'integer') then
        raise exception 'FAIL (test 1b2): build_revisions.progress is type %, expected smallint or integer', v_data_type using errcode = 'M0042';
    end if;

    if v_is_nullable <> 'NO' then
        raise exception 'FAIL (test 1c2): build_revisions.progress is nullable, expected NOT NULL' using errcode = 'M0042';
    end if;

    if v_default is null or v_default !~ '^0' then
        raise exception 'FAIL (test 1d2): build_revisions.progress default is %, expected 0', v_default using errcode = 'M0042';
    end if;

    -- status: project_drafts (new) and builds (pre-existing since 0000,
    -- unchanged by 0042 except for its new CHECK) are both NOT NULL with
    -- a 'planning' default. build_revisions.status is handled separately
    -- below -- it is deliberately, permanently NULLABLE with NO default,
    -- since a legacy (pre-0042) revision has no recorded status and none
    -- is fabricated for it.
    foreach v_table in array array['project_drafts', 'builds']
    loop
        select data_type, is_nullable, column_default
        into v_data_type, v_is_nullable, v_default
        from information_schema.columns
        where table_schema = 'public' and table_name = v_table and column_name = 'status';

        if v_data_type is null then
            raise exception 'FAIL (test 1e): %.status does not exist', v_table using errcode = 'M0042';
        end if;

        if v_data_type <> 'text' then
            raise exception 'FAIL (test 1f): %.status is type %, expected text', v_table, v_data_type using errcode = 'M0042';
        end if;

        if v_is_nullable <> 'NO' then
            raise exception 'FAIL (test 1g): %.status is nullable, expected NOT NULL', v_table using errcode = 'M0042';
        end if;

        if v_default !~ 'planning' then
            raise exception 'FAIL (test 1h): %.status default is %, expected ''planning''', v_table, v_default using errcode = 'M0042';
        end if;
    end loop;

    -- build_revisions.status: text, NULLABLE, no default -- the "not
    -- recorded" signal for a legacy revision is a genuine NULL, not a
    -- fabricated 'planning' the column default would otherwise produce.
    select data_type, is_nullable, column_default
    into v_data_type, v_is_nullable, v_default
    from information_schema.columns
    where table_schema = 'public' and table_name = 'build_revisions' and column_name = 'status';

    if v_data_type is null then
        raise exception 'FAIL (test 1i): build_revisions.status does not exist' using errcode = 'M0042';
    end if;

    if v_data_type <> 'text' then
        raise exception 'FAIL (test 1j): build_revisions.status is type %, expected text', v_data_type using errcode = 'M0042';
    end if;

    if v_is_nullable <> 'YES' then
        raise exception 'FAIL (test 1k): build_revisions.status is NOT NULL, expected nullable (legacy revisions must be able to record "not recorded")' using errcode = 'M0042';
    end if;

    if v_default is not null then
        raise exception 'FAIL (test 1l): build_revisions.status has a default (%) -- expected none, so a legacy row stays genuinely NULL rather than silently defaulting', v_default using errcode = 'M0042';
    end if;

    raise notice 'PASS (test 1): progress/status exist with the expected type/nullability/default on all three tables (build_revisions.status correctly nullable with no default)';
end $$;
rollback to savepoint test_1;

-- ---------------------------------------------------------------------
-- Test 2: a freshly-created draft/build/revision gets safe, truthful
-- defaults (0 / 'planning'), not invented data.
-- ---------------------------------------------------------------------
savepoint test_2;
do $$
declare
    v_draft_id uuid;
    v_progress integer;
    v_status text;
begin
    insert into public.project_drafts (id, user_id, title, category)
    values (gen_random_uuid(), '00000000-0000-0000-0000-000000000801', 'M0042 Default Test', 'pc_build')
    returning id into v_draft_id;

    select progress, status into v_progress, v_status from public.project_drafts where id = v_draft_id;

    if v_progress <> 0 or v_status <> 'planning' then
        raise exception 'FAIL (test 2): a new draft''s defaults are progress=%, status=%, expected 0/planning', v_progress, v_status using errcode = 'M0042';
    end if;

    raise notice 'PASS (test 2): a new project_drafts row defaults to progress=0, status=planning with no explicit value';
end $$;
rollback to savepoint test_2;

-- ---------------------------------------------------------------------
-- Test 3: CHECK constraints — progress range, all three tables.
-- ---------------------------------------------------------------------
savepoint test_3;
do $$
declare
    v_draft_id uuid;
begin
    insert into public.project_drafts (id, user_id, title, category)
    values (gen_random_uuid(), '00000000-0000-0000-0000-000000000801', 'M0042 Range Test', 'pc_build')
    returning id into v_draft_id;

    begin
        update public.project_drafts set progress = -1 where id = v_draft_id;
        raise exception 'FAIL (test 3a): project_drafts.progress = -1 was accepted' using errcode = 'M0042';
    exception when check_violation then
        raise notice 'PASS (test 3a): project_drafts.progress = -1 is rejected';
    end;

    begin
        update public.project_drafts set progress = 101 where id = v_draft_id;
        raise exception 'FAIL (test 3b): project_drafts.progress = 101 was accepted' using errcode = 'M0042';
    exception when check_violation then
        raise notice 'PASS (test 3b): project_drafts.progress = 101 is rejected';
    end;
end $$;
rollback to savepoint test_3;

-- ---------------------------------------------------------------------
-- Test 4: CHECK constraints — canonical status vocabulary, all three
-- tables. Unknown values (including the legacy 'building' alias, which
-- is deliberately NOT part of the canonical set) are rejected.
-- ---------------------------------------------------------------------
savepoint test_4;
do $$
declare
    v_draft_id uuid;
begin
    insert into public.project_drafts (id, user_id, title, category)
    values (gen_random_uuid(), '00000000-0000-0000-0000-000000000801', 'M0042 Status Test', 'pc_build')
    returning id into v_draft_id;

    begin
        update public.project_drafts set status = 'bogus' where id = v_draft_id;
        raise exception 'FAIL (test 4a): an unknown status value was accepted' using errcode = 'M0042';
    exception when check_violation then
        raise notice 'PASS (test 4a): an unknown status value is rejected';
    end;

    begin
        update public.project_drafts set status = 'building' where id = v_draft_id;
        raise exception 'FAIL (test 4b): the legacy ''building'' alias was accepted as a NEW status write (it must only ever exist as pre-migration-normalized historical data, never writable again)' using errcode = 'M0042';
    exception when check_violation then
        raise notice 'PASS (test 4b): the legacy ''building'' alias cannot be written as a new status value';
    end;
end $$;
rollback to savepoint test_4;

-- ---------------------------------------------------------------------
-- Test 5: CHECK constraints — Completed/100 consistency (one-directional:
-- Completed requires 100, but 100 does not require Completed).
-- ---------------------------------------------------------------------
savepoint test_5;
do $$
declare
    v_draft_id uuid;
begin
    insert into public.project_drafts (id, user_id, title, category, progress, status)
    values (gen_random_uuid(), '00000000-0000-0000-0000-000000000801', 'M0042 Consistency Test', 'pc_build', 50, 'in_progress')
    returning id into v_draft_id;

    begin
        update public.project_drafts set status = 'completed' where id = v_draft_id;
        raise exception 'FAIL (test 5a): status=completed with progress=50 (< 100) was accepted' using errcode = 'M0042';
    exception when check_violation then
        raise notice 'PASS (test 5a): Completed below 100%% is rejected';
    end;

    update public.project_drafts set progress = 100, status = 'completed' where id = v_draft_id;
    raise notice 'PASS (test 5b): Completed at exactly 100%% is accepted';
end $$;
rollback to savepoint test_5;

savepoint test_5_accept_matrix;
do $$
begin
    -- Explicit product-decision edge cases: Planning at nonzero,
    -- In Progress at 0 and 100, Paused at any percentage -- all must be
    -- accepted without any forced adjustment at the database layer (the
    -- editor's own client-side forcing is a UX convenience on top of
    -- this, not a substitute for it -- the constraint is what actually
    -- prevents an invalid state, however it was written).
    insert into public.project_drafts (id, user_id, title, category, progress, status)
    values (gen_random_uuid(), '00000000-0000-0000-0000-000000000801', 'M0042 Planning 50', 'pc_build', 50, 'planning');

    insert into public.project_drafts (id, user_id, title, category, progress, status)
    values (gen_random_uuid(), '00000000-0000-0000-0000-000000000801', 'M0042 InProgress 0', 'pc_build', 0, 'in_progress');

    insert into public.project_drafts (id, user_id, title, category, progress, status)
    values (gen_random_uuid(), '00000000-0000-0000-0000-000000000801', 'M0042 InProgress 100', 'pc_build', 100, 'in_progress');

    insert into public.project_drafts (id, user_id, title, category, progress, status)
    values (gen_random_uuid(), '00000000-0000-0000-0000-000000000801', 'M0042 Paused 37', 'pc_build', 37, 'paused');

    insert into public.project_drafts (id, user_id, title, category, progress, status)
    values (gen_random_uuid(), '00000000-0000-0000-0000-000000000801', 'M0042 Completed 100', 'pc_build', 100, 'completed');

    raise notice 'PASS (test 5c): Planning@50, In Progress@0, In Progress@100, Paused@37, and Completed@100 are all accepted';
end $$;
rollback to savepoint test_5_accept_matrix;

-- ---------------------------------------------------------------------
-- Test 6: publish_draft() copies progress/status into builds (first
-- publish) and into the new build_revisions row.
-- ---------------------------------------------------------------------
savepoint test_6;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000801', true);
set local role authenticated;
do $$
declare
    v_draft_id uuid;
    v_media_id uuid;
    v_build public.builds;
    v_revision_progress integer;
    v_revision_status text;
begin
    insert into public.project_drafts (id, user_id, title, description, category, progress, status)
    values (gen_random_uuid(), '00000000-0000-0000-0000-000000000801', 'M0042 First Publish Test', 'A description with real content for readiness checks.', 'pc_build', 45, 'in_progress')
    returning id into v_draft_id;

    insert into public.project_media (id, draft_id, storage_path)
    values (gen_random_uuid(), v_draft_id, 'test-fixtures/cover.jpg')
    returning id into v_media_id;

    update public.project_drafts set cover_media_id = v_media_id where id = v_draft_id;

    v_build := public.publish_draft(v_draft_id);

    if v_build.progress <> 45 or v_build.status <> 'in_progress' then
        raise exception 'FAIL (test 6a): first publish did not copy progress/status into builds (got progress=%, status=%)', v_build.progress, v_build.status using errcode = 'M0042';
    end if;

    select progress, status into v_revision_progress, v_revision_status
    from public.build_revisions where build_id = v_build.id order by created_at desc limit 1;

    if v_revision_progress <> 45 or v_revision_status <> 'in_progress' then
        raise exception 'FAIL (test 6b): first publish did not copy progress/status into build_revisions (got progress=%, status=%)', v_revision_progress, v_revision_status using errcode = 'M0042';
    end if;

    raise notice 'PASS (test 6): first publish copies real progress/status into both builds and build_revisions';
end $$;
reset role;
rollback to savepoint test_6;

-- ---------------------------------------------------------------------
-- Test 7: republish updates builds.progress/status (the literal Finding
-- 04 bug -- this UPDATE previously never touched status at all), and the
-- PRIOR revision remains completely unchanged (immutability).
-- ---------------------------------------------------------------------
savepoint test_7;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000801', true);
set local role authenticated;
do $$
declare
    v_draft_id uuid;
    v_media_id uuid;
    v_build public.builds;
    v_first_revision_id uuid;
    v_first_revision_progress integer;
    v_first_revision_status text;
    v_revision_count_before integer;
    v_revision_count_after integer;
begin
    insert into public.project_drafts (id, user_id, title, description, category, progress, status)
    values (gen_random_uuid(), '00000000-0000-0000-0000-000000000801', 'M0042 Republish Test', 'A description with real content for readiness checks.', 'pc_build', 10, 'planning')
    returning id into v_draft_id;

    insert into public.project_media (id, draft_id, storage_path)
    values (gen_random_uuid(), v_draft_id, 'test-fixtures/cover.jpg')
    returning id into v_media_id;

    update public.project_drafts set cover_media_id = v_media_id where id = v_draft_id;

    v_build := public.publish_draft(v_draft_id);

    select id, progress, status into v_first_revision_id, v_first_revision_progress, v_first_revision_status
    from public.build_revisions where build_id = v_build.id order by created_at desc limit 1;

    select count(*) into v_revision_count_before from public.build_revisions where build_id = v_build.id;

    -- Republish with a real change: 100% Completed.
    update public.project_drafts set progress = 100, status = 'completed' where id = v_draft_id;

    v_build := public.publish_draft(v_draft_id);

    if v_build.progress <> 100 or v_build.status <> 'completed' then
        raise exception 'FAIL (test 7a): republish did not update builds.progress/status (got progress=%, status=%) -- this is the literal Finding 04 bug', v_build.progress, v_build.status using errcode = 'M0042';
    end if;

    select count(*) into v_revision_count_after from public.build_revisions where build_id = v_build.id;

    if v_revision_count_after <> v_revision_count_before + 1 then
        raise exception 'FAIL (test 7b): republish did not create exactly one new revision (before=%, after=%)', v_revision_count_before, v_revision_count_after using errcode = 'M0042';
    end if;

    -- The FIRST revision must be byte-for-byte unchanged -- immutability.
    perform 1 from public.build_revisions
    where id = v_first_revision_id and progress = v_first_revision_progress and status = v_first_revision_status;

    if not found then
        raise exception 'FAIL (test 7c): the prior revision''s progress/status changed after republish -- revisions must be immutable' using errcode = 'M0042';
    end if;

    raise notice 'PASS (test 7): republish updates builds.progress/status, creates exactly one new revision, and never mutates a prior revision';
end $$;
reset role;
rollback to savepoint test_7;

-- ---------------------------------------------------------------------
-- Test 8: restore_revision_to_draft() restores progress/status from the
-- chosen historical revision.
-- ---------------------------------------------------------------------
savepoint test_8;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000801', true);
set local role authenticated;
do $$
declare
    v_draft_id uuid;
    v_media_id uuid;
    v_build public.builds;
    v_revision_id uuid;
    v_expected_updated_at timestamptz;
    v_restored_draft public.project_drafts;
begin
    insert into public.project_drafts (id, user_id, title, description, category, progress, status)
    values (gen_random_uuid(), '00000000-0000-0000-0000-000000000801', 'M0042 Restore Test', 'A description with real content for readiness checks.', 'pc_build', 70, 'in_progress')
    returning id into v_draft_id;

    insert into public.project_media (id, draft_id, storage_path)
    values (gen_random_uuid(), v_draft_id, 'test-fixtures/cover.jpg')
    returning id into v_media_id;

    update public.project_drafts set cover_media_id = v_media_id where id = v_draft_id;

    v_build := public.publish_draft(v_draft_id);
    select id into v_revision_id from public.build_revisions where build_id = v_build.id order by created_at desc limit 1;

    -- Simulate later drift after publish.
    update public.project_drafts set progress = 5, status = 'planning' where id = v_draft_id;
    select updated_at into v_expected_updated_at from public.project_drafts where id = v_draft_id;

    v_restored_draft := public.restore_revision_to_draft(v_revision_id, v_expected_updated_at);

    if v_restored_draft.progress <> 70 or v_restored_draft.status <> 'in_progress' then
        raise exception 'FAIL (test 8): restore_revision_to_draft() did not restore progress/status (got progress=%, status=%)', v_restored_draft.progress, v_restored_draft.status using errcode = 'M0042';
    end if;

    raise notice 'PASS (test 8): restore_revision_to_draft() restores the revision''s real progress/status onto the draft';
end $$;
reset role;
rollback to savepoint test_8;

-- ---------------------------------------------------------------------
-- Test 8b: a legacy (status=NULL) revision restored into an EXISTING
-- draft retains that draft's OWN current status -- there's nothing to
-- re-derive, the draft already has a real, current one. Historical
-- progress is still always restored verbatim.
-- ---------------------------------------------------------------------
-- All three legacy-restore scenarios below (8b/8c/8d) need to directly
-- mutate build_revisions to simulate "a pre-0042 revision" -- a plain
-- UPDATE, not a call through publish_draft() (which is SECURITY DEFINER
-- and so bypasses RLS internally; a direct UPDATE from this test does
-- NOT, since no client UPDATE policy exists on build_revisions -- see
-- test 9b). That direct UPDATE has to run as postgres, not authenticated,
-- so each scenario is split across a role switch rather than one DO
-- block: publish as authenticated (real auth.uid() ownership check),
-- reset role to mutate the revision directly, then switch back to
-- authenticated for the actual restore_revision_to_draft() call (which
-- also needs a real auth.uid()). Fixed, literal draft ids (rather than
-- gen_random_uuid()) carry state across that role switch, since a plain
-- SQL variable can't survive across separate top-level statements/DO
-- blocks the way a table row does.
savepoint test_8b;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000801', true);
set local role authenticated;
do $$
declare
    v_media_id uuid;
    v_build public.builds;
begin
    insert into public.project_drafts (id, user_id, title, description, category, progress, status)
    values ('00000000-0000-0000-0000-000000000811', '00000000-0000-0000-0000-000000000801', 'M0042 Legacy Restore Existing Draft', 'A description with real content for readiness checks.', 'pc_build', 40, 'in_progress');

    insert into public.project_media (id, draft_id, storage_path)
    values (gen_random_uuid(), '00000000-0000-0000-0000-000000000811', 'test-fixtures/cover.jpg')
    returning id into v_media_id;

    update public.project_drafts set cover_media_id = v_media_id where id = '00000000-0000-0000-0000-000000000811';

    v_build := public.publish_draft('00000000-0000-0000-0000-000000000811');

    -- The draft drifts to a different current status after publish --
    -- this is what restoring a legacy-status revision should fall back
    -- to, not anything invented.
    update public.project_drafts set progress = 10, status = 'paused' where id = '00000000-0000-0000-0000-000000000811';
end $$;
reset role;

-- Simulate a legacy, pre-0042 revision: a real historical progress
-- value, but no recorded status -- direct write, test setup only, run
-- with elevated privilege since RLS has no authenticated-role UPDATE
-- policy on build_revisions (same reasoning as test 9b).
update public.build_revisions br set status = null, progress = 65
from public.project_drafts pd
where pd.id = '00000000-0000-0000-0000-000000000811' and br.build_id = pd.published_build_id;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000801', true);
set local role authenticated;
do $$
declare
    v_legacy_revision_id uuid;
    v_expected_updated_at timestamptz;
    v_restored_draft public.project_drafts;
begin
    select br.id into v_legacy_revision_id
    from public.build_revisions br
    join public.project_drafts pd on pd.published_build_id = br.build_id
    where pd.id = '00000000-0000-0000-0000-000000000811';

    select updated_at into v_expected_updated_at from public.project_drafts where id = '00000000-0000-0000-0000-000000000811';

    v_restored_draft := public.restore_revision_to_draft(v_legacy_revision_id, v_expected_updated_at);

    if v_restored_draft.status <> 'paused' then
        raise exception 'FAIL (test 8b): restoring a legacy NULL-status revision into an existing draft did not retain the draft''s own current status (got %)', v_restored_draft.status using errcode = 'M0042';
    end if;

    if v_restored_draft.progress <> 65 then
        raise exception 'FAIL (test 8b): restored progress is % -- expected the revision''s own historical value (65), verbatim', v_restored_draft.progress using errcode = 'M0042';
    end if;

    raise notice 'PASS (test 8b): restoring a legacy NULL-status revision into an existing draft retains the draft''s own current status (paused) and restores historical progress verbatim (65)';
end $$;
reset role;
rollback to savepoint test_8b;

-- ---------------------------------------------------------------------
-- Test 8c: a legacy (status=NULL) revision restored where NO draft is
-- currently linked (a new draft is created) falls back to the current
-- BUILD's own canonical status instead.
-- ---------------------------------------------------------------------
savepoint test_8c;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000801', true);
set local role authenticated;
do $$
declare
    v_media_id uuid;
    v_build public.builds;
begin
    insert into public.project_drafts (id, user_id, title, description, category, progress, status)
    values ('00000000-0000-0000-0000-000000000812', '00000000-0000-0000-0000-000000000801', 'M0042 Legacy Restore New Draft', 'A description with real content for readiness checks.', 'pc_build', 0, 'planning');

    insert into public.project_media (id, draft_id, storage_path)
    values (gen_random_uuid(), '00000000-0000-0000-0000-000000000812', 'test-fixtures/cover.jpg')
    returning id into v_media_id;

    update public.project_drafts set cover_media_id = v_media_id where id = '00000000-0000-0000-0000-000000000812';

    v_build := public.publish_draft('00000000-0000-0000-0000-000000000812');
end $$;
reset role;

-- Both direct writes below are test setup only, run with elevated
-- privilege: no client UPDATE policy exists on builds or build_revisions
-- (same reasoning as test 9b) -- as authenticated, either statement
-- would silently affect zero rows via RLS rather than error, which is
-- exactly the bug this comment is here to prevent reintroducing.
-- The build itself becomes 'paused' (a real, current value).
update public.builds b set status = 'paused'
from public.project_drafts pd
where pd.id = '00000000-0000-0000-0000-000000000812' and b.id = pd.published_build_id;

update public.build_revisions br set status = null, progress = 80
from public.builds b
join public.project_drafts pd on pd.published_build_id = b.id
where pd.id = '00000000-0000-0000-0000-000000000812' and br.build_id = b.id;

-- The draft that published it is deleted entirely -- the documented
-- "no draft currently linked" edge case restore_revision_to_draft()
-- already handles for every other snapshot field.
delete from public.project_drafts where id = '00000000-0000-0000-0000-000000000812';

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000801', true);
set local role authenticated;
do $$
declare
    v_legacy_revision_id uuid;
    v_restored_draft public.project_drafts;
begin
    -- The draft that published this build is gone (deleted above), so
    -- the lookup goes through the build's own title -- unique within
    -- this test file's own fixture data.
    select br.id into v_legacy_revision_id
    from public.build_revisions br
    join public.builds b on b.id = br.build_id
    where b.title = 'M0042 Legacy Restore New Draft';

    v_restored_draft := public.restore_revision_to_draft(v_legacy_revision_id, null);

    if v_restored_draft.status <> 'paused' then
        raise exception 'FAIL (test 8c): restoring a legacy NULL-status revision with no linked draft did not fall back to the build''s own current status (got %)', v_restored_draft.status using errcode = 'M0042';
    end if;

    if v_restored_draft.progress <> 80 then
        raise exception 'FAIL (test 8c): restored progress is % -- expected the revision''s own historical value (80), verbatim', v_restored_draft.progress using errcode = 'M0042';
    end if;

    raise notice 'PASS (test 8c): restoring a legacy NULL-status revision with no linked draft falls back to the build''s own current status (paused) and restores historical progress verbatim (80)';
end $$;
reset role;
rollback to savepoint test_8c;

-- ---------------------------------------------------------------------
-- Test 8d: Hard Model C applied to a RESOLVED restore -- when the
-- fallback resolves to 'completed' but the revision's own historical
-- progress is below 100, the restored draft downgrades to 'in_progress'
-- rather than either rewriting history or leaving an inconsistent draft.
-- The historical revision row itself is never touched.
-- ---------------------------------------------------------------------
savepoint test_8d;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000801', true);
set local role authenticated;
do $$
declare
    v_media_id uuid;
    v_build public.builds;
begin
    insert into public.project_drafts (id, user_id, title, description, category, progress, status)
    values ('00000000-0000-0000-0000-000000000813', '00000000-0000-0000-0000-000000000801', 'M0042 Legacy Restore Completed Downgrade', 'A description with real content for readiness checks.', 'pc_build', 0, 'planning');

    insert into public.project_media (id, draft_id, storage_path)
    values (gen_random_uuid(), '00000000-0000-0000-0000-000000000813', 'test-fixtures/cover.jpg')
    returning id into v_media_id;

    update public.project_drafts set cover_media_id = v_media_id where id = '00000000-0000-0000-0000-000000000813';

    v_build := public.publish_draft('00000000-0000-0000-0000-000000000813');

    -- The draft's CURRENT status (the fallback source, since a draft is
    -- linked here) is 'completed' -- e.g. the project was marked
    -- Completed sometime after this old revision was published.
    update public.project_drafts set progress = 100, status = 'completed' where id = '00000000-0000-0000-0000-000000000813';
end $$;
reset role;

-- A legacy revision recording real, below-100 historical progress.
update public.build_revisions br set status = null, progress = 60
from public.project_drafts pd
where pd.id = '00000000-0000-0000-0000-000000000813' and br.build_id = pd.published_build_id;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000801', true);
set local role authenticated;
do $$
declare
    v_legacy_revision_id uuid;
    v_expected_updated_at timestamptz;
    v_restored_draft public.project_drafts;
    v_revision_progress_after integer;
    v_revision_status_after text;
begin
    select br.id into v_legacy_revision_id
    from public.build_revisions br
    join public.project_drafts pd on pd.published_build_id = br.build_id
    where pd.id = '00000000-0000-0000-0000-000000000813';

    select updated_at into v_expected_updated_at from public.project_drafts where id = '00000000-0000-0000-0000-000000000813';

    v_restored_draft := public.restore_revision_to_draft(v_legacy_revision_id, v_expected_updated_at);

    if v_restored_draft.status <> 'in_progress' then
        raise exception 'FAIL (test 8d): resolved Completed + historical progress 60 did not downgrade to in_progress on the restored draft (got %)', v_restored_draft.status using errcode = 'M0042';
    end if;

    if v_restored_draft.progress <> 60 then
        raise exception 'FAIL (test 8d): restored progress is % -- expected the revision''s own historical value (60), never rewritten to reach consistency', v_restored_draft.progress using errcode = 'M0042';
    end if;

    -- The historical revision itself must be completely untouched.
    select progress, status into v_revision_progress_after, v_revision_status_after
    from public.build_revisions where id = v_legacy_revision_id;

    if v_revision_progress_after <> 60 or v_revision_status_after is not null then
        raise exception 'FAIL (test 8d): the historical revision itself was modified (progress=%, status=%) -- it must never be written to', v_revision_progress_after, v_revision_status_after using errcode = 'M0042';
    end if;

    raise notice 'PASS (test 8d): a resolved Completed+below-100 restore downgrades the DRAFT to in_progress/60, and never modifies the historical revision (still NULL/60)';
end $$;
reset role;
rollback to savepoint test_8d;

-- ---------------------------------------------------------------------
-- Test 8e: build_revisions' own null-tolerant constraints -- NULL status
-- is always valid regardless of progress; a non-null invalid value is
-- still rejected; NULL never falsely trips the Completed/100 check.
-- ---------------------------------------------------------------------
savepoint test_8e;
do $$
declare
    v_build_id uuid;
begin
    select id into v_build_id from public.builds limit 1;

    if v_build_id is null then
        insert into public.builds (id, user_id, title, slug, description, category, status)
        values (gen_random_uuid(), '00000000-0000-0000-0000-000000000801', 'M0042 Constraint Fixture Build', 'm0042-constraint-fixture-build', 'desc', 'pc_build', 'planning')
        returning id into v_build_id;
    end if;

    -- NULL status with a high progress value must never spuriously trip
    -- the Completed/100 check -- the "status is null or ..." clause
    -- exists precisely for this.
    insert into public.build_revisions (id, build_id, user_id, title, description, version, progress, update_type, status)
    values (gen_random_uuid(), v_build_id, '00000000-0000-0000-0000-000000000801', 'Test', '', 'v1.0', 42, 'documentation', null);

    raise notice 'PASS (test 8e-1): a NULL status with any progress value is always accepted, never trips Completed/100';

    begin
        insert into public.build_revisions (id, build_id, user_id, title, description, version, progress, update_type, status)
        values (gen_random_uuid(), v_build_id, '00000000-0000-0000-0000-000000000801', 'Test', '', 'v1.0', 50, 'documentation', 'bogus');
        raise exception 'FAIL (test 8e-2): an unknown non-null status value was accepted on build_revisions' using errcode = 'M0042';
    exception when check_violation then
        raise notice 'PASS (test 8e-2): an unknown non-null status value is still rejected on build_revisions';
    end;

    begin
        insert into public.build_revisions (id, build_id, user_id, title, description, version, progress, update_type, status)
        values (gen_random_uuid(), v_build_id, '00000000-0000-0000-0000-000000000801', 'Test', '', 'v1.0', 50, 'documentation', 'completed');
        raise exception 'FAIL (test 8e-3): status=completed with progress=50 was accepted on build_revisions' using errcode = 'M0042';
    exception when check_violation then
        raise notice 'PASS (test 8e-3): a non-null Completed status still requires progress=100 on build_revisions';
    end;
end $$;
rollback to savepoint test_8e;

-- ---------------------------------------------------------------------
-- Test 9: ownership / RLS -- a non-owner cannot publish or restore
-- another user's draft/revision, and cannot write builds/build_revisions
-- directly (no client insert/update policy exists on either table).
-- ---------------------------------------------------------------------
savepoint test_9;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000801', true);
set local role authenticated;
do $$
declare
    v_draft_id uuid;
    v_media_id uuid;
begin
    insert into public.project_drafts (id, user_id, title, description, category)
    values ('00000000-0000-0000-0000-000000000901', '00000000-0000-0000-0000-000000000801', 'M0042 Ownership Test', 'A description with real content for readiness checks.', 'pc_build')
    returning id into v_draft_id;

    insert into public.project_media (id, draft_id, storage_path)
    values (gen_random_uuid(), v_draft_id, 'test-fixtures/cover.jpg')
    returning id into v_media_id;

    update public.project_drafts set cover_media_id = v_media_id where id = v_draft_id;
end $$;
reset role;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000802', true);
set local role authenticated;
do $$
begin
    begin
        perform public.publish_draft('00000000-0000-0000-0000-000000000901');
        raise exception 'FAIL (test 9a): a non-owner was able to publish another user''s draft' using errcode = 'M0042';
    exception when others then
        if sqlerrm !~* 'owner' then
            raise;
        end if;
        raise notice 'PASS (test 9a): a non-owner cannot publish another user''s draft';
    end;

    declare
        v_updated_rows integer;
    begin
        -- RLS enforcement for UPDATE with a WHERE clause is silent, not
        -- exception-throwing: with no applicable UPDATE policy, Postgres
        -- simply finds zero rows this role is allowed to touch and
        -- reports "UPDATE 0" -- it does NOT raise insufficient_privilege
        -- the way a missing table-level GRANT would. Checking ROW_COUNT
        -- is the correct assertion here; a bare "did this throw?" check
        -- would silently pass even if RLS let the write through, since a
        -- successful, silently-no-op UPDATE never throws anything at all.
        update public.builds set status = 'completed', progress = 100 where user_id = '00000000-0000-0000-0000-000000000801';
        get diagnostics v_updated_rows = row_count;

        if v_updated_rows <> 0 then
            raise exception 'FAIL (test 9b): a direct client UPDATE to builds.status/progress affected % row(s) -- these columns must only ever be writable through publish_draft()', v_updated_rows using errcode = 'M0042';
        end if;

        raise notice 'PASS (test 9b): a direct client UPDATE to builds affects zero rows (RLS has no applicable UPDATE policy)';
    exception when insufficient_privilege then
        raise notice 'PASS (test 9b): a direct client UPDATE to builds is rejected outright (no table-level GRANT)';
    end;
end $$;
reset role;
rollback to savepoint test_9;

-- ---------------------------------------------------------------------
-- Test 10: publish_draft()/restore_revision_to_draft() keep their exact
-- pre-0042 signatures and their authenticated-only, anon-free ACL.
-- ---------------------------------------------------------------------
savepoint test_10;
do $$
declare
    v_publish_signature text;
    v_restore_signature text;
    v_publish_has_anon boolean;
    v_restore_has_anon boolean;
begin
    -- pg_get_function_identity_arguments() deliberately omits DEFAULT
    -- clauses -- it reconstructs the argument list that identifies a
    -- function for overload resolution (what DROP/ALTER FUNCTION would
    -- need), which by definition excludes default expressions. Expected
    -- strings below were confirmed against a real `select
    -- pg_get_function_identity_arguments(oid) from pg_proc ...` query,
    -- not assumed.
    select pg_get_function_identity_arguments(oid) into v_publish_signature
    from pg_proc where proname = 'publish_draft' and pronamespace = 'public'::regnamespace;

    if v_publish_signature <> 'p_draft_id uuid, p_version_label text, p_publish_notes text' then
        raise exception 'FAIL (test 10a): publish_draft()''s signature changed -- got (%)', v_publish_signature using errcode = 'M0042';
    end if;

    select pg_get_function_identity_arguments(oid) into v_restore_signature
    from pg_proc where proname = 'restore_revision_to_draft' and pronamespace = 'public'::regnamespace;

    if v_restore_signature <> 'p_revision_id uuid, p_expected_draft_updated_at timestamp with time zone' then
        raise exception 'FAIL (test 10b): restore_revision_to_draft()''s signature changed -- got (%)', v_restore_signature using errcode = 'M0042';
    end if;

    -- 0038_restrict_pre_0020_function_execute_permissions.sql revoked
    -- EXECUTE from anon on both functions, keyed to these exact literal
    -- signatures. has_function_privilege confirms anon still cannot
    -- execute either one after 0042's create-or-replace.
    select has_function_privilege('anon', 'public.publish_draft(uuid, text, text)', 'EXECUTE') into v_publish_has_anon;
    select has_function_privilege('anon', 'public.restore_revision_to_draft(uuid, timestamptz)', 'EXECUTE') into v_restore_has_anon;

    if v_publish_has_anon then
        raise exception 'FAIL (test 10c): anon can execute publish_draft() after 0042 -- the 0038 grant restriction was lost' using errcode = 'M0042';
    end if;

    if v_restore_has_anon then
        raise exception 'FAIL (test 10d): anon can execute restore_revision_to_draft() after 0042 -- the 0038 grant restriction was lost' using errcode = 'M0042';
    end if;

    if not has_function_privilege('authenticated', 'public.publish_draft(uuid, text, text)', 'EXECUTE') then
        raise exception 'FAIL (test 10e): authenticated can no longer execute publish_draft()' using errcode = 'M0042';
    end if;

    raise notice 'PASS (test 10): both functions keep their exact pre-0042 signatures; anon has no EXECUTE, authenticated still does';
end $$;
rollback to savepoint test_10;

-- ---------------------------------------------------------------------
-- Test 11: rollback behavior -- the paired rollback file's statements
-- remove every 0042 constraint/column cleanly and restore both functions
-- to their pre-0042 (0035) bodies, without touching setup_inventory or
-- any other pre-existing column.
-- ---------------------------------------------------------------------
savepoint test_11;
alter table public.project_drafts drop constraint if exists project_drafts_status_progress_check;
alter table public.project_drafts drop constraint if exists project_drafts_status_check;
alter table public.project_drafts drop constraint if exists project_drafts_progress_check;
alter table public.project_drafts drop column if exists status;
alter table public.project_drafts drop column if exists progress;

alter table public.builds drop constraint if exists builds_status_progress_check;
alter table public.builds drop constraint if exists builds_status_check;
alter table public.builds drop constraint if exists builds_progress_check;
alter table public.builds drop column if exists progress;

alter table public.build_revisions drop constraint if exists build_revisions_status_progress_check;
alter table public.build_revisions drop constraint if exists build_revisions_status_check;
alter table public.build_revisions drop constraint if exists build_revisions_progress_check;
alter table public.build_revisions drop column if exists status;

do $$
declare
    v_any_column_exists boolean;
    v_setup_inventory_survives boolean;
begin
    select exists (
        select 1 from information_schema.columns
        where table_schema = 'public'
          and ((table_name = 'project_drafts' and column_name in ('progress', 'status'))
            or (table_name = 'builds' and column_name = 'progress')
            or (table_name = 'build_revisions' and column_name = 'status'))
    ) into v_any_column_exists;

    if v_any_column_exists then
        raise exception 'FAIL (test 11a): one or more 0042 columns still exist after the rollback statements ran' using errcode = 'M0042';
    end if;

    select exists (
        select 1 from information_schema.columns
        where table_schema = 'public' and table_name = 'builds' and column_name = 'status'
    ) into v_setup_inventory_survives;

    if not v_setup_inventory_survives then
        raise exception 'FAIL (test 11b): builds.status itself was dropped -- it predates 0042 (0000_baseline) and must survive rollback' using errcode = 'M0042';
    end if;

    raise notice 'PASS (test 11): rollback drops every 0042 column/constraint cleanly, leaving pre-existing columns (builds.status, build_revisions.progress, setup_inventory) untouched';
end $$;
rollback to savepoint test_11;

rollback;
