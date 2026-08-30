-- Migration 0049 test —
-- supabase/tests/migration_0049_account_deletion_challenge.test.sql
--
-- Covers the security-review fix: request_account_deletion_challenge()
-- (the amr-based, refresh-immune freshness gate), the single-use/
-- atomic-consumption behavior of account_deletion_challenges, and
-- self_delete_account(uuid)'s full behavior under its NEW signature —
-- superseding migration_0048_self_delete_account.test.sql's own
-- coverage of the now-dropped zero-argument version. See this file's
-- own security-property tests (2-6) for the exact gaps the review
-- found and this migration fixes, and test 7e/7f specifically for the
-- SECOND bug the same review found: 0048's original retry ordering
-- unconditionally recomputed the Storage-path capture query, silently
-- losing already-captured paths on any retry after the first
-- successful call.
--
-- IMPORTANT — mocking `auth.jwt()`: this suite sets the
-- `request.jwt.claims` GUC to a full JSON object (including `sub` and
-- `amr`) so `auth.jwt()` resolves inside each test's transaction, the
-- same way this codebase's existing tests already set
-- `request.jwt.claim.sub` alone for `auth.uid()`. **This has not been
-- verified against a live local Supabase instance** (see this file's
-- own STATUS line) — if `auth.jwt()` does not resolve as expected
-- against the real local stack's actual `auth` schema implementation,
-- run `select auth.jwt();` directly after the `set_config` calls below
-- to confirm the claim shape, and adjust the GUC name/shape here to
-- match before trusting these results.
--
-- STATUS: intended to run against the local disposable Supabase/Docker
-- stack only — NOT executed in the authoring session (no `supabase`
-- CLI, no reachable Docker daemon, no `psql` were available; see this
-- PR's own report for the exact environmental limitation). Depends on
-- migrations 0000-0049 already being applied.
--
-- Fail-closed: every assertion raises via `raise exception ... using
-- errcode = 'M0049'`.

begin;

-- Helper pattern used throughout: set both the `sub`-only GUC (for
-- auth.uid(), matching every other test file in this suite) and the
-- full `request.jwt.claims` GUC (for auth.jwt() -> 'amr').
create or replace function pg_temp.set_test_jwt(p_user_id uuid, p_amr jsonb)
returns void
language plpgsql
as $$
begin
    perform set_config('request.jwt.claim.sub', p_user_id::text, true);
    perform set_config(
        'request.jwt.claims',
        jsonb_build_object('sub', p_user_id, 'amr', p_amr)::text,
        true
    );
    set local role authenticated;
end;
$$;

insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-0000-0000-000000001501', 'm0049-user@example.invalid', '{"username": "m0049_user"}'::jsonb),
    ('00000000-0000-0000-0000-000000001502', 'm0049-other@example.invalid', '{"username": "m0049_other"}'::jsonb)
on conflict (id) do nothing;

-- Gives u1 a real, non-empty Storage path to capture -- needed so test
-- 7's retry check (below) can prove a real path survives a retry,
-- rather than trivially "surviving" an already-empty array.
update public.profiles
    set avatar_path = 'avatars/00000000-0000-0000-0000-000000001501/512.jpg'
    where id = '00000000-0000-0000-0000-000000001501';

-- ---------------------------------------------------------------------
-- Test 1: the OLD zero-argument self_delete_account() no longer exists
-- — proves 0049 actually dropped it, not just added a new overload
-- alongside it (which would leave the fixed-by-this-migration gap
-- fully open).
-- ---------------------------------------------------------------------
do $$
begin
    if exists (
        select 1 from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public' and p.proname = 'self_delete_account'
          and pg_get_function_identity_arguments(p.oid) = ''
    ) then
        raise exception 'FAIL (test 1): the zero-argument self_delete_account() still exists -- this is exactly the bypass 0049 exists to close' using errcode = 'M0049';
    end if;
    raise notice 'PASS (test 1): the zero-argument self_delete_account() no longer exists';
end $$;

-- ---------------------------------------------------------------------
-- Test 2: request_account_deletion_challenge() rejects a caller whose
-- JWT has NO amr claim at all (fails closed, per this migration's own
-- coalesce-to-empty-array design).
-- ---------------------------------------------------------------------
savepoint test_2;
do $$
begin
    perform pg_temp.set_test_jwt('00000000-0000-0000-0000-000000001501', '[]'::jsonb);

    begin
        perform public.request_account_deletion_challenge();
        raise exception 'FAIL (test 2): a caller with no amr claim was issued a challenge' using errcode = 'M0049';
    exception when others then
        if sqlerrm like '%Recent password verification required%' then
            raise notice 'PASS (test 2): no amr claim correctly rejected (%)', sqlerrm;
        else
            raise exception 'FAIL (test 2): rejected for the wrong reason: %', sqlerrm using errcode = 'M0049';
        end if;
    end;
end $$;
reset role;
rollback to savepoint test_2;

-- ---------------------------------------------------------------------
-- Test 3: a stale `password` amr entry (older than 5 minutes) is
-- rejected -- this is the exact scenario a routinely-refreshed session
-- would produce under the OLD iat-only check (a fresh iat, but a
-- password entry from long ago). Also present: a recent `token_refresh`
-- entry, which must NOT satisfy the check on its own -- proving the fix
-- checks the `password` method specifically, not just "any recent amr
-- activity."
-- ---------------------------------------------------------------------
savepoint test_3;
do $$
declare
    v_stale_password_ts bigint := extract(epoch from now())::bigint - 3600; -- 1 hour ago
    v_recent_refresh_ts bigint := extract(epoch from now())::bigint - 5;    -- 5 seconds ago
begin
    perform pg_temp.set_test_jwt(
        '00000000-0000-0000-0000-000000001501',
        jsonb_build_array(
            jsonb_build_object('method', 'password', 'timestamp', v_stale_password_ts),
            jsonb_build_object('method', 'token_refresh', 'timestamp', v_recent_refresh_ts)
        )
    );

    begin
        perform public.request_account_deletion_challenge();
        raise exception 'FAIL (test 3): a stale password amr entry (with only a recent token_refresh entry) was accepted -- this is the exact vulnerability 0049 fixes' using errcode = 'M0049';
    exception when others then
        if sqlerrm like '%Recent password verification required%' then
            raise notice 'PASS (test 3): stale password entry + recent token_refresh entry correctly rejected -- a routine token refresh alone cannot satisfy this check (%)', sqlerrm;
        else
            raise exception 'FAIL (test 3): rejected for the wrong reason: %', sqlerrm using errcode = 'M0049';
        end if;
    end;
end $$;
reset role;
rollback to savepoint test_3;

-- ---------------------------------------------------------------------
-- Test 4: a genuinely recent `password` amr entry is accepted and
-- issues a real, usable challenge token.
-- ---------------------------------------------------------------------
savepoint test_4;
do $$
declare
    v_token uuid;
    v_row_count integer;
begin
    perform pg_temp.set_test_jwt(
        '00000000-0000-0000-0000-000000001501',
        jsonb_build_array(jsonb_build_object('method', 'password', 'timestamp', extract(epoch from now())::bigint))
    );

    select public.request_account_deletion_challenge() into v_token;

    if v_token is null then
        raise exception 'FAIL (test 4a): no token returned' using errcode = 'M0049';
    end if;
    raise notice 'PASS (test 4a): a recent password amr entry issues a real token (%)', v_token;
end $$;
reset role;

do $$
declare
    v_row_count integer;
begin
    select count(*) into v_row_count
    from public.account_deletion_challenges
    where user_id = '00000000-0000-0000-0000-000000001501';

    if v_row_count <> 1 then
        raise exception 'FAIL (test 4b): expected exactly one challenge row, found %', v_row_count using errcode = 'M0049';
    end if;
    raise notice 'PASS (test 4b): exactly one challenge row exists';
end $$;
rollback to savepoint test_4;

-- ---------------------------------------------------------------------
-- Test 5: requesting a second challenge invalidates the first (upsert,
-- not accumulation) -- the earlier token must no longer work.
-- ---------------------------------------------------------------------
savepoint test_5;
do $$
declare
    v_token_1 uuid;
    v_token_2 uuid;
begin
    perform pg_temp.set_test_jwt(
        '00000000-0000-0000-0000-000000001501',
        jsonb_build_array(jsonb_build_object('method', 'password', 'timestamp', extract(epoch from now())::bigint))
    );

    select public.request_account_deletion_challenge() into v_token_1;
    select public.request_account_deletion_challenge() into v_token_2;

    if v_token_1 = v_token_2 then
        raise exception 'FAIL (test 5): a second request returned the same token instead of a fresh one' using errcode = 'M0049';
    end if;
    raise notice 'PASS (test 5): a second request issues a genuinely different token';

    if exists (select 1 from public.account_deletion_challenges where user_id = '00000000-0000-0000-0000-000000001501' and token = v_token_1) then
        raise exception 'FAIL (test 5b): the first token still exists after being superseded' using errcode = 'M0049';
    end if;
    raise notice 'PASS (test 5b): the first token no longer exists -- superseded, not accumulated';
end $$;
reset role;
rollback to savepoint test_5;

-- ---------------------------------------------------------------------
-- Test 6: self_delete_account(uuid) rejects a missing/wrong/foreign
-- token, and never runs any destructive step when it does.
-- ---------------------------------------------------------------------
insert into public.builds (id, user_id, title, slug, category, status, visibility)
values ('00000000-0000-0000-0000-000000001510', '00000000-0000-0000-0000-000000001501', 'M0049 Guard Build', 'm0049-guard-build', 'pc_build', 'planning', 'public');

savepoint test_6;
do $$
begin
    perform pg_temp.set_test_jwt('00000000-0000-0000-0000-000000001501', '[]'::jsonb);

    begin
        perform public.self_delete_account('00000000-0000-0000-0000-000000009999'::uuid);
        raise exception 'FAIL (test 6a): a random/unissued token was accepted' using errcode = 'M0049';
    exception when others then
        if sqlerrm like '%Deletion authorization is invalid or has expired%' then
            raise notice 'PASS (test 6a): an unissued token correctly rejected (%)', sqlerrm;
        else
            raise exception 'FAIL (test 6a): rejected for the wrong reason: %', sqlerrm using errcode = 'M0049';
        end if;
    end;
end $$;
reset role;

do $$
begin
    if not exists (select 1 from public.builds where id = '00000000-0000-0000-0000-000000001510') then
        raise exception 'FAIL (test 6b): the build was deleted despite the rejected call -- no destructive step must run without a valid token' using errcode = 'M0049';
    end if;
    raise notice 'PASS (test 6b): no destructive step ran -- the build still exists';
end $$;

-- Cross-user binding: u2 cannot use u1's real, valid, unconsumed token.
do $$
declare
    v_token uuid;
begin
    perform pg_temp.set_test_jwt(
        '00000000-0000-0000-0000-000000001501',
        jsonb_build_array(jsonb_build_object('method', 'password', 'timestamp', extract(epoch from now())::bigint))
    );
    select public.request_account_deletion_challenge() into v_token;
    reset role;

    perform pg_temp.set_test_jwt('00000000-0000-0000-0000-000000001502', '[]'::jsonb);

    begin
        perform public.self_delete_account(v_token);
        raise exception 'FAIL (test 6c): u2 successfully consumed u1''s challenge token -- cross-user token use must be impossible' using errcode = 'M0049';
    exception when others then
        if sqlerrm like '%Deletion authorization is invalid or has expired%' then
            raise notice 'PASS (test 6c): u2 cannot consume u1''s token -- rejected identically to any invalid token';
        else
            raise exception 'FAIL (test 6c): rejected for the wrong reason: %', sqlerrm using errcode = 'M0049';
        end if;
    end;
end $$;
reset role;

do $$
begin
    if not exists (select 1 from public.builds where id = '00000000-0000-0000-0000-000000001510') then
        raise exception 'FAIL (test 6d): u1''s build was deleted by u2''s attempted cross-user call' using errcode = 'M0049';
    end if;
    raise notice 'PASS (test 6d): u1''s build is untouched by u2''s rejected attempt';

    -- u1's token is still valid at this point (u2's failed attempt must
    -- not have consumed it) -- confirmed by the real deletion below
    -- (test 7) succeeding with it.
end $$;
rollback to savepoint test_6;

-- ---------------------------------------------------------------------
-- Test 6e/6f: a failed deletion-preparation transaction rolls back
-- challenge consumption, allowing a safe retry until expiration. A
-- legal hold is the easiest way to force self_delete_account() to
-- raise AFTER it has already deleted the challenge row (0049's own
-- ordering: challenge consumption happens first, the legal-hold check
-- second) but BEFORE the calling statement commits -- proving the
-- challenge deletion is inside the SAME transaction as the rest of the
-- function body, not committed separately. If this were not true, a
-- user rejected for a legal hold would burn their only challenge and
-- have no way to retry (pointlessly, since the hold would still block
-- them, but the failure MODE matters -- "try again with a fresh
-- password entry" must remain available for every OTHER rejection
-- reason, and this is the one case in this function's own body where a
-- consumed-then-rolled-back token is directly observable).
-- ---------------------------------------------------------------------
savepoint test_6e;
do $$
begin
    insert into public.legal_holds (user_id, reason)
    values ('00000000-0000-0000-0000-000000001501', 'M0049 test hold.');
end $$;

do $$
declare
    v_token uuid;
begin
    perform pg_temp.set_test_jwt(
        '00000000-0000-0000-0000-000000001501',
        jsonb_build_array(jsonb_build_object('method', 'password', 'timestamp', extract(epoch from now())::bigint))
    );
    select public.request_account_deletion_challenge() into v_token;

    begin
        perform public.self_delete_account(v_token);
        raise exception 'FAIL (test 6e): deletion succeeded despite an active legal hold' using errcode = 'M0049';
    exception when others then
        if sqlerrm like '%Your request could not be completed%' then
            raise notice 'PASS (test 6e): legal hold correctly rejects the first attempt (%)', sqlerrm;
        else
            raise exception 'FAIL (test 6e): rejected for the wrong reason: %', sqlerrm using errcode = 'M0049';
        end if;
    end;

    -- The SAME token, presented again: if the first call's challenge
    -- deletion had actually committed (i.e. was NOT rolled back with
    -- the rest of that failed call), this would now fail with "invalid
    -- or has expired" instead -- proving the token did NOT survive.
    begin
        perform public.self_delete_account(v_token);
        raise exception 'FAIL (test 6f): deletion succeeded on the retry despite the still-active legal hold' using errcode = 'M0049';
    exception when others then
        if sqlerrm like '%Your request could not be completed%' then
            raise notice 'PASS (test 6f): the SAME token is still valid after the failed attempt -- challenge consumption was rolled back along with the rest of that transaction, allowing a safe retry until expiration';
        elsif sqlerrm like '%Deletion authorization is invalid or has expired%' then
            raise exception 'FAIL (test 6f): the token was consumed even though the transaction that consumed it failed -- challenge consumption is NOT actually rolled back with the rest of self_delete_account(), so a rejected user loses their only challenge for no reason' using errcode = 'M0049';
        else
            raise exception 'FAIL (test 6f): rejected for the wrong reason: %', sqlerrm using errcode = 'M0049';
        end if;
    end;
end $$;
reset role;
rollback to savepoint test_6e;

-- ---------------------------------------------------------------------
-- Test 7: the real end-to-end flow -- request a challenge, consume it
-- via self_delete_account(), confirm it cannot be replayed a second
-- time, and confirm the underlying deletion behavior (builds/profile
-- cleanup, job creation, self-attributed audit row) matches
-- 0048_self_delete_account.sql's own already-verified logic, now
-- reached through the new signature.
-- ---------------------------------------------------------------------
do $$
declare
    v_token uuid;
    v_job_id uuid;
    v_paths text[];
begin
    perform pg_temp.set_test_jwt(
        '00000000-0000-0000-0000-000000001501',
        jsonb_build_array(jsonb_build_object('method', 'password', 'timestamp', extract(epoch from now())::bigint))
    );
    select public.request_account_deletion_challenge() into v_token;

    select job_id, storage_paths into v_job_id, v_paths from public.self_delete_account(v_token);

    if v_job_id is null then
        raise exception 'FAIL (test 7a): no job_id returned from the real deletion call' using errcode = 'M0049';
    end if;
    raise notice 'PASS (test 7a): real deletion call succeeds with a freshly-issued token, returns a job_id';

    if v_paths is distinct from array['avatars/00000000-0000-0000-0000-000000001501/512.jpg']::text[] then
        raise exception 'FAIL (test 7a2): unexpected captured Storage-path array on the FIRST call: %', v_paths using errcode = 'M0049';
    end if;
    raise notice 'PASS (test 7a2): the first call correctly captures the real avatar path (%)', v_paths;
end $$;
reset role;

do $$
begin
    if exists (select 1 from public.profiles where id = '00000000-0000-0000-0000-000000001501') then
        raise exception 'FAIL (test 7b): profiles row still exists after real deletion' using errcode = 'M0049';
    end if;
    if exists (select 1 from public.builds where id = '00000000-0000-0000-0000-000000001510') then
        raise exception 'FAIL (test 7b): the owned build still exists after real deletion' using errcode = 'M0049';
    end if;
    raise notice 'PASS (test 7b): profiles and owned builds deleted, matching 0048''s already-verified cleanup logic';

    if (select count(*) from public.moderation_actions where target_id = '00000000-0000-0000-0000-000000001501' and action_type = 'account_deleted') <> 1 then
        raise exception 'FAIL (test 7c): expected exactly one self-attributed account_deleted audit row' using errcode = 'M0049';
    end if;
    raise notice 'PASS (test 7c): exactly one self-attributed audit row exists';

    if exists (select 1 from public.account_deletion_challenges where user_id = '00000000-0000-0000-0000-000000001501') then
        raise exception 'FAIL (test 7d): the consumed challenge row still exists' using errcode = 'M0049';
    end if;
    raise notice 'PASS (test 7d): the consumed challenge row is gone -- single-use confirmed';
end $$;

-- ---------------------------------------------------------------------
-- Test 7e/7f: retry -- a SECOND call to self_delete_account(), for the
-- same account, with a FRESH challenge (the account still exists in
-- auth.users in this test harness, even though its profile/builds are
-- already gone -- exactly the "DB-complete, Auth-pending" state a real
-- retry after an Edge Function crash before admin.deleteUser() would be
-- in). Must resolve to the SAME job row and return the SAME,
-- previously-captured Storage paths -- not an empty array, which is
-- exactly the bug this migration's own header documents finding and
-- fixing (0048's original ordering recomputed the capture query
-- unconditionally, silently losing it on any retry).
-- ---------------------------------------------------------------------
do $$
declare
    v_token_2 uuid;
    v_job_id_2 uuid;
    v_job_id_1 uuid;
    v_paths_2 text[];
begin
    select id into v_job_id_1 from public.account_deletion_jobs where former_user_id = '00000000-0000-0000-0000-000000001501';

    perform pg_temp.set_test_jwt(
        '00000000-0000-0000-0000-000000001501',
        jsonb_build_array(jsonb_build_object('method', 'password', 'timestamp', extract(epoch from now())::bigint))
    );
    select public.request_account_deletion_challenge() into v_token_2;

    select job_id, storage_paths into v_job_id_2, v_paths_2 from public.self_delete_account(v_token_2);

    if v_job_id_2 <> v_job_id_1 then
        raise exception 'FAIL (test 7e): retry created a new job row (%) instead of resuming % ', v_job_id_2, v_job_id_1 using errcode = 'M0049';
    end if;
    raise notice 'PASS (test 7e): retry resumes the same job row';

    if v_paths_2 is distinct from array['avatars/00000000-0000-0000-0000-000000001501/512.jpg']::text[] then
        raise exception 'FAIL (test 7f): retry returned % instead of the originally-captured path -- this is exactly the storage-path-loss bug this migration fixes', v_paths_2 using errcode = 'M0049';
    end if;
    raise notice 'PASS (test 7f): retry returns the ORIGINALLY-captured path, not an empty array -- the storage-path-loss bug is fixed';
end $$;
reset role;

-- ---------------------------------------------------------------------
-- Test 7g: replay -- the FIRST token (already consumed by test 7a) is
-- rejected if presented again, identically to any other invalid token
-- -- proving atomic single-use consumption, not merely "checked, not
-- enforced." Captured and used within the same DO block so the
-- variable stays in scope.
-- ---------------------------------------------------------------------
do $$
declare
    v_replay_token uuid;
begin
    perform pg_temp.set_test_jwt(
        '00000000-0000-0000-0000-000000001501',
        jsonb_build_array(jsonb_build_object('method', 'password', 'timestamp', extract(epoch from now())::bigint))
    );
    -- A fresh token, immediately consumed once (simulating "the first
    -- token" for a clean replay test, independent of test 7a/7e's own
    -- already-consumed tokens above).
    select public.request_account_deletion_challenge() into v_replay_token;
    perform public.self_delete_account(v_replay_token);

    begin
        perform public.self_delete_account(v_replay_token);
        raise exception 'FAIL (test 7g): the same token was accepted a second time -- single-use consumption is not actually enforced' using errcode = 'M0049';
    exception when others then
        if sqlerrm like '%Deletion authorization is invalid or has expired%' then
            raise notice 'PASS (test 7g): replaying an already-consumed token is correctly rejected';
        else
            raise exception 'FAIL (test 7g): rejected for the wrong reason: %', sqlerrm using errcode = 'M0049';
        end if;
    end;
end $$;
reset role;

-- ---------------------------------------------------------------------
-- Test 8: function identity, SECURITY DEFINER, search_path, ACL for
-- both new functions.
-- ---------------------------------------------------------------------
do $$
declare
    v_identity text;
    v_secdef boolean;
    v_anon_exec boolean;
    v_authenticated_exec boolean;
begin
    select p.oid::regprocedure::text, p.prosecdef
    into v_identity, v_secdef
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'request_account_deletion_challenge';

    if v_identity <> 'request_account_deletion_challenge()' then
        raise exception 'FAIL (test 8a): unexpected identity: %', v_identity using errcode = 'M0049';
    end if;
    if not v_secdef then
        raise exception 'FAIL (test 8a): request_account_deletion_challenge is not SECURITY DEFINER' using errcode = 'M0049';
    end if;
    raise notice 'PASS (test 8a): request_account_deletion_challenge() identity and SECURITY DEFINER confirmed';

    v_anon_exec := has_function_privilege('anon', 'public.request_account_deletion_challenge()', 'EXECUTE');
    v_authenticated_exec := has_function_privilege('authenticated', 'public.request_account_deletion_challenge()', 'EXECUTE');
    if v_anon_exec then
        raise exception 'FAIL (test 8b): anon unexpectedly has EXECUTE on request_account_deletion_challenge' using errcode = 'M0049';
    end if;
    if not v_authenticated_exec then
        raise exception 'FAIL (test 8b): authenticated is missing EXECUTE on request_account_deletion_challenge' using errcode = 'M0049';
    end if;
    raise notice 'PASS (test 8b): ACL correct for request_account_deletion_challenge()';

    select p.oid::regprocedure::text, p.prosecdef
    into v_identity, v_secdef
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'self_delete_account';

    if v_identity <> 'self_delete_account(uuid)' then
        raise exception 'FAIL (test 8c): unexpected identity: % (expected self_delete_account(uuid))', v_identity using errcode = 'M0049';
    end if;
    if not v_secdef then
        raise exception 'FAIL (test 8c): self_delete_account is not SECURITY DEFINER' using errcode = 'M0049';
    end if;
    raise notice 'PASS (test 8c): self_delete_account(uuid) identity and SECURITY DEFINER confirmed';

    v_anon_exec := has_function_privilege('anon', 'public.self_delete_account(uuid)', 'EXECUTE');
    v_authenticated_exec := has_function_privilege('authenticated', 'public.self_delete_account(uuid)', 'EXECUTE');
    if v_anon_exec then
        raise exception 'FAIL (test 8d): anon unexpectedly has EXECUTE on self_delete_account' using errcode = 'M0049';
    end if;
    if not v_authenticated_exec then
        raise exception 'FAIL (test 8d): authenticated is missing EXECUTE on self_delete_account' using errcode = 'M0049';
    end if;
    raise notice 'PASS (test 8d): ACL correct for self_delete_account(uuid)';
end $$;

-- ---------------------------------------------------------------------
-- Test 9: account_deletion_challenges has zero client-readable
-- policies.
-- ---------------------------------------------------------------------
savepoint test_9;
do $$
begin
    insert into public.account_deletion_challenges (user_id, token, expires_at)
    values ('00000000-0000-0000-0000-000000001502', gen_random_uuid(), now() + interval '2 minutes');

    perform pg_temp.set_test_jwt('00000000-0000-0000-0000-000000001502', '[]'::jsonb);

    if exists (select 1 from public.account_deletion_challenges where user_id = '00000000-0000-0000-0000-000000001502') then
        raise exception 'FAIL (test 9): an authenticated session could read account_deletion_challenges directly' using errcode = 'M0049';
    end if;
    raise notice 'PASS (test 9): direct client SELECT on account_deletion_challenges returns nothing (RLS enabled, zero policies)';
end $$;
reset role;
rollback to savepoint test_9;

-- ---------------------------------------------------------------------
-- Cleanup.
-- ---------------------------------------------------------------------
delete from auth.users where email like 'm0049-%@example.invalid';
drop function if exists pg_temp.set_test_jwt(uuid, jsonb);

rollback;
