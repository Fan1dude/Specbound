-- Migration 0052 test —
-- supabase/tests/migration_0052_self_delete_account_column_ambiguity_fix.test.sql
--
-- Dedicated regression coverage for the exact runtime bug real local
-- execution found and 0052 fixes: self_delete_account(uuid)'s retry
-- branch raised "column reference storage_paths is ambiguous" on every
-- second call for the same account, because that bare column reference
-- collided with the function's own storage_paths OUT parameter (see
-- 0052's own header for the full root cause).
--
-- This file is self-contained (seeds its own fixture, does not depend
-- on any other test file's data or ordering) so it belongs in the main
-- `supabase/tests/*.test.sql` loop like every other non-legacy-upgrade
-- test — see docs/DEPLOYMENT.md Section 8.1's own corrected procedure.
--
-- Overlaps deliberately with migration_0049_account_deletion_challenge.test.sql's
-- own tests 7e/7f (which exercise the same retry-preserves-paths
-- property as part of that file's broader coverage, written before this
-- bug was known to be a real runtime failure, not just reviewed code) —
-- kept here as its OWN dedicated, minimal, single-purpose regression
-- test specifically for this fix, matching this PR's own established
-- pattern of giving each individually-reviewed bug fix its own focused
-- test file (0050, 0051) rather than relying solely on broader
-- pre-existing coverage to prove a specific, previously-broken case now
-- works.
--
-- STATUS: intended to run against the local disposable Supabase/Docker
-- stack only — NOT executed in the authoring session (no `supabase`
-- CLI, no reachable Docker daemon, no `psql` were available; see this
-- PR's own report for the exact environmental limitation). Depends on
-- migrations 0000-0052 already being applied. Real local testing of
-- 0049 is what found the bug this file regression-tests; this specific
-- file, testing the FIX, has itself not yet been executed for real —
-- disclosed honestly, not claimed otherwise.
--
-- Fail-closed: every assertion raises via `raise exception ... using
-- errcode = 'M0052'`.

begin;

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
    ('00000000-0000-0000-0000-000000001801', 'm0052-user@example.invalid', '{"username": "m0052_user"}'::jsonb)
on conflict (id) do nothing;

-- A real, non-empty Storage path -- needed so this test can prove a
-- real path survives the retry call, not just an already-empty one
-- (which would trivially "pass" even with the original bug present,
-- since the exception only fires when the SELECT actually runs against
-- a real row -- it does regardless of whether storage_paths is empty,
-- so this isn't strictly required to trigger the bug, but it IS
-- required to prove requirement 5's own "confirms the exact captured
-- paths are returned unchanged," not merely "the call didn't crash").
update public.profiles
    set avatar_path = 'avatars/00000000-0000-0000-0000-000000001801/512.jpg'
    where id = '00000000-0000-0000-0000-000000001801';

-- ---------------------------------------------------------------------
-- Test 1: first call captures the real path and creates the job.
-- ---------------------------------------------------------------------
do $$
declare
    v_token uuid;
    v_job_id uuid;
    v_paths text[];
begin
    perform pg_temp.set_test_jwt(
        '00000000-0000-0000-0000-000000001801',
        jsonb_build_array(jsonb_build_object('method', 'password', 'timestamp', extract(epoch from now())::bigint))
    );
    select public.request_account_deletion_challenge() into v_token;

    select job_id, storage_paths into v_job_id, v_paths from public.self_delete_account(v_token);

    if v_job_id is null then
        raise exception 'FAIL (test 1a): no job_id returned from the first call' using errcode = 'M0052';
    end if;
    if v_paths is distinct from array['avatars/00000000-0000-0000-0000-000000001801/512.jpg']::text[] then
        raise exception 'FAIL (test 1b): unexpected captured path on the first call: %', v_paths using errcode = 'M0052';
    end if;
    raise notice 'PASS (test 1): the first call succeeds and captures the real avatar path';
end $$;
reset role;

-- ---------------------------------------------------------------------
-- Test 2: THE REGRESSION -- the retry call (existing-job branch) must
-- not raise "column reference storage_paths is ambiguous", and must
-- return the exact same, previously-captured path, unchanged. This is
-- the exact call that failed in real local execution before 0052.
-- ---------------------------------------------------------------------
do $$
declare
    v_token uuid;
    v_job_id uuid;
    v_job_id_first uuid;
    v_paths text[];
begin
    select id into v_job_id_first from public.account_deletion_jobs where former_user_id = '00000000-0000-0000-0000-000000001801';

    perform pg_temp.set_test_jwt(
        '00000000-0000-0000-0000-000000001801',
        jsonb_build_array(jsonb_build_object('method', 'password', 'timestamp', extract(epoch from now())::bigint))
    );
    select public.request_account_deletion_challenge() into v_token;

    -- Before 0052, this line raised:
    --   ERROR: column reference "storage_paths" is ambiguous
    -- If it does again, this whole DO block aborts here with that same
    -- error (not a graceful FAIL notice) -- which itself is the
    -- clearest possible signal the regression has returned.
    select job_id, storage_paths into v_job_id, v_paths from public.self_delete_account(v_token);

    if v_job_id <> v_job_id_first then
        raise exception 'FAIL (test 2a): retry created a new job (%) instead of resuming % ', v_job_id, v_job_id_first using errcode = 'M0052';
    end if;
    raise notice 'PASS (test 2a): the retry call succeeds with no ambiguous-column error, resumes the same job';

    if v_paths is distinct from array['avatars/00000000-0000-0000-0000-000000001801/512.jpg']::text[] then
        raise exception 'FAIL (test 2b): retry returned % instead of the exact, unchanged, originally-captured path' , v_paths using errcode = 'M0052';
    end if;
    raise notice 'PASS (test 2b): the retry call returns the exact captured path, unchanged -- requirement 5 satisfied';
end $$;
reset role;

-- ---------------------------------------------------------------------
-- Cleanup.
-- ---------------------------------------------------------------------
delete from auth.users where email = 'm0052-user@example.invalid';
drop function if exists pg_temp.set_test_jwt(uuid, jsonb);

rollback;
