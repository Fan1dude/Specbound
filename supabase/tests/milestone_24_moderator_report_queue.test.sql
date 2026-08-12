-- Milestone 24 SQL test suite — supabase/tests/milestone_24_moderator_report_queue.test.sql
--
-- Milestone 24 (Moderator Report Queue) adds no migration — the schema
-- and RPCs it relies on (content_reports, moderation_actions,
-- resolve_report(), is_platform_moderator()) already shipped in
-- supabase/migrations/0028_moderation.sql (Milestone 22) and
-- 0027_profile_roles.sql, but had ZERO existing SQL test coverage before
-- this file (confirmed by grep across supabase/tests/ — only
-- migration_0033_function_execute_permissions.test.sql references these
-- functions at all, and only for their EXECUTE grants, not their actual
-- RLS/business-logic behavior). This suite exists specifically to prove
-- the read and resolution paths this milestone's frontend now depends
-- on, per the task's own requirement to run DB/RLS tests when existing
-- coverage doesn't already prove them.
--
-- STATUS: executed against the disposable local Supabase/Docker stack
-- for this repository (never production) — see this milestone's final
-- report for the actual `psql` run and its output. Depends on migrations
-- 0000-0035 already being applied there (confirmed: `supabase migration
-- list --local` shows 0000-0035 present before this file was run).
--
-- Never run this against a project with real data: it inserts three
-- fake auth.users rows, a profile_roles row, and a content_reports row.
-- The entire file is wrapped in one transaction that ends in ROLLBACK.
--
-- Same identity-simulation convention as every other suite in this
-- directory (milestone_19_parts_catalog.test.sql /
-- milestone_22_profile_roles_visibility.test.sql): `set local role
-- authenticated` + `set_config('request.jwt.claim.sub', ...)` for
-- auth.uid(), `set local role anon` with no claim for a signed-out
-- caller, both issued top-level (never from inside a `do $$` block),
-- `reset role` between tests to return to the privileged connecting role
-- for fixture setup. Each test runs inside its own SAVEPOINT and always
-- rolls back to it afterward, pass or fail.

begin;

-- ---------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------

insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-0000-0000-000000000201', 'm24-alice@example.invalid', '{"username": "m24_alice_test"}'::jsonb),
    ('00000000-0000-0000-0000-000000000202', 'm24-bob@example.invalid', '{"username": "m24_bob_test"}'::jsonb),
    ('00000000-0000-0000-0000-000000000203', 'm24-mod@example.invalid', '{"username": "m24_mod_test"}'::jsonb)
on conflict (id) do nothing;

insert into public.profile_roles (user_id, role, granted_by)
values ('00000000-0000-0000-0000-000000000203', 'moderator', '00000000-0000-0000-0000-000000000203');

-- ---------------------------------------------------------------------
-- Test 1: report_content() — the existing submission flow (ReportButton.js)
-- — still works exactly as before. alice reports bob's profile.
-- ---------------------------------------------------------------------
savepoint test_1;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000201', true);
set local role authenticated;
do $$
declare
    v_report public.content_reports;
begin
    select * into v_report from public.report_content('profile', '00000000-0000-0000-0000-000000000202', 'm24 test: inappropriate profile content');

    if v_report.status = 'open'
        and v_report.reporter_id = '00000000-0000-0000-0000-000000000201'
        and v_report.target_type = 'profile'
        and v_report.target_id = '00000000-0000-0000-0000-000000000202' then
        raise notice 'PASS (test 1): report_content() creates an open report exactly as before';
    else
        raise warning 'FAIL (test 1): unexpected report row: status=%, reporter_id=%, target_type=%, target_id=%',
            v_report.status, v_report.reporter_id, v_report.target_type, v_report.target_id;
    end if;
end $$;
reset role;
-- Deliberately NOT rolled back to the savepoint — every later test in
-- this file needs this report row to exist, same "build up fixture
-- state across tests, one shared rollback at the very end" pattern the
-- Milestone 19 suite uses for its own multi-step approval flow.

-- ---------------------------------------------------------------------
-- Test 2: the reporter (alice) can see her own report via direct SELECT
-- ---------------------------------------------------------------------
savepoint test_2;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000201', true);
set local role authenticated;
do $$
declare
    v_count int;
begin
    select count(*) into v_count
    from public.content_reports
    where reporter_id = '00000000-0000-0000-0000-000000000201'
        and target_id = '00000000-0000-0000-0000-000000000202';

    if v_count = 1 then
        raise notice 'PASS (test 2): the reporter sees her own report via direct SELECT';
    else
        raise warning 'FAIL (test 2): reporter saw % row(s), expected 1', v_count;
    end if;
end $$;
reset role;
rollback to savepoint test_2;

-- ---------------------------------------------------------------------
-- Test 3: an unrelated ordinary user (bob — who is also the REPORTED
-- target, proving content_reports grants no "see reports about me"
-- access either) sees ZERO rows for alice's report.
-- ---------------------------------------------------------------------
savepoint test_3;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000202', true);
set local role authenticated;
do $$
declare
    v_count int;
begin
    select count(*) into v_count
    from public.content_reports
    where reporter_id = '00000000-0000-0000-0000-000000000201';

    if v_count = 0 then
        raise notice 'PASS (test 3): an unrelated ordinary user (including the reported target) sees 0 rows for another user''s report';
    else
        raise warning 'FAIL (test 3): ordinary user saw % row(s), expected 0', v_count;
    end if;
end $$;
reset role;
rollback to savepoint test_3;

-- ---------------------------------------------------------------------
-- Test 4: a signed-out (anon) caller sees ZERO rows.
-- ---------------------------------------------------------------------
savepoint test_4;
set local role anon;
do $$
declare
    v_count int;
begin
    select count(*) into v_count from public.content_reports;

    if v_count = 0 then
        raise notice 'PASS (test 4): an anonymous caller sees 0 content_reports rows';
    else
        raise warning 'FAIL (test 4): anon saw % row(s), expected 0', v_count;
    end if;
end $$;
reset role;
rollback to savepoint test_4;

-- ---------------------------------------------------------------------
-- Test 5: the moderator sees the report via direct SELECT — the exact
-- read moderationRepository.js's getOpenReports() relies on.
-- ---------------------------------------------------------------------
savepoint test_5;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000203', true);
set local role authenticated;
do $$
declare
    v_count int;
begin
    select count(*) into v_count
    from public.content_reports
    where reporter_id = '00000000-0000-0000-0000-000000000201'
        and status = 'open';

    if v_count = 1 then
        raise notice 'PASS (test 5): a moderator sees the open report via direct SELECT';
    else
        raise warning 'FAIL (test 5): moderator saw % row(s), expected 1', v_count;
    end if;
end $$;
reset role;
rollback to savepoint test_5;

-- ---------------------------------------------------------------------
-- Test 6: a non-moderator (bob) cannot call resolve_report() — the
-- exact server-side check js/pages/moderation/loadModerationQueue.js's
-- own client-side gate is a UX convenience in front of, not a
-- replacement for.
-- ---------------------------------------------------------------------
savepoint test_6;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000202', true);
set local role authenticated;
do $$
declare
    v_report_id uuid;
    v_raised boolean := false;
begin
    select id into v_report_id from public.content_reports
        where reporter_id = '00000000-0000-0000-0000-000000000201' limit 1;

    begin
        perform public.resolve_report(v_report_id, 'dismissed');
    exception when others then
        v_raised := true;
    end;

    if v_raised then
        raise notice 'PASS (test 6): a non-moderator cannot call resolve_report() — the RPC itself rejects it';
    else
        raise warning 'FAIL (test 6): a non-moderator was able to call resolve_report() without error';
    end if;
end $$;
reset role;
rollback to savepoint test_6;

-- ---------------------------------------------------------------------
-- Test 7: resolve_report() with an invalid status is rejected — the
-- guard behind moderationRepository.js's RESOLUTION_OUTCOMES mapping
-- (only "reviewed"/"dismissed" are ever sent) staying enforced
-- server-side regardless of what the client sends.
-- ---------------------------------------------------------------------
savepoint test_7;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000203', true);
set local role authenticated;
do $$
declare
    v_report_id uuid;
    v_raised boolean := false;
begin
    select id into v_report_id from public.content_reports
        where reporter_id = '00000000-0000-0000-0000-000000000201' limit 1;

    begin
        perform public.resolve_report(v_report_id, 'not_a_real_status');
    exception when others then
        v_raised := true;
    end;

    if v_raised then
        raise notice 'PASS (test 7): resolve_report() rejects an invalid status';
    else
        raise warning 'FAIL (test 7): resolve_report() accepted an invalid status';
    end if;
end $$;
reset role;
rollback to savepoint test_7;

-- ---------------------------------------------------------------------
-- Test 8: resolve_report() on a nonexistent report id raises "Report
-- not found" — the exact error message
-- js/pages/moderation/renderModerationPage.js pattern-matches
-- (/not found/i) to distinguish a stale/already-gone report from a
-- generic failure.
-- ---------------------------------------------------------------------
savepoint test_8;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000203', true);
set local role authenticated;
do $$
declare
    v_raised boolean := false;
    v_message text;
begin
    begin
        perform public.resolve_report('00000000-0000-0000-0000-000000000999', 'dismissed');
    exception when others then
        v_raised := true;
        get stacked diagnostics v_message = message_text;
    end;

    if v_raised and v_message ilike '%not found%' then
        raise notice 'PASS (test 8): resolve_report() on a nonexistent id raises a "not found" error';
    else
        raise warning 'FAIL (test 8): expected a "not found" error, got raised=%, message=%', v_raised, v_message;
    end if;
end $$;
reset role;
rollback to savepoint test_8;

-- ---------------------------------------------------------------------
-- Test 9: the moderator resolves the report as "dismissed" (UI label
-- "No violation") — the actual write path
-- moderationRepository.js's resolveReport() calls.
-- ---------------------------------------------------------------------
savepoint test_9;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000203', true);
set local role authenticated;
do $$
declare
    v_report_id uuid;
    v_updated public.content_reports;
begin
    select id into v_report_id from public.content_reports
        where reporter_id = '00000000-0000-0000-0000-000000000201' limit 1;

    select * into v_updated from public.resolve_report(v_report_id, 'dismissed');

    if v_updated.status = 'dismissed'
        and v_updated.reviewed_by = '00000000-0000-0000-0000-000000000203'
        and v_updated.reviewed_at is not null then
        raise notice 'PASS (test 9): resolve_report(..., ''dismissed'') updates status/reviewed_by/reviewed_at correctly';
    else
        raise warning 'FAIL (test 9): unexpected result: status=%, reviewed_by=%, reviewed_at=%',
            v_updated.status, v_updated.reviewed_by, v_updated.reviewed_at;
    end if;
end $$;
-- NOT rolled back — tests 10-12 below need this resolution's side
-- effects (the moderation_actions row and the reporter notification) to
-- still exist.
reset role;

-- ---------------------------------------------------------------------
-- Test 10: resolve_report() automatically wrote a moderation_actions
-- audit row — an existing side effect of the RPC (0028_moderation.sql),
-- not something this milestone added; this proves it actually fires now
-- that something finally calls resolve_report() in practice.
-- ---------------------------------------------------------------------
savepoint test_10;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000203', true);
set local role authenticated;
do $$
declare
    v_count int;
begin
    select count(*) into v_count
    from public.moderation_actions
    where actor_id = '00000000-0000-0000-0000-000000000203'
        and action_type = 'report_resolved'
        and target_type = 'profile'
        and target_id = '00000000-0000-0000-0000-000000000202';

    if v_count = 1 then
        raise notice 'PASS (test 10): resolve_report() automatically created exactly one moderation_actions audit row';
    else
        raise warning 'FAIL (test 10): found % moderation_actions row(s), expected 1', v_count;
    end if;
end $$;
reset role;
rollback to savepoint test_10;

-- ---------------------------------------------------------------------
-- Test 11: a non-moderator (bob) cannot read moderation_actions, even
-- for a row that names him as the target — the read
-- js/pages/moderation/renderModerationPage.js's history view relies on
-- staying moderator-only.
-- ---------------------------------------------------------------------
savepoint test_11;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000202', true);
set local role authenticated;
do $$
declare
    v_count int;
begin
    select count(*) into v_count from public.moderation_actions;

    if v_count = 0 then
        raise notice 'PASS (test 11): a non-moderator sees 0 moderation_actions rows, even one naming him as the target';
    else
        raise warning 'FAIL (test 11): non-moderator saw % row(s), expected 0', v_count;
    end if;
end $$;
reset role;
rollback to savepoint test_11;

-- ---------------------------------------------------------------------
-- Test 12: resolve_report() automatically notified the reporter (an
-- existing 0028_moderation.sql side effect, kept as-is per this
-- milestone's own scope — see js/utils/notificationFormat.js's
-- report_resolved case for the one fix this milestone made so that
-- notification renders sensibly instead of falling through to a
-- generic, broken-link default).
-- ---------------------------------------------------------------------
savepoint test_12;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000201', true);
set local role authenticated;
do $$
declare
    v_count int;
begin
    select count(*) into v_count
    from public.notifications
    where recipient_id = '00000000-0000-0000-0000-000000000201'
        and actor_id = '00000000-0000-0000-0000-000000000203'
        and type = 'report_resolved';

    if v_count = 1 then
        raise notice 'PASS (test 12): the reporter received exactly one report_resolved notification';
    else
        raise warning 'FAIL (test 12): reporter has % report_resolved notification(s), expected 1', v_count;
    end if;
end $$;
reset role;
rollback to savepoint test_12;

-- ---------------------------------------------------------------------
-- Test 13: re-resolving the SAME report id a second time (the exact
-- scenario js/pages/moderation/renderModerationPage.js's client-side
-- freshness pre-check exists to avoid triggering in the first place —
-- see that file's own comment) still "succeeds" at the database layer,
-- confirming resolve_report() has no built-in idempotency guard against
-- double-resolution. Documented here as a known, accepted gap (this
-- milestone's final report explains why it's not being closed with a
-- new migration), not silently assumed away.
-- ---------------------------------------------------------------------
savepoint test_13;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000203', true);
set local role authenticated;
do $$
declare
    v_report_id uuid;
    v_second_resolution public.content_reports;
begin
    select id into v_report_id from public.content_reports
        where reporter_id = '00000000-0000-0000-0000-000000000201' limit 1;

    -- Already 'dismissed' from test 9 above. resolve_report() matches
    -- by id alone, so this succeeds and silently overwrites it —
    -- confirming the gap this milestone's UI mitigates client-side.
    select * into v_second_resolution from public.resolve_report(v_report_id, 'reviewed');

    if v_second_resolution.status = 'reviewed' then
        raise notice 'PASS (test 13, informational): resolve_report() has no server-side guard against re-resolving an already-resolved report — confirmed expected/known, not a surprise. UI-layer mitigation only, see this milestone''s final report.';
    else
        raise warning 'FAIL (test 13): expected resolve_report() to silently re-resolve (proving the known gap), got status=%', v_second_resolution.status;
    end if;
end $$;
reset role;
rollback to savepoint test_13;

rollback;
