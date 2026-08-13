-- Milestone 25 SQL test suite —
-- supabase/tests/milestone_25_follow_notifications.test.sql
--
-- Covers migration 0037_follow_notifications.sql — set_follow() now
-- calls create_notification() on a genuinely new follow, and
-- notifications_type_check accepts 'follow'. Full design:
-- docs/milestones/MILESTONE_25_FOLLOW_NOTIFICATIONS_SPECIFICATION.md.
--
-- STATUS: executed against the disposable local Supabase/Docker stack
-- for this repository (never production) — see this milestone's final
-- report for the actual `psql` run and its output. Depends on migrations
-- 0000-0037 already being applied there.
--
-- Concurrency note, stated precisely rather than glossed over (same
-- honest framing as milestone_24_resolve_report_atomic_guard.test.sql):
-- this file, like every suite in this directory, runs as one script in
-- one transaction that always ends in ROLLBACK, so it cannot host a TRUE
-- two-independently-committing-session test. Test 3 below proves the
-- underlying mechanism — INSERT ... ON CONFLICT DO NOTHING RETURNING id
-- — is what's actually deployed and behaves correctly under a repeated
-- call; the guarantee that this specific Postgres pattern is safe under
-- genuine multi-connection concurrency was already empirically
-- demonstrated during Milestone 24's resolve_report() work (two real,
-- separately-authenticated database connections racing the identical
-- ON CONFLICT DO NOTHING RETURNING mechanism) and applies identically
-- here, since set_follow() reuses that exact pattern verbatim, not a
-- variation of it.
--
-- Same identity-simulation convention as every other suite in this
-- directory: `set local role authenticated` + `set_config
-- ('request.jwt.claim.sub', ...)`, `set local role anon` for
-- signed-out, `reset role` between tests. Each test runs inside its own
-- SAVEPOINT; tests that later tests depend on are deliberately not
-- rolled back until noted.

begin;

-- ---------------------------------------------------------------------
-- Fixtures — alice (follower), bob (followed). A third account, carol,
-- is used only for the unauthorized-read test (test 7) so it's a
-- genuinely different, uninvolved party, not alice or bob themselves.
-- ---------------------------------------------------------------------

insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-0000-0000-000000000401', 'm25-alice@example.invalid', '{"username": "m25_alice_test"}'::jsonb),
    ('00000000-0000-0000-0000-000000000402', 'm25-bob@example.invalid', '{"username": "m25_bob_test"}'::jsonb),
    ('00000000-0000-0000-0000-000000000403', 'm25-carol@example.invalid', '{"username": "m25_carol_test"}'::jsonb)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- Test 1: a new follow produces exactly one correct notification —
-- type='follow', recipient=bob (followed), actor=alice (follower),
-- build_id/comment_id both null.
-- ---------------------------------------------------------------------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000401', true);
set local role authenticated;
do $$
declare
    v_result record;
begin
    select * into v_result from public.set_follow('00000000-0000-0000-0000-000000000402'::uuid, true);

    if v_result.followed = true and v_result.followers_count = 1 and v_result.following_count = 1 then
        raise notice 'PASS (test 1a): set_follow() returns the correct followed/followers_count/following_count shape';
    else
        raise warning 'FAIL (test 1a): unexpected result: followed=%, followers_count=%, following_count=%', v_result.followed, v_result.followers_count, v_result.following_count;
    end if;
end $$;
reset role;

-- Checked as the postgres connecting role (not alice or bob) to inspect
-- the raw row directly — this is fixture verification, not an RLS test
-- (that's test 7 below).
do $$
declare
    v_count int;
    v_row public.notifications;
begin
    select count(*) into v_count from public.notifications where type = 'follow';

    select * into v_row from public.notifications where type = 'follow' limit 1;

    if v_count = 1
        and v_row.recipient_id = '00000000-0000-0000-0000-000000000402'
        and v_row.actor_id = '00000000-0000-0000-0000-000000000401'
        and v_row.build_id is null
        and v_row.comment_id is null
    then
        raise notice 'PASS (test 1b): exactly one follow notification, correct recipient/actor, null build_id/comment_id';
    else
        raise warning 'FAIL (test 1b): count=%, recipient=%, actor=%, build_id=%, comment_id=%', v_count, v_row.recipient_id, v_row.actor_id, v_row.build_id, v_row.comment_id;
    end if;
end $$;
-- NOT rolled back — tests 2-3 need this follow's committed state.

-- ---------------------------------------------------------------------
-- Test 2: repeating the same desired follow state (already following,
-- calling set_follow(..., true) again) creates no duplicate follow row
-- and no duplicate notification.
-- ---------------------------------------------------------------------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000401', true);
set local role authenticated;
do $$
begin
    perform public.set_follow('00000000-0000-0000-0000-000000000402'::uuid, true);
end $$;
reset role;

do $$
declare
    v_follow_count int;
    v_notif_count int;
begin
    select count(*) into v_follow_count from public.follows
        where follower_id = '00000000-0000-0000-0000-000000000401'
            and following_id = '00000000-0000-0000-0000-000000000402';

    select count(*) into v_notif_count from public.notifications where type = 'follow';

    if v_follow_count = 1 and v_notif_count = 1 then
        raise notice 'PASS (test 2): repeating an already-active follow creates no duplicate row and no duplicate notification';
    else
        raise warning 'FAIL (test 2): follow_count=%, notif_count=% (expected 1 and 1)', v_follow_count, v_notif_count;
    end if;
end $$;

-- ---------------------------------------------------------------------
-- Test 3: the atomic ON CONFLICT DO NOTHING RETURNING mechanism itself
-- — three back-to-back calls against the same already-active follow,
-- simulating rapid/repeated requests hitting the same guard. See this
-- file's header for the harness's honest concurrency-testing limits and
-- the Milestone 24 precedent this pattern's true multi-connection safety
-- already rests on.
-- ---------------------------------------------------------------------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000401', true);
set local role authenticated;
do $$
begin
    perform public.set_follow('00000000-0000-0000-0000-000000000402'::uuid, true);
    perform public.set_follow('00000000-0000-0000-0000-000000000402'::uuid, true);
    perform public.set_follow('00000000-0000-0000-0000-000000000402'::uuid, true);
end $$;
reset role;

do $$
declare
    v_follow_count int;
    v_notif_count int;
begin
    select count(*) into v_follow_count from public.follows
        where follower_id = '00000000-0000-0000-0000-000000000401'
            and following_id = '00000000-0000-0000-0000-000000000402';

    select count(*) into v_notif_count from public.notifications where type = 'follow';

    if v_follow_count = 1 and v_notif_count = 1 then
        raise notice 'PASS (test 3): repeated rapid follow requests never produce more than one follow row or one notification';
    else
        raise warning 'FAIL (test 3): follow_count=%, notif_count=% (expected 1 and 1)', v_follow_count, v_notif_count;
    end if;
end $$;

-- ---------------------------------------------------------------------
-- Test 4: unfollow produces no new notification.
-- ---------------------------------------------------------------------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000401', true);
set local role authenticated;
do $$
declare
    v_result record;
begin
    select * into v_result from public.set_follow('00000000-0000-0000-0000-000000000402'::uuid, false);

    if v_result.followed = false and v_result.followers_count = 0 then
        raise notice 'PASS (test 4a): unfollow returns followed=false, followers_count=0';
    else
        raise warning 'FAIL (test 4a): followed=%, followers_count=%', v_result.followed, v_result.followers_count;
    end if;
end $$;
reset role;

do $$
declare
    v_notif_count int;
begin
    select count(*) into v_notif_count from public.notifications where type = 'follow';

    if v_notif_count = 1 then
        raise notice 'PASS (test 4b): unfollow created no new notification (still exactly the one from test 1)';
    else
        raise warning 'FAIL (test 4b): found % follow notification(s) after unfollow, expected still 1', v_notif_count;
    end if;
end $$;

-- ---------------------------------------------------------------------
-- Test 5: refollow after a genuine unfollow produces exactly one NEW
-- notification (total now 2).
-- ---------------------------------------------------------------------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000401', true);
set local role authenticated;
do $$
begin
    perform public.set_follow('00000000-0000-0000-0000-000000000402'::uuid, true);
end $$;
reset role;

do $$
declare
    v_notif_count int;
begin
    select count(*) into v_notif_count from public.notifications where type = 'follow';

    if v_notif_count = 2 then
        raise notice 'PASS (test 5): refollowing after a genuine unfollow creates exactly one new notification (total 2)';
    else
        raise warning 'FAIL (test 5): found % follow notification(s), expected 2', v_notif_count;
    end if;
end $$;

-- ---------------------------------------------------------------------
-- Test 6: self-follow remains rejected — both the app-level check and
-- the table's own CHECK constraint are untouched by this migration.
-- ---------------------------------------------------------------------
savepoint test_6;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000401', true);
set local role authenticated;
do $$
declare
    v_raised boolean := false;
    v_message text;
begin
    begin
        perform public.set_follow('00000000-0000-0000-0000-000000000401'::uuid, true);
    exception when others then
        v_raised := true;
        get stacked diagnostics v_message = message_text;
    end;

    if v_raised and v_message ilike '%cannot follow yourself%' then
        raise notice 'PASS (test 6): self-follow is still rejected with the exact pre-0037 message';
    else
        raise warning 'FAIL (test 6): expected self-follow rejection, got raised=%, message=%', v_raised, v_message;
    end if;
end $$;
reset role;
rollback to savepoint test_6;

-- ---------------------------------------------------------------------
-- Test 7: an unrelated, uninvolved user (carol — not alice or bob)
-- cannot read bob's follow notification. RLS is unchanged by this
-- migration; this confirms it still holds for the new type.
-- ---------------------------------------------------------------------
savepoint test_7;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000403', true);
set local role authenticated;
do $$
declare
    v_count int;
begin
    select count(*) into v_count from public.notifications where type = 'follow';

    if v_count = 0 then
        raise notice 'PASS (test 7): an uninvolved user sees 0 follow notifications belonging to someone else';
    else
        raise warning 'FAIL (test 7): uninvolved user saw % row(s), expected 0', v_count;
    end if;
end $$;
reset role;
rollback to savepoint test_7;

-- ---------------------------------------------------------------------
-- Test 8: direct notification forgery remains impossible — a client
-- cannot call create_notification() directly (it has zero grants to any
-- role, unchanged by this migration) to fabricate a fake 'follow' event.
-- ---------------------------------------------------------------------
savepoint test_8;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000401', true);
set local role authenticated;
do $$
declare
    v_raised boolean := false;
begin
    begin
        perform public.create_notification(
            '00000000-0000-0000-0000-000000000402'::uuid,
            '00000000-0000-0000-0000-000000000401'::uuid,
            'follow'
        );
    exception when others then
        v_raised := true;
    end;

    if v_raised then
        raise notice 'PASS (test 8): a client still cannot call create_notification() directly — no EXECUTE grant to any role';
    else
        raise warning 'FAIL (test 8): a client was able to call create_notification() directly, forging a notification';
    end if;
end $$;
reset role;
rollback to savepoint test_8;

-- ---------------------------------------------------------------------
-- Test 9: notifications_type_check accepts 'follow' and still rejects
-- an unknown type — proven directly against the constraint, not
-- inferred from set_follow()'s success in tests 1/3/5 above.
-- ---------------------------------------------------------------------
savepoint test_9;
do $$
declare
    v_accepted_follow boolean := false;
    v_rejected_bogus boolean := false;
begin
    begin
        insert into public.notifications (recipient_id, actor_id, type)
        values ('00000000-0000-0000-0000-000000000402', '00000000-0000-0000-0000-000000000401', 'follow');
        v_accepted_follow := true;
    exception when others then
        v_accepted_follow := false;
    end;

    begin
        insert into public.notifications (recipient_id, actor_id, type)
        values ('00000000-0000-0000-0000-000000000402', '00000000-0000-0000-0000-000000000401', 'not_a_real_type');
    exception when others then
        v_rejected_bogus := true;
    end;

    if v_accepted_follow and v_rejected_bogus then
        raise notice 'PASS (test 9): notifications_type_check accepts ''follow'' and rejects an unknown type';
    else
        raise warning 'FAIL (test 9): accepted_follow=%, rejected_bogus=%', v_accepted_follow, v_rejected_bogus;
    end if;
end $$;
rollback to savepoint test_9;

-- ---------------------------------------------------------------------
-- Test 10: existing follow RPC return behavior remains fully
-- compatible — a fresh pair (not alice/bob, to avoid any prior-test
-- follow-state interference) exercises the exact same return shape
-- (followed, followers_count, following_count) proven correct pre-0037.
-- ---------------------------------------------------------------------
savepoint test_10;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000403', true);
set local role authenticated;
do $$
declare
    v_result record;
begin
    select * into v_result from public.set_follow('00000000-0000-0000-0000-000000000401'::uuid, true);

    if v_result.followed = true
        and v_result.followers_count is not null
        and v_result.following_count is not null
    then
        raise notice 'PASS (test 10): set_follow()''s return shape (followed, followers_count, following_count) is unchanged';
    else
        raise warning 'FAIL (test 10): unexpected shape: followed=%, followers_count=%, following_count=%', v_result.followed, v_result.followers_count, v_result.following_count;
    end if;
end $$;
reset role;
rollback to savepoint test_10;

-- ---------------------------------------------------------------------
-- Test 11: the safe rollback restores pre-0037 follow behavior without
-- deleting or invalidating any existing 'follow' notification row.
-- Applies the rollback file's CREATE OR REPLACE body inline (same
-- content as supabase/rollbacks/0037_follow_notifications_rollback.sql)
-- rather than shelling out to a separate file, so this stays inside the
-- same transaction/rollback-to-savepoint harness as every other test
-- here. Restored again to the 0037 body immediately after, so no
-- savepoint rollback is relied upon to undo a function redefinition
-- (DDL-ish function replacement isn't guaranteed to interact cleanly
-- with a savepoint the same way row data does — restoring explicitly is
-- the honest, unambiguous approach).
-- ---------------------------------------------------------------------
do $$
begin
    -- Apply the rollback body: pre-0037 set_follow(), no notification call.
    execute $rb$
        create or replace function public.set_follow(
            p_following_id uuid,
            p_followed boolean
        )
        returns table(followed boolean, followers_count integer, following_count integer)
        language plpgsql
        security definer
        set search_path = public, pg_temp
        as $body$
        declare
            v_follower_id uuid := auth.uid();
        begin
            if v_follower_id is null then
                raise exception 'You must be signed in to follow a builder.';
            end if;

            if v_follower_id = p_following_id then
                raise exception 'You cannot follow yourself.';
            end if;

            if not exists (select 1 from public.profiles where id = p_following_id) then
                raise exception 'Builder not found.';
            end if;

            if p_followed then
                insert into public.follows (follower_id, following_id)
                values (v_follower_id, p_following_id)
                on conflict (follower_id, following_id) do nothing;
            else
                delete from public.follows
                    where follower_id = v_follower_id and following_id = p_following_id;
            end if;

            return query
                select
                    exists(
                        select 1 from public.follows f
                        where f.follower_id = v_follower_id and f.following_id = p_following_id
                    ),
                    coalesce(
                        (select p.followers_count from public.profiles p where p.id = p_following_id),
                        0
                    ),
                    coalesce(
                        (select p.following_count from public.profiles p where p.id = v_follower_id),
                        0
                    );
        end;
        $body$;
    $rb$;
end $$;

-- With the rollback applied, a NEW follow (a fresh pair, not previously
-- followed) must create no notification.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000402', true);
set local role authenticated;
do $$
begin
    perform public.set_follow('00000000-0000-0000-0000-000000000403'::uuid, true);
end $$;
reset role;

do $$
declare
    v_new_pair_notif_count int;
begin
    select count(*) into v_new_pair_notif_count from public.notifications
        where type = 'follow'
            and recipient_id = '00000000-0000-0000-0000-000000000403'
            and actor_id = '00000000-0000-0000-0000-000000000402';

    if v_new_pair_notif_count = 0 then
        raise notice 'PASS (test 11a): after the behavioral rollback, a genuinely new follow creates NO notification — future-follow behavior correctly reverted';
    else
        raise warning 'FAIL (test 11a): a new follow after rollback created % notification(s), expected 0', v_new_pair_notif_count;
    end if;
end $$;

do $$
declare
    v_preserved_count int;
begin
    select count(*) into v_preserved_count from public.notifications
        where type = 'follow'
            and recipient_id = '00000000-0000-0000-0000-000000000402'
            and actor_id = '00000000-0000-0000-0000-000000000401';

    if v_preserved_count = 2 then
        raise notice 'PASS (test 11b): the two existing follow notifications from before the rollback are fully preserved — not deleted, not invalidated';
    else
        raise warning 'FAIL (test 11b): found % pre-rollback follow notification(s), expected 2 preserved', v_preserved_count;
    end if;
end $$;

do $$
declare
    v_check_still_allows_follow boolean := false;
    v_throwaway_id uuid;
begin
    begin
        insert into public.notifications (recipient_id, actor_id, type)
        values ('00000000-0000-0000-0000-000000000402', '00000000-0000-0000-0000-000000000401', 'follow')
        returning id into v_throwaway_id;
        v_check_still_allows_follow := true;
        delete from public.notifications where id = v_throwaway_id;
    exception when others then
        v_check_still_allows_follow := false;
    end;

    if v_check_still_allows_follow then
        raise notice 'PASS (test 11c): notifications_type_check still accepts ''follow'' after the behavioral rollback — the CHECK was deliberately NOT narrowed';
    else
        raise warning 'FAIL (test 11c): notifications_type_check rejected ''follow'' after rollback — existing follow rows would now violate their own constraint';
    end if;
end $$;

-- Restore the 0037 (current) body so the rest of this file/session isn't
-- left in the rolled-back state.
do $$
begin
    execute $fwd$
        create or replace function public.set_follow(
            p_following_id uuid,
            p_followed boolean
        )
        returns table(followed boolean, followers_count integer, following_count integer)
        language plpgsql
        security definer
        set search_path = public, pg_temp
        as $body$
        declare
            v_follower_id uuid := auth.uid();
            v_inserted_id uuid;
        begin
            if v_follower_id is null then
                raise exception 'You must be signed in to follow a builder.';
            end if;

            if v_follower_id = p_following_id then
                raise exception 'You cannot follow yourself.';
            end if;

            if not exists (select 1 from public.profiles where id = p_following_id) then
                raise exception 'Builder not found.';
            end if;

            if p_followed then
                insert into public.follows (follower_id, following_id)
                values (v_follower_id, p_following_id)
                on conflict (follower_id, following_id) do nothing
                returning id into v_inserted_id;

                if v_inserted_id is not null then
                    perform public.create_notification(p_following_id, v_follower_id, 'follow');
                end if;
            else
                delete from public.follows
                    where follower_id = v_follower_id and following_id = p_following_id;
            end if;

            return query
                select
                    exists(
                        select 1 from public.follows f
                        where f.follower_id = v_follower_id and f.following_id = p_following_id
                    ),
                    coalesce(
                        (select p.followers_count from public.profiles p where p.id = p_following_id),
                        0
                    ),
                    coalesce(
                        (select p.following_count from public.profiles p where p.id = v_follower_id),
                        0
                    );
        end;
        $body$;
    $fwd$;
end $$;

rollback;
