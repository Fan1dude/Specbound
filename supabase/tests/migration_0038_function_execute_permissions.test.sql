-- Migration 0038 function-permission test —
-- supabase/tests/migration_0038_function_execute_permissions.test.sql
--
-- Covers the EXECUTE-permission hardening in migration 0038
-- (restrict_pre_0020_function_execute_permissions): proves, at the
-- database level, that the ten pre-0020 functions 0038 touches now
-- reject `anon` (both at the catalog/ACL level and at the actual grant
-- check when called), that `authenticated` retains EXECUTE and reaches
-- each function's own body (a business-logic rejection with a garbage
-- argument is success for THIS test — see the SQLSTATE-distinguishing
-- convention below, inherited verbatim from
-- migration_0033_function_execute_permissions.test.sql), that the three
-- intentionally-public functions 0038 explicitly leaves alone
-- (get_activity_feed, record_build_view, get_public_profile_roles) are
-- still callable by anon, that create_notification() remains
-- unreachable by any client role, that service_role/the function owner
-- keep whatever access they already had, and that the paired rollback
-- restores the exact pre-0038 grants (to the named `anon` role only,
-- never broadening `PUBLIC`) and can be reapplied forward again.
--
-- STATUS: executed against the local disposable Supabase/Docker stack —
-- see this PR's own report for the exact assertion count and pass
-- result. NOT yet executed against a disposable/staging Supabase project
-- or against production; run it there too before trusting the result in
-- an environment closer to production. Depends on migrations 0001-0038
-- already being applied.
--
-- Never run this against a project with real data — same fixture-safety
-- posture as migration_0033_function_execute_permissions.test.sql (fake
-- auth.users rows, namespaced usernames, single outer transaction ending
-- in ROLLBACK, each test in its own SAVEPOINT).
--
-- Fail-closed design: identical convention to migration_0033's own file
-- — every FAIL is raised via `raise exception ... using errcode =
-- 'M0038'` (this file's own dedicated, made-up SQLSTATE, chosen to be
-- unmistakably ours and never collide with a built-in code), so a
-- deliberate FAIL can always be told apart from any other error the
-- tested functions might raise, and a WARNING alone never changes
-- psql's exit code the way `raise exception` does.
--
-- Permission testing convention: a nested `begin ... exception when
-- insufficient_privilege then ... end` block inside each `do $$ ... $$`
-- catches Postgres's own ACL rejection (SQLSTATE 42501) without
-- aborting the outer transaction — this is what distinguishes "the
-- database refused to run this at all" (what 0038 controls) from "the
-- function ran and its own business logic raised an error" (e.g.
-- "Project not found." — ordinary P0001 — for an authenticated caller
-- passing a nonexistent id). Every one of the ten functions' first
-- meaningful check after the auth.uid()-null guard is a plain "not
-- found" lookup against a random, guaranteed-nonexistent uuid — verified
-- by reading each function's current body directly before writing this
-- file — so no real build/draft/comment/notification fixture is needed
-- anywhere in this file to prove "authenticated reached the function
-- body": a random uuid safely produces a business-logic P0001, never a
-- successful write, keeping this file free of any real side effects
-- beyond its own two disposable auth.users rows.
--
-- Role-switch statements are top-level only, never inside a `do $$`
-- block, matching every other SQL test file in this repo.

begin;

insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-0000-0000-000000000501', 'm0038-user@example.invalid', '{"username": "m0038_user_test"}'::jsonb),
    ('00000000-0000-0000-0000-000000000502', 'm0038-recipient@example.invalid', '{"username": "m0038_recipient_test"}'::jsonb)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- Test 1: for each of the ten functions — signature exists, anon lacks
-- EXECUTE at the catalog level, authenticated retains it, and the
-- function is still SECURITY DEFINER with its safe search_path (proving
-- 0038 — a pure GRANT/REVOKE migration — didn't collaterally touch any
-- function body/signature). Data-driven: this is purely mechanical
-- metadata inspection, identical shape for all ten, so a loop over a
-- literal list is clearer than ten near-identical longhand blocks.
-- ---------------------------------------------------------------------
savepoint test_1;
do $$
declare
    v_name text;
    v_oid oid;
begin
    for v_name in select unnest(array[
        'public.create_comment(uuid, text)',
        'public.delete_comment(uuid)',
        'public.set_build_like(uuid, boolean)',
        'public.set_build_saved(uuid, boolean)',
        'public.mark_notification_read(uuid)',
        'public.mark_all_notifications_read()',
        'public.publish_draft(uuid, text, text)',
        'public.restore_revision_to_draft(uuid, timestamptz)',
        'public.set_build_visibility(uuid, text)',
        'public.set_follow(uuid, boolean)'
    ])
    loop
        v_oid := to_regprocedure(v_name);

        if v_oid is null then
            raise exception 'FAIL (test 1, %): function does not exist with the expected signature', v_name using errcode = 'M0038';
        end if;

        if has_function_privilege('anon', v_oid, 'EXECUTE') then
            raise exception 'FAIL (test 1, %): anon unexpectedly still has EXECUTE', v_name using errcode = 'M0038';
        end if;

        if not has_function_privilege('authenticated', v_oid, 'EXECUTE') then
            raise exception 'FAIL (test 1, %): authenticated unexpectedly lacks EXECUTE', v_name using errcode = 'M0038';
        end if;

        if not (select prosecdef from pg_proc where oid = v_oid) then
            raise exception 'FAIL (test 1, %): function is no longer SECURITY DEFINER — 0038 must never touch function bodies', v_name using errcode = 'M0038';
        end if;

        if not exists (
            select 1 from pg_proc where oid = v_oid
                and 'search_path=public, pg_temp' = any(proconfig)
        ) then
            raise exception 'FAIL (test 1, %): search_path is no longer "public, pg_temp" — 0038 must never touch function bodies', v_name using errcode = 'M0038';
        end if;

        raise notice 'PASS (test 1, %): exists, anon lacks EXECUTE, authenticated has EXECUTE, still SECURITY DEFINER with safe search_path', v_name;
    end loop;
end $$;
rollback to savepoint test_1;

-- ---------------------------------------------------------------------
-- Test 2: anon is rejected at the grant layer (SQLSTATE 42501), not
-- merely by internal business logic, for all ten functions — the actual
-- behavioral proof, not just the catalog check test 1 already did.
-- ---------------------------------------------------------------------
savepoint test_2;
set local role anon;
do $$
begin
    begin perform public.create_comment('00000000-0000-0000-0000-000000000000'::uuid, 'x');
        raise exception 'FAIL (test 2a): create_comment(uuid,text) was callable by anon' using errcode = 'M0038';
    exception when insufficient_privilege then
        raise notice 'PASS (test 2a): create_comment(uuid,text) correctly denied to anon (42501)';
    end;

    begin perform public.delete_comment('00000000-0000-0000-0000-000000000000'::uuid);
        raise exception 'FAIL (test 2b): delete_comment(uuid) was callable by anon' using errcode = 'M0038';
    exception when insufficient_privilege then
        raise notice 'PASS (test 2b): delete_comment(uuid) correctly denied to anon (42501)';
    end;

    begin perform public.set_build_like('00000000-0000-0000-0000-000000000000'::uuid, true);
        raise exception 'FAIL (test 2c): set_build_like(uuid,boolean) was callable by anon' using errcode = 'M0038';
    exception when insufficient_privilege then
        raise notice 'PASS (test 2c): set_build_like(uuid,boolean) correctly denied to anon (42501)';
    end;

    begin perform public.set_build_saved('00000000-0000-0000-0000-000000000000'::uuid, true);
        raise exception 'FAIL (test 2d): set_build_saved(uuid,boolean) was callable by anon' using errcode = 'M0038';
    exception when insufficient_privilege then
        raise notice 'PASS (test 2d): set_build_saved(uuid,boolean) correctly denied to anon (42501)';
    end;

    begin perform public.mark_notification_read('00000000-0000-0000-0000-000000000000'::uuid);
        raise exception 'FAIL (test 2e): mark_notification_read(uuid) was callable by anon' using errcode = 'M0038';
    exception when insufficient_privilege then
        raise notice 'PASS (test 2e): mark_notification_read(uuid) correctly denied to anon (42501)';
    end;

    begin perform public.mark_all_notifications_read();
        raise exception 'FAIL (test 2f): mark_all_notifications_read() was callable by anon' using errcode = 'M0038';
    exception when insufficient_privilege then
        raise notice 'PASS (test 2f): mark_all_notifications_read() correctly denied to anon (42501)';
    end;

    begin perform public.publish_draft('00000000-0000-0000-0000-000000000000'::uuid, 'v', 'n');
        raise exception 'FAIL (test 2g): publish_draft(uuid,text,text) was callable by anon' using errcode = 'M0038';
    exception when insufficient_privilege then
        raise notice 'PASS (test 2g): publish_draft(uuid,text,text) correctly denied to anon (42501)';
    end;

    begin perform public.restore_revision_to_draft('00000000-0000-0000-0000-000000000000'::uuid, null);
        raise exception 'FAIL (test 2h): restore_revision_to_draft(uuid,timestamptz) was callable by anon' using errcode = 'M0038';
    exception when insufficient_privilege then
        raise notice 'PASS (test 2h): restore_revision_to_draft(uuid,timestamptz) correctly denied to anon (42501)';
    end;

    begin perform public.set_build_visibility('00000000-0000-0000-0000-000000000000'::uuid, 'private');
        raise exception 'FAIL (test 2i): set_build_visibility(uuid,text) was callable by anon' using errcode = 'M0038';
    exception when insufficient_privilege then
        raise notice 'PASS (test 2i): set_build_visibility(uuid,text) correctly denied to anon (42501)';
    end;

    begin perform public.set_follow('00000000-0000-0000-0000-000000000000'::uuid, true);
        raise exception 'FAIL (test 2j): set_follow(uuid,boolean) was callable by anon' using errcode = 'M0038';
    exception when insufficient_privilege then
        raise notice 'PASS (test 2j): set_follow(uuid,boolean) correctly denied to anon (42501)';
    end;
end $$;
reset role;
rollback to savepoint test_2;

-- ---------------------------------------------------------------------
-- Test 3: authenticated reaches every function's own body — a
-- business-logic rejection (P0001, "... not found.") with a random
-- nonexistent uuid is success here; only insufficient_privilege (42501)
-- is a FAIL. mark_all_notifications_read() takes no id argument at all,
-- so it simply succeeds outright for a user with zero notifications.
-- ---------------------------------------------------------------------
savepoint test_3;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000501', true);
set local role authenticated;
do $$
begin
    begin perform public.create_comment('00000000-0000-0000-0000-000000000000'::uuid, 'x');
        raise notice 'PASS (test 3a): create_comment(uuid,text) reached its own logic as authenticated';
    exception
        when insufficient_privilege then raise exception 'FAIL (test 3a): create_comment(uuid,text) denied to authenticated' using errcode = 'M0038';
        when others then raise notice 'PASS (test 3a): create_comment(uuid,text) reached its own logic (%), not a permission error', sqlerrm;
    end;

    begin perform public.delete_comment('00000000-0000-0000-0000-000000000000'::uuid);
        raise notice 'PASS (test 3b): delete_comment(uuid) reached its own logic as authenticated';
    exception
        when insufficient_privilege then raise exception 'FAIL (test 3b): delete_comment(uuid) denied to authenticated' using errcode = 'M0038';
        when others then raise notice 'PASS (test 3b): delete_comment(uuid) reached its own logic (%), not a permission error', sqlerrm;
    end;

    begin perform public.set_build_like('00000000-0000-0000-0000-000000000000'::uuid, true);
        raise notice 'PASS (test 3c): set_build_like(uuid,boolean) reached its own logic as authenticated';
    exception
        when insufficient_privilege then raise exception 'FAIL (test 3c): set_build_like(uuid,boolean) denied to authenticated' using errcode = 'M0038';
        when others then raise notice 'PASS (test 3c): set_build_like(uuid,boolean) reached its own logic (%), not a permission error', sqlerrm;
    end;

    begin perform public.set_build_saved('00000000-0000-0000-0000-000000000000'::uuid, true);
        raise notice 'PASS (test 3d): set_build_saved(uuid,boolean) reached its own logic as authenticated';
    exception
        when insufficient_privilege then raise exception 'FAIL (test 3d): set_build_saved(uuid,boolean) denied to authenticated' using errcode = 'M0038';
        when others then raise notice 'PASS (test 3d): set_build_saved(uuid,boolean) reached its own logic (%), not a permission error', sqlerrm;
    end;

    begin perform public.mark_notification_read('00000000-0000-0000-0000-000000000000'::uuid);
        raise notice 'PASS (test 3e): mark_notification_read(uuid) reached its own logic as authenticated';
    exception
        when insufficient_privilege then raise exception 'FAIL (test 3e): mark_notification_read(uuid) denied to authenticated' using errcode = 'M0038';
        when others then raise notice 'PASS (test 3e): mark_notification_read(uuid) reached its own logic (%), not a permission error', sqlerrm;
    end;

    begin perform public.mark_all_notifications_read();
        raise notice 'PASS (test 3f): mark_all_notifications_read() executable by authenticated (returns a count, no error expected)';
    exception
        when insufficient_privilege then raise exception 'FAIL (test 3f): mark_all_notifications_read() denied to authenticated' using errcode = 'M0038';
        when others then raise exception 'FAIL (test 3f): mark_all_notifications_read() raised an unexpected error (%) for a plain signed-in call', sqlerrm using errcode = 'M0038';
    end;

    begin perform public.publish_draft('00000000-0000-0000-0000-000000000000'::uuid, 'v', 'n');
        raise notice 'PASS (test 3g): publish_draft(uuid,text,text) reached its own logic as authenticated';
    exception
        when insufficient_privilege then raise exception 'FAIL (test 3g): publish_draft(uuid,text,text) denied to authenticated' using errcode = 'M0038';
        when others then raise notice 'PASS (test 3g): publish_draft(uuid,text,text) reached its own logic (%), not a permission error', sqlerrm;
    end;

    begin perform public.restore_revision_to_draft('00000000-0000-0000-0000-000000000000'::uuid, null);
        raise notice 'PASS (test 3h): restore_revision_to_draft(uuid,timestamptz) reached its own logic as authenticated';
    exception
        when insufficient_privilege then raise exception 'FAIL (test 3h): restore_revision_to_draft(uuid,timestamptz) denied to authenticated' using errcode = 'M0038';
        when others then raise notice 'PASS (test 3h): restore_revision_to_draft(uuid,timestamptz) reached its own logic (%), not a permission error', sqlerrm;
    end;

    begin perform public.set_build_visibility('00000000-0000-0000-0000-000000000000'::uuid, 'private');
        raise notice 'PASS (test 3i): set_build_visibility(uuid,text) reached its own logic as authenticated';
    exception
        when insufficient_privilege then raise exception 'FAIL (test 3i): set_build_visibility(uuid,text) denied to authenticated' using errcode = 'M0038';
        when others then raise notice 'PASS (test 3i): set_build_visibility(uuid,text) reached its own logic (%), not a permission error', sqlerrm;
    end;

    begin perform public.set_follow('00000000-0000-0000-0000-000000000000'::uuid, true);
        raise notice 'PASS (test 3j): set_follow(uuid,boolean) reached its own logic as authenticated';
    exception
        when insufficient_privilege then raise exception 'FAIL (test 3j): set_follow(uuid,boolean) denied to authenticated' using errcode = 'M0038';
        when others then raise notice 'PASS (test 3j): set_follow(uuid,boolean) reached its own logic (%), not a permission error', sqlerrm;
    end;
end $$;
reset role;
rollback to savepoint test_3;

-- ---------------------------------------------------------------------
-- Test 4: the three intentionally-public functions 0038 explicitly
-- leaves alone remain callable by anon — a real, successful call for
-- get_activity_feed() and get_public_profile_roles() (both tolerate an
-- empty/nonexistent result set with no error), and a business-logic
-- "not found" (not insufficient_privilege) for record_build_view() with
-- a random build id, same not-found-is-success convention as test 3.
-- ---------------------------------------------------------------------
savepoint test_4;
set local role anon;
do $$
begin
    begin perform public.get_activity_feed('explore', null, null, 5);
        raise notice 'PASS (test 4a): get_activity_feed(...) still executable by anon after 0038';
    exception when insufficient_privilege then
        raise exception 'FAIL (test 4a): get_activity_feed(...) unexpectedly denied to anon after 0038' using errcode = 'M0038';
    end;

    begin perform public.record_build_view('00000000-0000-0000-0000-000000000000'::uuid, gen_random_uuid());
        raise notice 'PASS (test 4b): record_build_view(uuid,uuid) still reachable by anon after 0038 (business-logic "not found" is expected/OK)';
    exception
        when insufficient_privilege then raise exception 'FAIL (test 4b): record_build_view(uuid,uuid) unexpectedly denied to anon after 0038' using errcode = 'M0038';
        when others then raise notice 'PASS (test 4b): record_build_view(uuid,uuid) reached its own logic (%), not a permission error', sqlerrm;
    end;

    begin perform public.get_public_profile_roles('00000000-0000-0000-0000-000000000000'::uuid);
        raise notice 'PASS (test 4c): get_public_profile_roles(uuid) still executable by anon after 0038';
    exception when insufficient_privilege then
        raise exception 'FAIL (test 4c): get_public_profile_roles(uuid) unexpectedly denied to anon after 0038' using errcode = 'M0038';
    end;
end $$;
reset role;
rollback to savepoint test_4;

-- ---------------------------------------------------------------------
-- Test 5: create_notification() remains unavailable to both anon and
-- authenticated — a regression guard, not new coverage (0033 already
-- proved this; 0038 touches ten adjacent-but-different functions and
-- must not have loosened this one).
-- ---------------------------------------------------------------------
savepoint test_5_anon;
set local role anon;
do $$
begin
    begin perform public.create_notification(
            '00000000-0000-0000-0000-000000000502'::uuid,
            '00000000-0000-0000-0000-000000000501'::uuid,
            'comment'
        );
        raise exception 'FAIL (test 5a): create_notification(...) was callable by anon' using errcode = 'M0038';
    exception when insufficient_privilege then
        raise notice 'PASS (test 5a): create_notification(...) correctly denied to anon';
    end;
end $$;
reset role;
rollback to savepoint test_5_anon;

savepoint test_5_auth;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000501', true);
set local role authenticated;
do $$
begin
    begin perform public.create_notification(
            '00000000-0000-0000-0000-000000000502'::uuid,
            '00000000-0000-0000-0000-000000000501'::uuid,
            'comment'
        );
        raise exception 'FAIL (test 5b): create_notification(...) was callable by authenticated' using errcode = 'M0038';
    exception when insufficient_privilege then
        raise notice 'PASS (test 5b): create_notification(...) correctly denied to authenticated';
    end;
end $$;
reset role;
rollback to savepoint test_5_auth;

-- ---------------------------------------------------------------------
-- Test 6: service_role keeps whatever access it already had (0038 never
-- touches it), checked at the catalog level for all ten functions plus
-- one representative real call; the function owner (the connecting
-- role, since ownership always bypasses ACL checks entirely) is
-- likewise checked at the catalog level for all ten.
-- ---------------------------------------------------------------------
savepoint test_6;
do $$
declare
    v_name text;
    v_oid oid;
begin
    for v_name in select unnest(array[
        'public.create_comment(uuid, text)',
        'public.delete_comment(uuid)',
        'public.set_build_like(uuid, boolean)',
        'public.set_build_saved(uuid, boolean)',
        'public.mark_notification_read(uuid)',
        'public.mark_all_notifications_read()',
        'public.publish_draft(uuid, text, text)',
        'public.restore_revision_to_draft(uuid, timestamptz)',
        'public.set_build_visibility(uuid, text)',
        'public.set_follow(uuid, boolean)'
    ])
    loop
        v_oid := to_regprocedure(v_name);

        if not has_function_privilege('service_role', v_oid, 'EXECUTE') then
            raise exception 'FAIL (test 6, %): service_role unexpectedly lost EXECUTE', v_name using errcode = 'M0038';
        end if;

        if not has_function_privilege(current_user, v_oid, 'EXECUTE') then
            raise exception 'FAIL (test 6, %): the connecting/owning role unexpectedly lacks EXECUTE', v_name using errcode = 'M0038';
        end if;
    end loop;

    raise notice 'PASS (test 6): service_role and the connecting/owning role retain EXECUTE on all ten functions at the catalog level';
end $$;
rollback to savepoint test_6;

-- service_role bypasses RLS but NOT these functions' own internal
-- auth.uid()-null checks — Supabase's real server-side callers always
-- act on behalf of a specific user and set the JWT claim accordingly,
-- so the fixture user's claim is set here too, matching that real usage
-- rather than an artificial "service_role with no identity at all" case
-- these functions were never designed to accept from any role.
savepoint test_6_call;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000501', true);
set local role service_role;
do $$
begin
    begin perform public.mark_all_notifications_read();
        raise notice 'PASS (test 6b): mark_all_notifications_read() still actually callable by service_role';
    exception when insufficient_privilege then
        raise exception 'FAIL (test 6b): mark_all_notifications_read() unexpectedly denied to service_role' using errcode = 'M0038';
    end;
end $$;
reset role;
rollback to savepoint test_6_call;

-- ---------------------------------------------------------------------
-- Test 7: the rollback restores the exact pre-0038 grant on all ten
-- functions — to the named `anon` role only, never broadening `PUBLIC`
-- — and reapplying 0038's own REVOKE afterward restores the hardened
-- state again. Grants are plain SQL statements (unlike 0037's function
-- redefinition, no dollar-quoted DDL is needed here), so the rollback's
-- and migration's own statements are run verbatim, top-level, exactly
-- as they appear in the real files.
-- ---------------------------------------------------------------------
savepoint test_7;

-- Apply the rollback verbatim.
grant execute on function
    public.create_comment(uuid, text),
    public.delete_comment(uuid),
    public.set_build_like(uuid, boolean),
    public.set_build_saved(uuid, boolean),
    public.mark_notification_read(uuid),
    public.mark_all_notifications_read(),
    public.publish_draft(uuid, text, text),
    public.restore_revision_to_draft(uuid, timestamptz),
    public.set_build_visibility(uuid, text),
    public.set_follow(uuid, boolean)
to anon;

do $$
declare
    v_name text;
    v_oid oid;
    v_public_has_execute boolean;
begin
    for v_name in select unnest(array[
        'public.create_comment(uuid, text)',
        'public.delete_comment(uuid)',
        'public.set_build_like(uuid, boolean)',
        'public.set_build_saved(uuid, boolean)',
        'public.mark_notification_read(uuid)',
        'public.mark_all_notifications_read()',
        'public.publish_draft(uuid, text, text)',
        'public.restore_revision_to_draft(uuid, timestamptz)',
        'public.set_build_visibility(uuid, text)',
        'public.set_follow(uuid, boolean)'
    ])
    loop
        v_oid := to_regprocedure(v_name);

        if not has_function_privilege('anon', v_oid, 'EXECUTE') then
            raise exception 'FAIL (test 7a, %): rollback did not restore anon EXECUTE', v_name using errcode = 'M0038';
        end if;

        -- PUBLIC is a pseudo-role (grantee oid 0 in an exploded ACL), not
        -- a real pg_roles row — checked directly, same technique as
        -- migration_0033's own test 7b, rather than via
        -- has_function_privilege('public', ...) which would error.
        select exists (
            select 1 from pg_proc p
            cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) as a
            where p.oid = v_oid and a.grantee = 0 and a.privilege_type = 'EXECUTE'
        ) into v_public_has_execute;

        if v_public_has_execute then
            raise exception 'FAIL (test 7b, %): rollback unexpectedly granted PUBLIC, not just anon', v_name using errcode = 'M0038';
        end if;
    end loop;

    raise notice 'PASS (test 7a/7b): rollback restored anon EXECUTE on all ten functions, without ever granting PUBLIC';
end $$;

-- Reapply migration 0038's own REVOKE, verbatim, to restore the
-- hardened state before this savepoint is rolled back.
revoke execute on function
    public.create_comment(uuid, text),
    public.delete_comment(uuid),
    public.set_build_like(uuid, boolean),
    public.set_build_saved(uuid, boolean),
    public.mark_notification_read(uuid),
    public.mark_all_notifications_read(),
    public.publish_draft(uuid, text, text),
    public.restore_revision_to_draft(uuid, timestamptz),
    public.set_build_visibility(uuid, text),
    public.set_follow(uuid, boolean)
from anon;

do $$
declare
    v_name text;
    v_oid oid;
begin
    for v_name in select unnest(array[
        'public.create_comment(uuid, text)',
        'public.delete_comment(uuid)',
        'public.set_build_like(uuid, boolean)',
        'public.set_build_saved(uuid, boolean)',
        'public.mark_notification_read(uuid)',
        'public.mark_all_notifications_read()',
        'public.publish_draft(uuid, text, text)',
        'public.restore_revision_to_draft(uuid, timestamptz)',
        'public.set_build_visibility(uuid, text)',
        'public.set_follow(uuid, boolean)'
    ])
    loop
        v_oid := to_regprocedure(v_name);

        if has_function_privilege('anon', v_oid, 'EXECUTE') then
            raise exception 'FAIL (test 7c, %): reapplying 0038 did not restore the hardened (anon-free) state', v_name using errcode = 'M0038';
        end if;
    end loop;

    raise notice 'PASS (test 7c): reapplying migration 0038 after the rollback rehearsal restored the hardened state on all ten functions';
end $$;

-- Not rolled back to test_7 here on purpose: leaving the hardened state
-- in place through the rest of this file (there is no test after this
-- one that depends on the pre-0038 state) is more honest than silently
-- reverting via SAVEPOINT and relying on that to "undo" the rehearsal —
-- the explicit reapply above IS the real state this file leaves behind
-- for the remainder of the transaction, matching what actually happened
-- (rollback rehearsed, then forward-restored), not a shortcut around it.

-- ---------------------------------------------------------------------
-- Cleanup: remove the two disposable auth.users rows created above.
-- Redundant with the final ROLLBACK below (nothing in this file is ever
-- committed), but explicit for the same defense-in-depth reasoning
-- documented in migration_0033's own test 7 header.
-- ---------------------------------------------------------------------
delete from auth.users where email like 'm0038-%@example.invalid';

rollback;
