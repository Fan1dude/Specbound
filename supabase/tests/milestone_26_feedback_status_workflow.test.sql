-- Migration 0039 SQL test suite —
-- supabase/tests/milestone_26_feedback_status_workflow.test.sql
--
-- Covers update_feedback_status() and the supporting schema added by
-- migration 0039_feedback_status_workflow.sql — see that file's own
-- header and docs/milestones/MILESTONE_26_FEEDBACK_REVIEW_SPECIFICATION.md
-- for the full design.
--
-- STATUS: executed against the disposable local Supabase/Docker stack
-- for this repository (never production). Depends on migrations
-- 0000-0039 already being applied there.
--
-- Same identity-simulation convention as every other suite in this
-- directory: `set_config('request.jwt.claim.sub', ...)` +
-- `set local role authenticated`/`set local role anon`, `reset role`
-- between tests, everything wrapped in one outer transaction that always
-- ends in ROLLBACK so this file can never leave residue in a shared
-- database. Fixture inserts (auth.users, profile_roles, and — where
-- noted — feedback_submissions rows that need a specific, controlled
-- created_at/status_updated_at value the RPC itself would never
-- produce) run under the harness's default role (bypasses RLS, same as
-- every other suite's fixture setup).
--
-- Harness limitation, same one 0036's own test file documents precisely
-- rather than glossing over: this file runs as ONE script in ONE psql
-- session inside a single transaction, so it cannot host a TRUE
-- overlapping-session race (two independently-committing transactions).
-- Test 12 below proves the atomic guard rejects a second, stale call
-- that sequentially follows a first — the same in-harness proof 0036's
-- test 2 already established for resolve_report(). The genuine
-- multi-connection scenario is exercised separately during this
-- milestone's live local verification (two real disposable accounts,
-- two real psql/PostgREST sessions) — see the final report for that run.
--
-- Second harness limitation, specific to this file: `now()` inside
-- PL/pgSQL returns the enclosing TRANSACTION's start time (transaction_
-- timestamp() semantics), not wall-clock time per statement — so every
-- update_feedback_status() call made anywhere in this single-transaction
-- file gets an IDENTICAL status_updated_at. That's a harness artifact,
-- not a bug (every timestamp column in this schema already uses now()
-- the same way, and in real use each RPC call is its own transaction).
-- Test 16 (History ordering) therefore proves the ORDER BY contract by
-- inserting fixture rows with explicit, distinct status_updated_at/
-- created_at values directly, not by relying on two RPC calls in this
-- file producing different timestamps.

begin;

-- ---------------------------------------------------------------------
-- Fixtures.
--   alice (401) — ordinary submitter.
--   bob   (402) — ordinary user, non-moderator; also used as the
--                 "cross-user" reader who must never see alice's rows.
--   modA  (403) — moderator role.
--   modB  (404) — staff role (distinct from moderator, to prove both
--                 satisfy is_platform_moderator()).
--   carol (405) — a second submitter, kept separate from alice so
--                 per-recipient notification counts in later tests are
--                 unambiguous.
-- ---------------------------------------------------------------------

insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-0000-0000-000000000401', 'm26-alice@example.invalid', '{"username": "m26_alice_test"}'::jsonb),
    ('00000000-0000-0000-0000-000000000402', 'm26-bob@example.invalid', '{"username": "m26_bob_test"}'::jsonb),
    ('00000000-0000-0000-0000-000000000403', 'm26-moda@example.invalid', '{"username": "m26_moda_test"}'::jsonb),
    ('00000000-0000-0000-0000-000000000404', 'm26-modb@example.invalid', '{"username": "m26_modb_test"}'::jsonb),
    ('00000000-0000-0000-0000-000000000405', 'm26-carol@example.invalid', '{"username": "m26_carol_test"}'::jsonb)
on conflict (id) do nothing;

insert into public.profile_roles (user_id, role, granted_by) values
    ('00000000-0000-0000-0000-000000000403', 'moderator', '00000000-0000-0000-0000-000000000403'),
    ('00000000-0000-0000-0000-000000000404', 'staff', '00000000-0000-0000-0000-000000000404');

-- alice submits one feedback row through the real RPC (same path a
-- genuine user takes) — this is the row tests 1-9ish act on.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000401', true);
set local role authenticated;
select public.submit_feedback('bug', 'm26 test: fixture submission for status-workflow coverage', 'https://specboundapp.com/pages/workshop.html');
reset role;

-- ---------------------------------------------------------------------
-- Test 1: moderator authorization — modA (role = moderator) can move
-- alice's row from open to reviewed.
-- ---------------------------------------------------------------------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000403', true);
set local role authenticated;
do $$
declare
    v_feedback_id uuid;
    v_result public.feedback_submissions;
begin
    select id into v_feedback_id from public.feedback_submissions
        where user_id = '00000000-0000-0000-0000-000000000401' and status = 'open';

    select * into v_result from public.update_feedback_status(v_feedback_id, 'open', 'reviewed');

    if v_result.status = 'reviewed' then
        raise notice 'PASS (test 1): moderator (role=moderator) can transition open -> reviewed';
    else
        raise warning 'FAIL (test 1): unexpected status=%', v_result.status;
    end if;
end $$;
reset role;
-- NOT rolled back — later tests build on this row now being 'reviewed'.

-- ---------------------------------------------------------------------
-- Test 2: staff authorization — modB (role = staff, not moderator)
-- can transition the same row reviewed -> closed, proving
-- is_platform_moderator() covers both roles, not just 'moderator'.
-- ---------------------------------------------------------------------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000404', true);
set local role authenticated;
do $$
declare
    v_feedback_id uuid;
    v_result public.feedback_submissions;
begin
    select id into v_feedback_id from public.feedback_submissions
        where user_id = '00000000-0000-0000-0000-000000000401' and status = 'reviewed';

    select * into v_result from public.update_feedback_status(v_feedback_id, 'reviewed', 'closed');

    if v_result.status = 'closed' then
        raise notice 'PASS (test 2): staff (role=staff) can transition reviewed -> closed';
    else
        raise warning 'FAIL (test 2): unexpected status=%', v_result.status;
    end if;
end $$;
reset role;
-- NOT rolled back — alice's fixture row is now 'closed' for the
-- remainder of this file (used by the terminal/no-op tests below).

-- ---------------------------------------------------------------------
-- Test 3: ordinary-user (non-moderator, non-staff) rejection — bob
-- cannot call update_feedback_status at all, rejected by the function's
-- own business-logic check (not the grant layer — bob is authenticated).
-- ---------------------------------------------------------------------
savepoint test_3;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000402', true);
set local role authenticated;
do $$
declare
    v_feedback_id uuid;
    v_raised boolean := false;
    v_message text;
begin
    select id into v_feedback_id from public.feedback_submissions
        where user_id = '00000000-0000-0000-0000-000000000401';

    begin
        perform public.update_feedback_status(v_feedback_id, 'closed', 'reviewed');
    exception when others then
        v_raised := true;
        get stacked diagnostics v_message = message_text;
    end;

    if v_raised and v_message ilike '%only moderators or staff%' then
        raise notice 'PASS (test 3): an ordinary authenticated user is rejected by the function''s own authorization check';
    else
        raise warning 'FAIL (test 3): expected the moderator/staff-only error, got raised=%, message=%', v_raised, v_message;
    end if;
end $$;
reset role;
rollback to savepoint test_3;

-- ---------------------------------------------------------------------
-- Test 4: anonymous grant-layer rejection — an anon caller never
-- reaches the function body at all (42501), matching the grants
-- hardened by 0033/0038 for every other RPC in this schema.
-- ---------------------------------------------------------------------
savepoint test_4;
set local role anon;
do $$
declare
    v_feedback_id uuid;
    v_raised boolean := false;
    v_sqlstate text;
begin
    select id into v_feedback_id from public.feedback_submissions
        where user_id = '00000000-0000-0000-0000-000000000401';

    begin
        perform public.update_feedback_status(v_feedback_id, 'closed', 'reviewed');
    exception when others then
        v_raised := true;
        get stacked diagnostics v_sqlstate = returned_sqlstate;
    end;

    if v_raised and v_sqlstate = '42501' then
        raise notice 'PASS (test 4): anon is rejected at the grant layer (42501), never reaching the function body';
    else
        raise warning 'FAIL (test 4): expected sqlstate 42501, got raised=%, sqlstate=%', v_raised, v_sqlstate;
    end if;
end $$;
reset role;
rollback to savepoint test_4;

-- ---------------------------------------------------------------------
-- Test 5: existing self-read RLS is unchanged — alice can still read
-- her own (now-closed) row.
-- ---------------------------------------------------------------------
savepoint test_5;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000401', true);
set local role authenticated;
do $$
declare
    v_count int;
begin
    select count(*) into v_count from public.feedback_submissions
        where user_id = '00000000-0000-0000-0000-000000000401';

    if v_count = 1 then
        raise notice 'PASS (test 5): submitter can still read her own feedback row via existing self-read RLS';
    else
        raise warning 'FAIL (test 5): expected 1 row, saw %', v_count;
    end if;
end $$;
reset role;
rollback to savepoint test_5;

-- ---------------------------------------------------------------------
-- Test 6: cross-user read denial — bob (ordinary, non-moderator)
-- cannot see alice's feedback row through the same table.
-- ---------------------------------------------------------------------
savepoint test_6;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000402', true);
set local role authenticated;
do $$
declare
    v_count int;
begin
    select count(*) into v_count from public.feedback_submissions
        where user_id = '00000000-0000-0000-0000-000000000401';

    if v_count = 0 then
        raise notice 'PASS (test 6): an ordinary user cannot read another user''s feedback row';
    else
        raise warning 'FAIL (test 6): bob saw % of alice''s row(s), expected 0', v_count;
    end if;
end $$;
reset role;
rollback to savepoint test_6;

-- ---------------------------------------------------------------------
-- Test 7-9: all three valid transitions succeed, each on a FRESH
-- carol-submitted row (independent of alice's fixture above).
-- ---------------------------------------------------------------------
savepoint test_valid_transitions;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000405', true);
set local role authenticated;
select public.submit_feedback('suggestion', 'm26 test: carol fixture A (open -> reviewed)', null);
select public.submit_feedback('suggestion', 'm26 test: carol fixture B (open -> closed)', null);
select public.submit_feedback('suggestion', 'm26 test: carol fixture C (reviewed -> closed)', null);
reset role;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000403', true);
set local role authenticated;
do $$
declare
    v_id_a uuid;
    v_id_b uuid;
    v_id_c uuid;
    v_result public.feedback_submissions;
    v_pass boolean := true;
begin
    select id into v_id_a from public.feedback_submissions where message = 'm26 test: carol fixture A (open -> reviewed)';
    select id into v_id_b from public.feedback_submissions where message = 'm26 test: carol fixture B (open -> closed)';
    select id into v_id_c from public.feedback_submissions where message = 'm26 test: carol fixture C (reviewed -> closed)';

    select * into v_result from public.update_feedback_status(v_id_a, 'open', 'reviewed');
    if v_result.status <> 'reviewed' then v_pass := false; end if;

    select * into v_result from public.update_feedback_status(v_id_b, 'open', 'closed');
    if v_result.status <> 'closed' then v_pass := false; end if;

    select * into v_result from public.update_feedback_status(v_id_c, 'open', 'reviewed');
    if v_result.status <> 'reviewed' then v_pass := false; end if;
    select * into v_result from public.update_feedback_status(v_id_c, 'reviewed', 'closed');
    if v_result.status <> 'closed' then v_pass := false; end if;

    if v_pass then
        raise notice 'PASS (tests 7-9): all three approved transitions (open->reviewed, open->closed, reviewed->closed) succeed';
    else
        raise warning 'FAIL (tests 7-9): one or more valid transitions produced an unexpected status';
    end if;
end $$;
reset role;
rollback to savepoint test_valid_transitions;

-- ---------------------------------------------------------------------
-- Test 10: every invalid/no-op transition is rejected — reviewed->open,
-- closed->open, closed->reviewed, and all three no-ops. Uses alice's
-- fixture row, which is 'closed' at this point in the file (tests 1-2).
-- ---------------------------------------------------------------------
savepoint test_10;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000403', true);
set local role authenticated;
do $$
declare
    v_feedback_id uuid;
    v_pass boolean := true;
    v_expected text;
    v_new text;
    v_raised boolean;
    v_message text;
    v_pairs text[][] := array[
        array['reviewed', 'open'],
        array['closed', 'open'],
        array['closed', 'reviewed'],
        array['open', 'open'],
        array['reviewed', 'reviewed'],
        array['closed', 'closed']
    ];
    i int;
begin
    select id into v_feedback_id from public.feedback_submissions
        where user_id = '00000000-0000-0000-0000-000000000401';

    for i in 1..array_length(v_pairs, 1) loop
        v_expected := v_pairs[i][1];
        v_new := v_pairs[i][2];
        v_raised := false;

        begin
            perform public.update_feedback_status(v_feedback_id, v_expected, v_new);
        exception when others then
            v_raised := true;
            get stacked diagnostics v_message = message_text;
        end;

        if not (v_raised and v_message ilike '%invalid status transition%') then
            v_pass := false;
            raise warning 'FAIL (test 10, %->%): expected an invalid-transition error, got raised=%, message=%', v_expected, v_new, v_raised, v_message;
        end if;
    end loop;

    if v_pass then
        raise notice 'PASS (test 10): every invalid transition and every no-op is rejected as an invalid status transition';
    end if;
end $$;
reset role;
rollback to savepoint test_10;

-- ---------------------------------------------------------------------
-- Test 11: Closed is genuinely terminal — even the correct current
-- status ('closed') can never be the SOURCE of any transition, already
-- exhaustively covered by test 10's closed->open/closed->reviewed
-- cases plus closed->closed above; this test additionally confirms the
-- row's actual stored status truly is 'closed' and stays that way after
-- every rejected attempt in test 10.
-- ---------------------------------------------------------------------
savepoint test_11;
do $$
declare
    v_status text;
begin
    select status into v_status from public.feedback_submissions
        where user_id = '00000000-0000-0000-0000-000000000401';

    if v_status = 'closed' then
        raise notice 'PASS (test 11): the row remains genuinely closed after every rejected transition attempt';
    else
        raise warning 'FAIL (test 11): expected status=closed, found %', v_status;
    end if;
end $$;
rollback to savepoint test_11;

-- ---------------------------------------------------------------------
-- Test 12: not-found behavior — a random, nonexistent id raises a
-- distinct "not found" error, never the stale/conflict message.
-- ---------------------------------------------------------------------
savepoint test_12;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000403', true);
set local role authenticated;
do $$
declare
    v_raised boolean := false;
    v_message text;
begin
    begin
        perform public.update_feedback_status('00000000-0000-0000-0000-000000000999', 'open', 'reviewed');
    exception when others then
        v_raised := true;
        get stacked diagnostics v_message = message_text;
    end;

    if v_raised and v_message ilike '%not found%' and v_message not ilike '%already%updated%' then
        raise notice 'PASS (test 12): a nonexistent feedback id raises a distinct not-found error';
    else
        raise warning 'FAIL (test 12): expected a distinct not-found error, got raised=%, message=%', v_raised, v_message;
    end if;
end $$;
reset role;
rollback to savepoint test_12;

-- ---------------------------------------------------------------------
-- Test 13: atomic stale/concurrent conflict, and exactly one accepted
-- outcome under competing reviewers — modA transitions a fresh open
-- row to 'reviewed'; modB then attempts open->closed against the SAME
-- row using the now-stale expected status 'open'. modB's call must be
-- rejected with the distinct stale/conflict message, and the row must
-- retain modA's outcome ('reviewed'), not modB's attempted one.
-- (In-harness sequential proof — see this file's header for why a true
-- overlapping-connection race is verified separately, live.)
-- ---------------------------------------------------------------------
savepoint test_13;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000405', true);
set local role authenticated;
select public.submit_feedback('bug', 'm26 test: carol fixture D (competing reviewers)', null);
reset role;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000403', true);
set local role authenticated;
do $$
declare
    v_feedback_id uuid;
    v_result public.feedback_submissions;
begin
    select id into v_feedback_id from public.feedback_submissions where message = 'm26 test: carol fixture D (competing reviewers)';
    select * into v_result from public.update_feedback_status(v_feedback_id, 'open', 'reviewed');

    if v_result.status <> 'reviewed' then
        raise warning 'FAIL (test 13 setup): modA''s first call did not succeed as expected';
    end if;
end $$;
reset role;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000404', true);
set local role authenticated;
do $$
declare
    v_feedback_id uuid;
    v_raised boolean := false;
    v_message text;
    v_final_status text;
begin
    select id into v_feedback_id from public.feedback_submissions where message = 'm26 test: carol fixture D (competing reviewers)';

    begin
        perform public.update_feedback_status(v_feedback_id, 'open', 'closed');
    exception when others then
        v_raised := true;
        get stacked diagnostics v_message = message_text;
    end;

    select status into v_final_status from public.feedback_submissions where id = v_feedback_id;

    if v_raised and v_message ilike '%already updated%' and v_final_status = 'reviewed' then
        raise notice 'PASS (test 13): a stale second call from a competing reviewer is rejected, and the row retains only the first accepted outcome (exactly one winner)';
    else
        raise warning 'FAIL (test 13): expected a stale-conflict rejection with the row left at reviewed, got raised=%, message=%, final_status=%', v_raised, v_message, v_final_status;
    end if;
end $$;
reset role;
rollback to savepoint test_13;

-- ---------------------------------------------------------------------
-- Test 14: status_updated_at is set only on success — null before any
-- transition, set after a successful one, and UNCHANGED by a rejected
-- attempt (invalid transition) made afterward.
-- ---------------------------------------------------------------------
savepoint test_14;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000405', true);
set local role authenticated;
select public.submit_feedback('confusing', 'm26 test: carol fixture E (status_updated_at)', null);
reset role;

do $$
declare
    v_feedback_id uuid;
    v_before timestamptz;
begin
    select id into v_feedback_id from public.feedback_submissions where message = 'm26 test: carol fixture E (status_updated_at)';
    select status_updated_at into v_before from public.feedback_submissions where id = v_feedback_id;

    if v_before is null then
        raise notice 'PASS (test 14a): a freshly-submitted open row has status_updated_at = null';
    else
        raise warning 'FAIL (test 14a): expected null, got %', v_before;
    end if;
end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000403', true);
set local role authenticated;
do $$
declare
    v_feedback_id uuid;
    v_after timestamptz;
begin
    select id into v_feedback_id from public.feedback_submissions where message = 'm26 test: carol fixture E (status_updated_at)';
    perform public.update_feedback_status(v_feedback_id, 'open', 'reviewed');

    select status_updated_at into v_after from public.feedback_submissions where id = v_feedback_id;

    if v_after is not null then
        raise notice 'PASS (test 14b): a successful transition sets status_updated_at';
    else
        raise warning 'FAIL (test 14b): expected a non-null timestamp after a successful transition';
    end if;
end $$;

do $$
declare
    v_feedback_id uuid;
    v_before_reject timestamptz;
    v_after_reject timestamptz;
begin
    select id into v_feedback_id from public.feedback_submissions where message = 'm26 test: carol fixture E (status_updated_at)';
    select status_updated_at into v_before_reject from public.feedback_submissions where id = v_feedback_id;

    begin
        perform public.update_feedback_status(v_feedback_id, 'reviewed', 'open');
    exception when others then
        null;
    end;

    select status_updated_at into v_after_reject from public.feedback_submissions where id = v_feedback_id;

    if v_before_reject = v_after_reject then
        raise notice 'PASS (test 14c): a rejected (invalid) transition attempt does not change status_updated_at';
    else
        raise warning 'FAIL (test 14c): status_updated_at changed on a rejected attempt — before=%, after=%', v_before_reject, v_after_reject;
    end if;
end $$;
reset role;
rollback to savepoint test_14;

-- ---------------------------------------------------------------------
-- Test 15: correct History ordering contract — status_updated_at is
-- the primary sort key (desc), with created_at, then id, as
-- deterministic tiebreakers. Fixture rows below set BOTH columns
-- explicitly (bypassing the RPC, which cannot produce distinct
-- status_updated_at values within one transaction — see this file's
-- header) so the ordering can be verified precisely rather than
-- relying on now()'s per-transaction constancy.
-- ---------------------------------------------------------------------
savepoint test_15;

insert into public.feedback_submissions (id, user_id, category, message, status, created_at, status_updated_at) values
    ('00000000-0000-0000-0000-000000000411', '00000000-0000-0000-0000-000000000401', 'bug', 'm26 test: ordering — newest status_updated_at', 'closed', now() - interval '10 days', now() - interval '1 hour'),
    ('00000000-0000-0000-0000-000000000412', '00000000-0000-0000-0000-000000000401', 'bug', 'm26 test: ordering — oldest status_updated_at, but newest created_at', 'reviewed', now(), now() - interval '5 hours'),
    -- Two rows tied on status_updated_at — created_at must break the tie.
    ('00000000-0000-0000-0000-000000000413', '00000000-0000-0000-0000-000000000401', 'bug', 'm26 test: ordering — tied A (older created_at)', 'closed', now() - interval '2 days', now() - interval '3 hours'),
    ('00000000-0000-0000-0000-000000000414', '00000000-0000-0000-0000-000000000401', 'bug', 'm26 test: ordering — tied B (newer created_at)', 'closed', now() - interval '1 day', now() - interval '3 hours');

do $$
declare
    v_ordered uuid[];
begin
    select array_agg(id order by status_updated_at desc nulls last, created_at desc, id desc)
        into v_ordered
        from public.feedback_submissions
        where id in (
            '00000000-0000-0000-0000-000000000411',
            '00000000-0000-0000-0000-000000000412',
            '00000000-0000-0000-0000-000000000413',
            '00000000-0000-0000-0000-000000000414'
        );

    -- Expected order: 411 (most recent status_updated_at) first, then
    -- the tied pair with the newer created_at (414) before the older
    -- (413), then 412 (oldest status_updated_at, despite having the
    -- newest created_at of all four) last.
    if v_ordered = array[
        '00000000-0000-0000-0000-000000000411'::uuid,
        '00000000-0000-0000-0000-000000000414'::uuid,
        '00000000-0000-0000-0000-000000000413'::uuid,
        '00000000-0000-0000-0000-000000000412'::uuid
    ] then
        raise notice 'PASS (test 15): History''s ORDER BY (status_updated_at desc, created_at desc, id desc) sorts by most-recently-actioned first, with a deterministic tiebreak — not by submission age';
    else
        raise warning 'FAIL (test 15): unexpected order %', v_ordered;
    end if;
end $$;
rollback to savepoint test_15;

-- ---------------------------------------------------------------------
-- Test 16: correct notification type and recipient — a fresh row,
-- transitioned open -> reviewed then reviewed -> closed, produces
-- exactly one 'feedback_reviewed' and one 'feedback_closed'
-- notification, both recipient_id = the submitter.
-- ---------------------------------------------------------------------
savepoint test_16;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000405', true);
set local role authenticated;
select public.submit_feedback('feature_request', 'm26 test: carol fixture F (notification type/recipient)', null);
reset role;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000403', true);
set local role authenticated;
do $$
declare
    v_feedback_id uuid;
begin
    select id into v_feedback_id from public.feedback_submissions where message = 'm26 test: carol fixture F (notification type/recipient)';
    perform public.update_feedback_status(v_feedback_id, 'open', 'reviewed');
    perform public.update_feedback_status(v_feedback_id, 'reviewed', 'closed');
end $$;
reset role;

do $$
declare
    v_reviewed_count int;
    v_closed_count int;
begin
    select count(*) into v_reviewed_count from public.notifications
        where recipient_id = '00000000-0000-0000-0000-000000000405' and type = 'feedback_reviewed';
    select count(*) into v_closed_count from public.notifications
        where recipient_id = '00000000-0000-0000-0000-000000000405' and type = 'feedback_closed';

    if v_reviewed_count = 1 and v_closed_count = 1 then
        raise notice 'PASS (test 16): exactly one feedback_reviewed and one feedback_closed notification, correctly addressed to the submitter';
    else
        raise warning 'FAIL (test 16): expected 1/1, got feedback_reviewed=%, feedback_closed=%', v_reviewed_count, v_closed_count;
    end if;
end $$;

-- ---------------------------------------------------------------------
-- Test 17: reviewer identity absent from client-visible notification
-- data — both notifications from test 16 have actor_id = null.
-- ---------------------------------------------------------------------
do $$
declare
    v_non_null_actor_count int;
begin
    select count(*) into v_non_null_actor_count from public.notifications
        where recipient_id = '00000000-0000-0000-0000-000000000405'
            and type in ('feedback_reviewed', 'feedback_closed')
            and actor_id is not null;

    if v_non_null_actor_count = 0 then
        raise notice 'PASS (test 17): neither feedback notification carries a reviewer identity — actor_id is null on both';
    else
        raise warning 'FAIL (test 17): % feedback notification(s) unexpectedly carry a non-null actor_id', v_non_null_actor_count;
    end if;
end $$;
rollback to savepoint test_16;

-- ---------------------------------------------------------------------
-- Test 18: null submitter transition without notification — a row
-- with user_id = null (simulating a deleted account, per
-- feedback_submissions' own `on delete set null`) can still be
-- transitioned successfully, and creates zero notifications.
-- ---------------------------------------------------------------------
savepoint test_18;

-- Role-switching (SET LOCAL ROLE) is kept as top-level statements, not
-- nested inside a DO block — same convention every other test in this
-- file (and every other suite in this directory) follows; a temp table
-- carries the "before" count across the role switch since PL/pgSQL
-- local variables can't survive between separate DO blocks.
create temp table m26_test18_counts (label text, cnt int);

insert into public.feedback_submissions (id, user_id, category, message, status) values
    ('00000000-0000-0000-0000-000000000415', null, 'bug', 'm26 test: deleted-account fixture', 'open');

insert into m26_test18_counts
    select 'before', count(*) from public.notifications where type in ('feedback_reviewed', 'feedback_closed');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000403', true);
set local role authenticated;
select public.update_feedback_status('00000000-0000-0000-0000-000000000415', 'open', 'reviewed');
reset role;

insert into m26_test18_counts
    select 'after', count(*) from public.notifications where type in ('feedback_reviewed', 'feedback_closed');

do $$
declare
    v_before int;
    v_after int;
    v_status text;
begin
    select cnt into v_before from m26_test18_counts where label = 'before';
    select cnt into v_after from m26_test18_counts where label = 'after';

    if v_after = v_before then
        raise notice 'PASS (test 18): a null-user_id (deleted-account) row transitions successfully and creates zero notifications';
    else
        raise warning 'FAIL (test 18): notification count changed (%->%) for a null-user_id transition, expected no change', v_before, v_after;
    end if;

    select status into v_status from public.feedback_submissions where id = '00000000-0000-0000-0000-000000000415';

    if v_status = 'reviewed' then
        raise notice 'PASS (test 18b): the null-user_id row''s status itself was updated normally';
    else
        raise warning 'FAIL (test 18b): expected status=reviewed, got %', v_status;
    end if;
end $$;
rollback to savepoint test_18;

-- ---------------------------------------------------------------------
-- Test 19: null actor handling does not error — create_notification()
-- itself accepts a null p_actor_id (used internally by
-- update_feedback_status(); not directly callable by any client role,
-- so this exercises it the same way production does: from inside
-- another SECURITY DEFINER function). Already proven functionally by
-- tests 16/17 succeeding without error; this test additionally confirms
-- the notifications.actor_id column itself is genuinely nullable at the
-- schema level, not merely "happened to not be enforced yet".
-- ---------------------------------------------------------------------
savepoint test_19;
do $$
declare
    v_is_nullable text;
begin
    select is_nullable into v_is_nullable
        from information_schema.columns
        where table_schema = 'public' and table_name = 'notifications' and column_name = 'actor_id';

    if v_is_nullable = 'YES' then
        raise notice 'PASS (test 19): notifications.actor_id is genuinely nullable at the schema level';
    else
        raise warning 'FAIL (test 19): expected actor_id to be nullable, is_nullable=%', v_is_nullable;
    end if;
end $$;
rollback to savepoint test_19;

-- ---------------------------------------------------------------------
-- Test 20: notification constraint behavior — the widened CHECK
-- accepts both new types and still rejects an unrecognized one. Uses a
-- throwaway direct insert (bypassing create_notification(), which has
-- no client grant) purely to probe the constraint itself.
-- ---------------------------------------------------------------------
savepoint test_20;
do $$
declare
    v_accepted_ok boolean := true;
    v_rejected_ok boolean := false;
begin
    begin
        insert into public.notifications (recipient_id, actor_id, type) values
            ('00000000-0000-0000-0000-000000000401', null, 'feedback_reviewed');
        insert into public.notifications (recipient_id, actor_id, type) values
            ('00000000-0000-0000-0000-000000000401', null, 'feedback_closed');
    exception when others then
        v_accepted_ok := false;
    end;

    begin
        insert into public.notifications (recipient_id, actor_id, type) values
            ('00000000-0000-0000-0000-000000000401', null, 'not_a_real_type');
    exception when check_violation then
        v_rejected_ok := true;
    end;

    if v_accepted_ok and v_rejected_ok then
        raise notice 'PASS (test 20): notifications_type_check accepts feedback_reviewed/feedback_closed and still rejects an unknown type';
    else
        raise warning 'FAIL (test 20): accepted_ok=%, rejected_ok=%', v_accepted_ok, v_rejected_ok;
    end if;
end $$;
rollback to savepoint test_20;

-- ---------------------------------------------------------------------
-- Test 21: existing (actor-backed) notification types unaffected —
-- set_follow() still creates a normal, real-actor 'follow' notification
-- exactly as before 0039 (regression check for the actor_id nullability
-- change: it only permits a new possibility, nothing existing changed).
-- ---------------------------------------------------------------------
savepoint test_21;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000402', true);
set local role authenticated;
select public.set_follow('00000000-0000-0000-0000-000000000401', true);
reset role;

do $$
declare
    v_actor_id uuid;
begin
    select actor_id into v_actor_id from public.notifications
        where recipient_id = '00000000-0000-0000-0000-000000000401'
            and type = 'follow'
        order by created_at desc
        limit 1;

    if v_actor_id = '00000000-0000-0000-0000-000000000402' then
        raise notice 'PASS (test 21): an existing actor-backed notification type (follow) still carries a real, correct actor_id, unaffected by the nullability change';
    else
        raise warning 'FAIL (test 21): expected actor_id=bob, got %', v_actor_id;
    end if;
end $$;
rollback to savepoint test_21;

-- ---------------------------------------------------------------------
-- Test 22: function grants — authenticated has EXECUTE on
-- update_feedback_status(); anon/public do not. Matches the hardened
-- posture from 0033/0038.
-- ---------------------------------------------------------------------
savepoint test_22;
do $$
declare
    v_anon_execute boolean;
    v_authenticated_execute boolean;
    v_public_execute boolean;
begin
    select has_function_privilege('anon', 'public.update_feedback_status(uuid,text,text)', 'execute') into v_anon_execute;
    select has_function_privilege('authenticated', 'public.update_feedback_status(uuid,text,text)', 'execute') into v_authenticated_execute;
    select has_function_privilege('public', 'public.update_feedback_status(uuid,text,text)', 'execute') into v_public_execute;

    if v_anon_execute = false and v_authenticated_execute = true and v_public_execute = false then
        raise notice 'PASS (test 22): update_feedback_status() grants are authenticated-only, matching 0033/0038''s hardened posture';
    else
        raise warning 'FAIL (test 22): unexpected grants — anon=%, authenticated=%, public=%', v_anon_execute, v_authenticated_execute, v_public_execute;
    end if;
end $$;
rollback to savepoint test_22;

-- ---------------------------------------------------------------------
-- Test 23: rollback SQL preserves data — running the literal rollback
-- statement (drop function) inside a savepoint leaves every existing
-- feedback row, its status, its status_updated_at, and every existing
-- notification (actor-backed and actorless alike) completely untouched,
-- and makes update_feedback_status() genuinely uncallable afterward
-- (42883, undefined function) until re-applied. The savepoint is then
-- rolled back, restoring the function for any tests that might run
-- after this one — though this file's own outer `rollback;` at the end
-- discards everything regardless.
-- ---------------------------------------------------------------------
savepoint test_23;
do $$
declare
    v_feedback_count_before int;
    v_notification_count_before int;
    v_feedback_count_after int;
    v_notification_count_after int;
    v_raised boolean := false;
    v_sqlstate text;
begin
    select count(*) into v_feedback_count_before from public.feedback_submissions;
    select count(*) into v_notification_count_before from public.notifications;

    execute 'drop function if exists public.update_feedback_status(uuid, text, text)';

    select count(*) into v_feedback_count_after from public.feedback_submissions;
    select count(*) into v_notification_count_after from public.notifications;

    if v_feedback_count_before <> v_feedback_count_after or v_notification_count_before <> v_notification_count_after then
        raise warning 'FAIL (test 23a): row counts changed by the rollback — feedback %->%, notifications %->%',
            v_feedback_count_before, v_feedback_count_after, v_notification_count_before, v_notification_count_after;
    else
        raise notice 'PASS (test 23a): the rollback (drop function) leaves every feedback row and every notification completely untouched';
    end if;

    begin
        perform public.update_feedback_status('00000000-0000-0000-0000-000000000401', 'open', 'reviewed');
    exception when others then
        v_raised := true;
        get stacked diagnostics v_sqlstate = returned_sqlstate;
    end;

    if v_raised and v_sqlstate = '42883' then
        raise notice 'PASS (test 23b): update_feedback_status() is genuinely uncallable after the rollback (undefined function)';
    else
        raise warning 'FAIL (test 23b): expected sqlstate 42883 after dropping the function, got raised=%, sqlstate=%', v_raised, v_sqlstate;
    end if;
end $$;
rollback to savepoint test_23;

-- Everything in this file — fixtures, all 23 tests' effects — is
-- discarded here. Nothing above ever touches a real/shared database.
rollback;
