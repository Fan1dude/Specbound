-- Migration 0036 SQL test suite —
-- supabase/tests/milestone_24_resolve_report_atomic_guard.test.sql
--
-- Covers resolve_report()'s atomic `and status = 'open'` guard added by
-- migration 0036_resolve_report_atomic_status_guard.sql, which fixes the
-- double-resolution race documented in
-- docs/milestones/MILESTONE_24_MODERATOR_REPORT_QUEUE_SPECIFICATION.md
-- §4 and demonstrated during PR #19 review.
--
-- STATUS: executed against the disposable local Supabase/Docker stack
-- for this repository (never production) — see this fix's final report
-- for the actual `psql` run and its output. Depends on migrations
-- 0000-0036 already being applied there.
--
-- Harness limitation, stated precisely rather than glossed over: this
-- file, like every other suite in this directory, runs as ONE script in
-- ONE psql session, wrapped in a single outer transaction that always
-- ends in ROLLBACK so it can never leave residue in a shared database.
-- That structure cannot host a TRUE overlapping-session test — two
-- independently-committing transactions racing each other — because
-- everything in this file shares one uncommitted transaction by design.
-- What test 2 below CAN and does prove, inside that constraint, is that
-- the guard actually works when a second resolve_report() call is made
-- against a report a first call already resolved (moderator B's call
-- strictly follows moderator A's — the same sequencing every prior call
-- in this file already uses).
--
-- The TRUE two-independent-connection scenario — the actual case this
-- fix targets, where each moderator's session is a separate Postgres
-- connection that commits independently — was verified manually outside
-- this harness, using two separate `docker exec ... psql` invocations
-- against the same disposable local database, each with `set local role
-- authenticated; set request.jwt.claim.sub = '<moderator-id>'` simulating
-- a real PostgREST-authenticated session, each its own top-level
-- transaction that actually committed. Before migration 0036: both calls
-- returned success, the second silently overwrote the first's decision,
-- and left 2 moderation_actions rows + 2 notifications for one report.
-- After 0036: the second call raised 'This report has already been
-- resolved.', the first decision was untouched, and exactly 1
-- moderation_actions row + 1 notification remained. See this fix's final
-- report for the exact commands and output from both runs. That manual,
-- genuinely-multi-connection verification is the authoritative
-- concurrency evidence; test 2 below is this file's in-harness proof
-- that the same guard clause is what's actually deployed and callable.
--
-- Same identity-simulation convention as
-- milestone_24_moderator_report_queue.test.sql: `set local role
-- authenticated` + `set_config('request.jwt.claim.sub', ...)`, `set
-- local role anon` for signed-out, `reset role` between tests. Each test
-- runs inside its own SAVEPOINT; tests that later tests depend on are
-- deliberately not rolled back until noted, matching that file's own
-- pattern.

begin;

-- ---------------------------------------------------------------------
-- Fixtures — alice (reporter), bob (ordinary user, non-moderator, and
-- the reported target), modA and modB (two distinct moderators, so
-- "moderator B resolves a report moderator A already resolved" is a
-- genuinely different actor, not the same session calling twice).
-- ---------------------------------------------------------------------

insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-0000-0000-000000000301', 'm24g-alice@example.invalid', '{"username": "m24g_alice_test"}'::jsonb),
    ('00000000-0000-0000-0000-000000000302', 'm24g-bob@example.invalid', '{"username": "m24g_bob_test"}'::jsonb),
    ('00000000-0000-0000-0000-000000000303', 'm24g-moda@example.invalid', '{"username": "m24g_moda_test"}'::jsonb),
    ('00000000-0000-0000-0000-000000000304', 'm24g-modb@example.invalid', '{"username": "m24g_modb_test"}'::jsonb)
on conflict (id) do nothing;

insert into public.profile_roles (user_id, role, granted_by) values
    ('00000000-0000-0000-0000-000000000303', 'moderator', '00000000-0000-0000-0000-000000000303'),
    ('00000000-0000-0000-0000-000000000304', 'moderator', '00000000-0000-0000-0000-000000000304');

-- alice reports bob's profile — the report both test 1/2/3/4/5 below act on.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000301', true);
set local role authenticated;
select public.report_content('profile', '00000000-0000-0000-0000-000000000302', 'm24g test: report for atomic-guard coverage');
reset role;

-- ---------------------------------------------------------------------
-- Test 1: a normal first resolution succeeds (point 1, and half of
-- point 8 — the "dismissed"/"No violation" outcome).
-- ---------------------------------------------------------------------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000303', true);
set local role authenticated;
do $$
declare
    v_report_id uuid;
    v_result public.content_reports;
begin
    select id into v_report_id from public.content_reports
        where reporter_id = '00000000-0000-0000-0000-000000000301'
            and target_id = '00000000-0000-0000-0000-000000000302';

    select * into v_result from public.resolve_report(v_report_id, 'dismissed');

    if v_result.status = 'dismissed' and v_result.reviewed_by = '00000000-0000-0000-0000-000000000303' then
        raise notice 'PASS (test 1): moderator A''s first resolution succeeds (dismissed)';
    else
        raise warning 'FAIL (test 1): unexpected result: status=%, reviewed_by=%', v_result.status, v_result.reviewed_by;
    end if;
end $$;
reset role;
-- NOT rolled back — tests 2-5 need this resolution's committed state.

-- ---------------------------------------------------------------------
-- Test 2: a second attempt (moderator B, a genuinely different actor)
-- against the SAME report fails as already-resolved (point 2), and does
-- so via the atomic guard clause itself — not a pre-check this test file
-- performs.
-- ---------------------------------------------------------------------
savepoint test_2;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000304', true);
set local role authenticated;
do $$
declare
    v_report_id uuid;
    v_raised boolean := false;
    v_message text;
begin
    select id into v_report_id from public.content_reports
        where reporter_id = '00000000-0000-0000-0000-000000000301'
            and target_id = '00000000-0000-0000-0000-000000000302';

    begin
        perform public.resolve_report(v_report_id, 'reviewed');
    exception when others then
        v_raised := true;
        get stacked diagnostics v_message = message_text;
    end;

    if v_raised and v_message ilike '%already%resolved%' then
        raise notice 'PASS (test 2): a second moderator''s attempt against an already-resolved report is rejected with an already-resolved error';
    else
        raise warning 'FAIL (test 2): expected an already-resolved error, got raised=%, message=%', v_raised, v_message;
    end if;
end $$;
reset role;
-- NOT rolled back to test_2 — the point of tests 3-5 is confirming
-- test 2's rejected attempt left NO trace, so its own failed subtransaction
-- (rolled back internally by the `exception when others` block PL/pgSQL
-- wraps around it) must be inspected in the state right after it ran.

-- ---------------------------------------------------------------------
-- Test 3: the first stored outcome (moderator A's "dismissed") was not
-- overwritten by test 2's rejected attempt (point 3).
-- ---------------------------------------------------------------------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000303', true);
set local role authenticated;
do $$
declare
    v_status text;
    v_reviewed_by uuid;
begin
    select status, reviewed_by into v_status, v_reviewed_by from public.content_reports
        where reporter_id = '00000000-0000-0000-0000-000000000301'
            and target_id = '00000000-0000-0000-0000-000000000302';

    if v_status = 'dismissed' and v_reviewed_by = '00000000-0000-0000-0000-000000000303' then
        raise notice 'PASS (test 3): the first stored outcome (moderator A, dismissed) was not overwritten by the rejected second attempt';
    else
        raise warning 'FAIL (test 3): stored outcome changed — status=%, reviewed_by=%, expected dismissed/moderator A', v_status, v_reviewed_by;
    end if;
end $$;
reset role;

-- ---------------------------------------------------------------------
-- Test 4: exactly one moderation_actions row exists for this report's
-- target — test 2's rejected attempt inserted nothing (point 4).
-- ---------------------------------------------------------------------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000303', true);
set local role authenticated;
do $$
declare
    v_count int;
begin
    select count(*) into v_count from public.moderation_actions
        where action_type = 'report_resolved'
            and target_type = 'profile'
            and target_id = '00000000-0000-0000-0000-000000000302';

    if v_count = 1 then
        raise notice 'PASS (test 4): exactly one moderation_actions row exists — the rejected second attempt created none';
    else
        raise warning 'FAIL (test 4): found % moderation_actions row(s), expected exactly 1', v_count;
    end if;
end $$;
reset role;

-- ---------------------------------------------------------------------
-- Test 5: exactly one report_resolved notification was sent to alice —
-- test 2's rejected attempt notified no one (point 5).
-- ---------------------------------------------------------------------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000301', true);
set local role authenticated;
do $$
declare
    v_count int;
begin
    select count(*) into v_count from public.notifications
        where recipient_id = '00000000-0000-0000-0000-000000000301'
            and type = 'report_resolved';

    if v_count = 1 then
        raise notice 'PASS (test 5): exactly one report_resolved notification exists — the rejected second attempt sent none';
    else
        raise warning 'FAIL (test 5): found % notification(s), expected exactly 1', v_count;
    end if;
end $$;
reset role;

-- ---------------------------------------------------------------------
-- Test 6: the not-found case remains distinguishable from the
-- already-resolved case — a nonexistent report id still raises "Report
-- not found.", never the already-resolved message (point 6).
-- ---------------------------------------------------------------------
savepoint test_6;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000303', true);
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

    if v_raised and v_message ilike '%not found%' and v_message not ilike '%already%resolved%' then
        raise notice 'PASS (test 6): a nonexistent report id still raises a distinct "not found" error, never the already-resolved message';
    else
        raise warning 'FAIL (test 6): expected a distinct not-found error, got raised=%, message=%', v_raised, v_message;
    end if;
end $$;
reset role;
rollback to savepoint test_6;

-- ---------------------------------------------------------------------
-- Test 7: an unauthorized (non-moderator) user still cannot resolve a
-- report — confirms the rewrite did not weaken the existing
-- authorization check (point 7).
-- ---------------------------------------------------------------------
savepoint test_7;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000302', true);
set local role authenticated;
do $$
declare
    v_report_id uuid;
    v_raised boolean := false;
    v_message text;
begin
    select id into v_report_id from public.content_reports
        where reporter_id = '00000000-0000-0000-0000-000000000301'
            and target_id = '00000000-0000-0000-0000-000000000302';

    begin
        perform public.resolve_report(v_report_id, 'dismissed');
    exception when others then
        v_raised := true;
        get stacked diagnostics v_message = message_text;
    end;

    if v_raised and v_message ilike '%moderators can resolve%' then
        raise notice 'PASS (test 7): a non-moderator is still rejected by the authorization check, unchanged by the rewrite';
    else
        raise warning 'FAIL (test 7): expected the moderator-only authorization error, got raised=%, message=%', v_raised, v_message;
    end if;
end $$;
reset role;
rollback to savepoint test_7;

-- ---------------------------------------------------------------------
-- Test 8: both permitted first-resolution outcomes still work — a FRESH
-- open report resolved as "reviewed" ("Violation confirmed") succeeds,
-- completing point 8 alongside test 1's "dismissed" case above.
-- ---------------------------------------------------------------------
savepoint test_8;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000301', true);
set local role authenticated;
select public.report_content('profile', '00000000-0000-0000-0000-000000000303', 'm24g test: second fresh report for the reviewed-outcome case');
reset role;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000304', true);
set local role authenticated;
do $$
declare
    v_report_id uuid;
    v_result public.content_reports;
begin
    select id into v_report_id from public.content_reports
        where reporter_id = '00000000-0000-0000-0000-000000000301'
            and target_id = '00000000-0000-0000-0000-000000000303';

    select * into v_result from public.resolve_report(v_report_id, 'reviewed');

    if v_result.status = 'reviewed' and v_result.reviewed_by = '00000000-0000-0000-0000-000000000304' then
        raise notice 'PASS (test 8): a fresh open report can still be resolved as "reviewed" (Violation confirmed)';
    else
        raise warning 'FAIL (test 8): unexpected result: status=%, reviewed_by=%', v_result.status, v_result.reviewed_by;
    end if;
end $$;
reset role;
rollback to savepoint test_8;

-- ---------------------------------------------------------------------
-- Test 9: existing RLS and function grants remain correct after the
-- rewrite — anon still has no EXECUTE on resolve_report(), authenticated
-- still does, and content_reports RLS still hides other users' reports
-- from an ordinary user (point 9).
-- ---------------------------------------------------------------------
savepoint test_9;
do $$
declare
    v_anon_execute boolean;
    v_authenticated_execute boolean;
    v_public_execute boolean;
begin
    select has_function_privilege('anon', 'public.resolve_report(uuid,text,text)', 'execute') into v_anon_execute;
    select has_function_privilege('authenticated', 'public.resolve_report(uuid,text,text)', 'execute') into v_authenticated_execute;
    select has_function_privilege('public', 'public.resolve_report(uuid,text,text)', 'execute') into v_public_execute;

    if v_anon_execute = false and v_authenticated_execute = true and v_public_execute = false then
        raise notice 'PASS (test 9a): resolve_report() grants are unchanged by the rewrite — authenticated only, not anon/public';
    else
        raise warning 'FAIL (test 9a): unexpected grants — anon=%, authenticated=%, public=%', v_anon_execute, v_authenticated_execute, v_public_execute;
    end if;
end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000302', true);
set local role authenticated;
do $$
declare
    v_count int;
begin
    select count(*) into v_count from public.content_reports
        where reporter_id = '00000000-0000-0000-0000-000000000301';

    if v_count = 0 then
        raise notice 'PASS (test 9b): content_reports RLS still hides another user''s reports from an ordinary user';
    else
        raise warning 'FAIL (test 9b): ordinary user saw % row(s) of another user''s reports, expected 0', v_count;
    end if;
end $$;
reset role;
rollback to savepoint test_9;

rollback;
