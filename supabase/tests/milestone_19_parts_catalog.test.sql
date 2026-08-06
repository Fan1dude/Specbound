-- Milestone 19 SQL test suite — supabase/tests/milestone_19_parts_catalog.test.sql
--
-- Covers the six scenarios called out in the SQL/security audit:
-- duplicate normalization, alias conflicts, unauthorized approval,
-- repeated approval, withdrawal rules, and rejection. See
-- docs/milestones/MILESTONE_19_SQL_SECURITY_AUDIT.md §4 for the audit
-- this file is evidence for.
--
-- STATUS: written, NOT executed. This implementation environment has no
-- database access (anon-key only) — there is nowhere to run this against.
-- Run it once against a disposable/staging Supabase project (never
-- production) before trusting the result, via the SQL editor or `psql`.
-- Depends on migrations 0001-0023 already being applied there.
--
-- Never run this against a project with real data: it inserts three
-- fake auth.users rows and exercises every write path in 0020-0023. The
-- entire file is wrapped in one transaction that ends in ROLLBACK, so if
-- it runs to completion (or aborts) without a manual COMMIT, none of it
-- persists — but that safety net only helps if nothing outside this
-- transaction observes the intermediate state first.
--
-- auth.users' exact required columns vary by Supabase/GoTrue version —
-- the minimal (id, email) insert below is the commonly-documented
-- pattern but may need adjusting for a given project's schema.
--
-- Each test runs inside its own SAVEPOINT and always rolls back to it
-- afterward (pass or fail) — one test's outcome, expected or not, can
-- never leak into another test's starting state. Failures are reported
-- via RAISE WARNING (visible, but non-aborting) so the whole suite
-- always runs to completion and prints a full pass/fail report, rather
-- than stopping at the first problem.
--
-- Identity simulation follows Supabase's standard pattern for testing
-- RLS/auth.uid() from raw SQL: `set local role authenticated` (so
-- policies scoped `to authenticated` actually apply — the connecting
-- role, typically a superuser/table owner, bypasses RLS by default) plus
-- `set_config('request.jwt.claim.sub', '<uuid>', true)` (what Supabase's
-- auth.uid() reads). `reset role` returns to the original privileged
-- role between tests for fixture setup. Both are issued as plain
-- top-level statements, not from inside a DO block — SET ROLE's
-- behavior when issued from within PL/pgSQL is not something this
-- unexecuted file should gamble on; top-level is unambiguous.

begin;

-- ---------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------

insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000000001', 'm19-moderator@example.invalid'),
    ('00000000-0000-0000-0000-000000000002', 'm19-submitter-a@example.invalid'),
    ('00000000-0000-0000-0000-000000000003', 'm19-submitter-b@example.invalid')
on conflict (id) do nothing;

insert into public.catalog_moderators (user_id, granted_by)
values ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001');

-- Two real, distinct canonical components to test alias/duplicate
-- scenarios against.
insert into public.components (technology_id, field_key, canonical_name, created_by)
values
    ('pc_build', 'gpu', 'RTX 4080', '00000000-0000-0000-0000-000000000001'),
    ('pc_build', 'gpu', 'RTX 4080 Super', '00000000-0000-0000-0000-000000000001');

-- ---------------------------------------------------------------------
-- Test 1: duplicate normalization is rejected at the DB level
-- ---------------------------------------------------------------------
savepoint test_1;
do $$
begin
    begin
        -- "RTX-4080" normalizes to the same "rtx4080" as the seeded
        -- "RTX 4080" — punctuation/spacing only, same real part.
        insert into public.components (technology_id, field_key, canonical_name, created_by)
        values ('pc_build', 'gpu', 'RTX-4080', '00000000-0000-0000-0000-000000000001');

        raise warning 'FAIL (test 1): duplicate-normalized canonical_name was accepted, expected unique_violation';
    exception when unique_violation then
        raise notice 'PASS (test 1): duplicate normalization correctly rejected (%)', sqlerrm;
    end;
end $$;
rollback to savepoint test_1;

-- ---------------------------------------------------------------------
-- Test 2a: alias conflicts — same alias text, same slot, two components
-- ---------------------------------------------------------------------
savepoint test_2a;
do $$
declare
    v_component_a uuid;
    v_component_b uuid;
begin
    select id into v_component_a from public.components where canonical_name = 'RTX 4080';
    select id into v_component_b from public.components where canonical_name = 'RTX 4080 Super';

    insert into public.component_aliases (component_id, alias) values (v_component_a, '4080');

    begin
        insert into public.component_aliases (component_id, alias) values (v_component_b, '4080');
        raise warning 'FAIL (test 2a): duplicate alias text in the same technology/field slot was accepted, expected unique_violation';
    exception when unique_violation then
        raise notice 'PASS (test 2a): duplicate alias text correctly rejected (%)', sqlerrm;
    end;
end $$;
rollback to savepoint test_2a;

-- ---------------------------------------------------------------------
-- Test 2b: alias conflicts — approving a submission as an alias of one
-- component when a DIFFERENT component already canonically owns that
-- exact normalized name (the cross-table guard added in the audit pass,
-- not caught by either table's own unique index alone).
-- ---------------------------------------------------------------------
savepoint test_2b;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
    v_component_b uuid;
    v_submission_id uuid;
begin
    select id into v_component_b from public.components where canonical_name = 'RTX 4080 Super';

    -- Submitted name matches the OTHER seeded component ("RTX 4080")
    -- exactly, not "RTX 4080 Super". Inserted as the moderator here
    -- purely for setup convenience — who submits doesn't matter to this
    -- test, only who approves.
    insert into public.component_submissions (technology_id, field_key, submitted_name, submitted_by)
    values ('pc_build', 'gpu', 'RTX 4080', '00000000-0000-0000-0000-000000000001')
    returning id into v_submission_id;

    begin
        -- Approving as an alias of "RTX 4080 Super" while "RTX 4080"
        -- itself already exists as a separate canonical component.
        perform public.approve_component_submission(v_submission_id, v_component_b);
        raise warning 'FAIL (test 2b): approved as alias despite an existing different canonical owner of that normalized name';
    exception when others then
        if sqlerrm like 'A different component already canonically owns%' then
            raise notice 'PASS (test 2b): cross-table alias/canonical collision correctly rejected (%)', sqlerrm;
        else
            raise warning 'FAIL (test 2b): raised an unexpected error: %', sqlerrm;
        end if;
    end;
end $$;

reset role;
rollback to savepoint test_2b;

-- ---------------------------------------------------------------------
-- Test 2c: alias conflicts — the mirror image of 2b. Approving a
-- submission AS A NEW COMPONENT when its normalized name already exists
-- as an ALIAS of a different, existing component.
-- ---------------------------------------------------------------------
savepoint test_2c;

do $$
declare
    v_component_a uuid;
    v_submission_id uuid;
begin
    select id into v_component_a from public.components where canonical_name = 'RTX 4080';

    insert into public.component_aliases (component_id, alias) values (v_component_a, 'Rtx-4080-Alias-Test');

    insert into public.component_submissions (technology_id, field_key, submitted_name, submitted_by)
    values ('pc_build', 'gpu', 'Rtx 4080 Alias Test', '00000000-0000-0000-0000-000000000002')
    returning id into v_submission_id;

    create temporary table if not exists m19_test_scratch (key text primary key, value uuid);
    insert into m19_test_scratch (key, value) values ('test_2c_submission', v_submission_id)
        on conflict (key) do update set value = excluded.value;
end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
    v_submission_id uuid;
begin
    select value into v_submission_id from m19_test_scratch where key = 'test_2c_submission';

    begin
        -- No alias_of_component_id passed — approving "as new".
        perform public.approve_component_submission(v_submission_id);
        raise warning 'FAIL (test 2c): approved as a new component despite the same normalized text already existing as another component''s alias';
    exception when others then
        if sqlerrm like 'This normalized name is already registered as an alias%' then
            raise notice 'PASS (test 2c): new-component-vs-existing-alias collision correctly rejected (%)', sqlerrm;
        else
            raise warning 'FAIL (test 2c): raised an unexpected error: %', sqlerrm;
        end if;
    end;
end $$;

reset role;
rollback to savepoint test_2c;

-- ---------------------------------------------------------------------
-- Test 3: unauthorized approval — a non-moderator cannot approve
-- ---------------------------------------------------------------------
savepoint test_3;

do $$
declare
    v_submission_id uuid;
begin
    insert into public.component_submissions (technology_id, field_key, submitted_name, submitted_by)
    values ('pc_build', 'cpu', 'Test CPU For Auth Check', '00000000-0000-0000-0000-000000000002')
    returning id into v_submission_id;

    -- Stash the id somewhere the next block (running as a different
    -- role) can still see it within this same transaction.
    create temporary table if not exists m19_test_scratch (key text primary key, value uuid);
    insert into m19_test_scratch (key, value) values ('test_3_submission', v_submission_id)
        on conflict (key) do update set value = excluded.value;
end $$;

-- Submitter B, not a moderator, not even the submitter of this row.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', true);
set local role authenticated;

do $$
declare
    v_submission_id uuid;
begin
    select value into v_submission_id from m19_test_scratch where key = 'test_3_submission';

    begin
        perform public.approve_component_submission(v_submission_id);
        raise warning 'FAIL (test 3): a non-moderator was able to approve a submission';
    exception when others then
        if sqlerrm like 'Only a catalog moderator may approve%' then
            raise notice 'PASS (test 3): unauthorized approval correctly rejected (%)', sqlerrm;
        else
            raise warning 'FAIL (test 3): raised an unexpected error: %', sqlerrm;
        end if;
    end;
end $$;

reset role;
rollback to savepoint test_3;

-- ---------------------------------------------------------------------
-- Test 4: repeated approval — approving twice fails the second time,
-- and the first approval leaves the row in a fully consistent state.
-- ---------------------------------------------------------------------
savepoint test_4;

do $$
declare
    v_submission_id uuid;
begin
    insert into public.component_submissions (technology_id, field_key, submitted_name, submitted_by)
    values ('pc_build', 'cpu', 'Test CPU For Repeat Check', '00000000-0000-0000-0000-000000000002')
    returning id into v_submission_id;

    create temporary table if not exists m19_test_scratch (key text primary key, value uuid);
    insert into m19_test_scratch (key, value) values ('test_4_submission', v_submission_id)
        on conflict (key) do update set value = excluded.value;
end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
    v_submission_id uuid;
    v_component_id uuid;
    v_status text;
    v_resolved_component_id uuid;
    v_moderator_id uuid;
    v_reviewed_at timestamptz;
begin
    select value into v_submission_id from m19_test_scratch where key = 'test_4_submission';

    v_component_id := public.approve_component_submission(v_submission_id);

    select status, resolved_component_id, moderator_id, reviewed_at
        into v_status, v_resolved_component_id, v_moderator_id, v_reviewed_at
        from public.component_submissions
        where id = v_submission_id;

    if v_status = 'approved'
        and v_resolved_component_id = v_component_id
        and v_moderator_id = '00000000-0000-0000-0000-000000000001'
        and v_reviewed_at is not null
    then
        raise notice 'PASS (test 4a): first approval left the submission in a fully consistent approved state';
    else
        raise warning 'FAIL (test 4a): submission state after approval was inconsistent (status=%, resolved=%, moderator=%, reviewed_at=%)',
            v_status, v_resolved_component_id, v_moderator_id, v_reviewed_at;
    end if;

    begin
        perform public.approve_component_submission(v_submission_id);
        raise warning 'FAIL (test 4b): the same submission was approved a second time';
    exception when others then
        if sqlerrm like '%not found or already resolved%' then
            raise notice 'PASS (test 4b): repeated approval correctly rejected (%)', sqlerrm;
        else
            raise warning 'FAIL (test 4b): raised an unexpected error: %', sqlerrm;
        end if;
    end;
end $$;

reset role;
rollback to savepoint test_4;

-- ---------------------------------------------------------------------
-- Test 5: withdrawal rules — a submitter may delete their own PENDING
-- submission, but not another user's, and not their own once resolved.
-- ---------------------------------------------------------------------
savepoint test_5;

-- 5a: the submitter withdraws their own pending submission.
do $$
declare
    v_pending_id uuid;
begin
    insert into public.component_submissions (technology_id, field_key, submitted_name, submitted_by)
    values ('pc_build', 'cpu', 'Test CPU For Withdrawal Check', '00000000-0000-0000-0000-000000000002')
    returning id into v_pending_id;

    create temporary table if not exists m19_test_scratch (key text primary key, value uuid);
    insert into m19_test_scratch (key, value) values ('test_5a_submission', v_pending_id)
        on conflict (key) do update set value = excluded.value;
end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
    v_pending_id uuid;
    v_deleted_count integer;
begin
    select value into v_pending_id from m19_test_scratch where key = 'test_5a_submission';

    delete from public.component_submissions where id = v_pending_id;
    get diagnostics v_deleted_count = row_count;

    if v_deleted_count = 1 then
        raise notice 'PASS (test 5a): submitter successfully withdrew their own pending submission';
    else
        raise warning 'FAIL (test 5a): expected 1 row deleted, got %', v_deleted_count;
    end if;
end $$;

reset role;

-- 5b: a different user cannot withdraw someone else's pending submission.
do $$
declare
    v_pending_id uuid;
begin
    insert into public.component_submissions (technology_id, field_key, submitted_name, submitted_by)
    values ('pc_build', 'cpu', 'Test CPU For Withdrawal Check 2', '00000000-0000-0000-0000-000000000002')
    returning id into v_pending_id;

    insert into m19_test_scratch (key, value) values ('test_5b_submission', v_pending_id)
        on conflict (key) do update set value = excluded.value;
end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', true);
set local role authenticated;

do $$
declare
    v_pending_id uuid;
    v_deleted_count integer;
begin
    select value into v_pending_id from m19_test_scratch where key = 'test_5b_submission';

    delete from public.component_submissions where id = v_pending_id;
    get diagnostics v_deleted_count = row_count;

    if v_deleted_count = 0 then
        raise notice 'PASS (test 5b): a different user could not withdraw someone else''s pending submission';
    else
        raise warning 'FAIL (test 5b): expected 0 rows deleted, got %', v_deleted_count;
    end if;
end $$;

reset role;

-- 5c: the submitter cannot withdraw their own submission once resolved.
do $$
declare
    v_resolved_id uuid;
begin
    insert into public.component_submissions (technology_id, field_key, submitted_name, submitted_by)
    values ('pc_build', 'cpu', 'Test CPU For Withdrawal Check 3', '00000000-0000-0000-0000-000000000002')
    returning id into v_resolved_id;

    insert into m19_test_scratch (key, value) values ('test_5c_submission', v_resolved_id)
        on conflict (key) do update set value = excluded.value;
end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
    v_resolved_id uuid;
begin
    select value into v_resolved_id from m19_test_scratch where key = 'test_5c_submission';
    perform public.reject_component_submission(v_resolved_id, 'test rejection for withdrawal check');
end $$;

reset role;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
    v_resolved_id uuid;
    v_deleted_count integer;
begin
    select value into v_resolved_id from m19_test_scratch where key = 'test_5c_submission';

    delete from public.component_submissions where id = v_resolved_id;
    get diagnostics v_deleted_count = row_count;

    if v_deleted_count = 0 then
        raise notice 'PASS (test 5c): submitter could not withdraw their own already-resolved submission';
    else
        raise warning 'FAIL (test 5c): expected 0 rows deleted, got %', v_deleted_count;
    end if;
end $$;

reset role;
rollback to savepoint test_5;

-- ---------------------------------------------------------------------
-- Test 6: rejection — leaves a fully consistent rejected state (no
-- resolved_component_id), and cannot be repeated.
-- ---------------------------------------------------------------------
savepoint test_6;

do $$
declare
    v_submission_id uuid;
begin
    insert into public.component_submissions (technology_id, field_key, submitted_name, submitted_by)
    values ('pc_build', 'cpu', 'Test CPU For Rejection Check', '00000000-0000-0000-0000-000000000002')
    returning id into v_submission_id;

    create temporary table if not exists m19_test_scratch (key text primary key, value uuid);
    insert into m19_test_scratch (key, value) values ('test_6_submission', v_submission_id)
        on conflict (key) do update set value = excluded.value;
end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
    v_submission_id uuid;
    v_status text;
    v_resolved_component_id uuid;
    v_moderator_id uuid;
    v_reviewed_at timestamptz;
    v_moderator_note text;
begin
    select value into v_submission_id from m19_test_scratch where key = 'test_6_submission';

    perform public.reject_component_submission(v_submission_id, 'spam');

    select status, resolved_component_id, moderator_id, reviewed_at, moderator_note
        into v_status, v_resolved_component_id, v_moderator_id, v_reviewed_at, v_moderator_note
        from public.component_submissions
        where id = v_submission_id;

    if v_status = 'rejected'
        and v_resolved_component_id is null
        and v_moderator_id = '00000000-0000-0000-0000-000000000001'
        and v_reviewed_at is not null
        and v_moderator_note = 'spam'
    then
        raise notice 'PASS (test 6a): rejection left a fully consistent rejected state';
    else
        raise warning 'FAIL (test 6a): submission state after rejection was inconsistent (status=%, resolved=%, moderator=%, reviewed_at=%, note=%)',
            v_status, v_resolved_component_id, v_moderator_id, v_reviewed_at, v_moderator_note;
    end if;

    begin
        perform public.reject_component_submission(v_submission_id, 'spam again');
        raise warning 'FAIL (test 6b): the same submission was rejected a second time';
    exception when others then
        if sqlerrm like '%not found or already resolved%' then
            raise notice 'PASS (test 6b): repeated rejection correctly rejected (%)', sqlerrm;
        else
            raise warning 'FAIL (test 6b): raised an unexpected error: %', sqlerrm;
        end if;
    end;
end $$;

reset role;
rollback to savepoint test_6;

-- ---------------------------------------------------------------------
-- Nothing in this file should persist. Review the NOTICE/WARNING output
-- above for the pass/fail report, then roll back.
-- ---------------------------------------------------------------------
rollback;
