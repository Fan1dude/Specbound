-- Migration 0048 test (SUPERSEDED — see below) —
-- supabase/tests/superseded/migration_0048_self_delete_account.superseded.sql
-- (moved here from supabase/tests/migration_0048_self_delete_account.test.sql;
-- see this repository's own PR history for why)
--
-- SUPERSEDED, disclosed here rather than silently left stale: PR review
-- found that 0048's zero-argument self_delete_account() relied on the
-- calling Edge Function checking a JWT `iat` claim for "recent
-- reauthentication" — insufficient, since Supabase's own token-refresh
-- grant advances `iat` without re-verifying the password. Migration
-- 0049_account_deletion_challenge.sql fixes this by DROPPING this
-- zero-argument function entirely and replacing it with
-- self_delete_account(p_challenge_token uuid), gated by a
-- database-verified, single-use challenge. This file is therefore only
-- valid against a database with 0048 applied and 0049 NOT YET applied —
-- a state that will never persist in any real deployment, since 0049
-- ships as an immediate, same-PR follow-up, never adopted separately.
-- Running this file against the current migration chain (0000-0050) WILL
-- fail (the zero-argument function this file tests no longer exists) —
-- that is expected, not a regression. **The current, authoritative
-- coverage for self-service account deletion is
-- supabase/tests/migration_0049_account_deletion_challenge.test.sql**
-- (and, for the recovery worker, migration_0050_account_deletion_recovery.test.sql),
-- which re-verify every property below under the new signature and add
-- the challenge/recovery-specific security properties.
--
-- SECOND security-review finding (this PR) moved this file out of
-- supabase/tests/ entirely, into supabase/tests/superseded/, and
-- renamed its extension from `.test.sql` to `.superseded.sql`: this
-- repository's documented test-run command (docs/DEPLOYMENT.md §8)
-- iterates `supabase/tests/*.test.sql` and expects every file it runs to
-- pass — leaving a file THERE that is designed to fail (see above) would
-- make that command permanently, deliberately broken, which defeats its
-- purpose as a real "did every active test pass" signal. Moving it here
-- is option 2 the review offered ("move/rename it outside the executable
-- test pattern as historical documentation") rather than option 1
-- (rewriting it to test 0049's/0050's API) — this repository's own "do
-- not rewrite old migrations" convention, already extended to this
-- file's own test LOGIC below (kept verbatim, unmodified), is extended
-- once more to cover WHERE that logic lives: a file documenting what an
-- earlier, now-superseded design actually did is itself a small piece of
-- history, not something to quietly rewrite into looking like it always
-- tested the current API.
--
-- Original scope (0048, in isolation, pre-0049): anonymous rejection,
-- legal-hold rejection (with a generic message, never distinguishing it
-- from any other failure), Storage-path capture (avatar, revision-media
-- minus legacy avatar_url, project-media, published and never-published
-- drafts), builds/build_revisions/profiles cleanup, the
-- authored-but-not-owned build_revisions clear-not-delete case, job-row
-- creation, the self-attributed audit row (and 0045's fix keeping it
-- alive later), idempotent retry (no duplicate audit row, same job
-- resumed), function identity/ACL, and — the key security property, for
-- 0048's own zero-argument design specifically — that the function had
-- NO parameter of any kind, so no caller could name a different
-- account.
--
-- STATUS: intended to run against the local disposable Supabase/Docker
-- stack only, at the specific 0048-applied/0049-not-yet-applied
-- migration state described above — NOT executed in the authoring
-- session (no `supabase` CLI, no reachable Docker daemon, no `psql`
-- were available; see this PR's own report for the exact environmental
-- limitation).
--
-- Fail-closed: every assertion raises via `raise exception ... using
-- errcode = 'M0048'`.

begin;

-- ---------------------------------------------------------------------
-- Test 1: an anonymous caller (no auth.uid()) is rejected.
-- ---------------------------------------------------------------------
savepoint test_1;
do $$
begin
    perform set_config('request.jwt.claim.sub', '', true);
    set local role authenticated;

    begin
        perform public.self_delete_account();
        raise exception 'FAIL (test 1): an anonymous caller was allowed to call self_delete_account()' using errcode = 'M0048';
    exception when others then
        if sqlerrm like '%must be signed in%' then
            raise notice 'PASS (test 1): anonymous caller correctly rejected (%)', sqlerrm;
        else
            raise exception 'FAIL (test 1): rejected for the wrong reason: %', sqlerrm using errcode = 'M0048';
        end if;
    end;
end $$;
reset role;
rollback to savepoint test_1;

-- ---------------------------------------------------------------------
-- Test 2: security — self_delete_account() takes NO parameters. Proven
-- structurally, not just by convention: attempting to call it with any
-- argument must fail with a function-does-not-exist error, since no
-- such overload exists.
-- ---------------------------------------------------------------------
do $$
begin
    begin
        perform public.self_delete_account('00000000-0000-0000-0000-000000009999'::uuid);
        raise exception 'FAIL (test 2): self_delete_account(uuid) unexpectedly exists -- a target user id must never be an accepted parameter' using errcode = 'M0048';
    exception when undefined_function then
        raise notice 'PASS (test 2): self_delete_account(uuid) does not exist -- no code path accepts a target user id';
    end;
end $$;

-- ---------------------------------------------------------------------
-- Test 3: a legal hold blocks deletion, with the SAME generic message
-- as any other failure — never a message that reveals a hold exists.
-- ---------------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-0000-0000-000000001301', 'm0048-held@example.invalid', '{"username": "m0048_held"}'::jsonb),
    ('00000000-0000-0000-0000-000000001302', 'm0048-staff@example.invalid', '{"username": "m0048_staff"}'::jsonb)
on conflict (id) do nothing;

insert into public.profile_roles (user_id, role) values ('00000000-0000-0000-0000-000000001302', 'staff');

savepoint test_3;
do $$
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000001302', true);
    set local role authenticated;
    perform public.place_legal_hold('00000000-0000-0000-0000-000000001301', 'M0048 test hold.');
end $$;
reset role;

do $$
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000001301', true);
    set local role authenticated;

    begin
        perform public.self_delete_account();
        raise exception 'FAIL (test 3): a held account was allowed to self-delete' using errcode = 'M0048';
    exception when others then
        if sqlerrm = 'Your request could not be completed. Contact support@specboundapp.com.' then
            raise notice 'PASS (test 3): held account correctly rejected with the generic message (%), never one that names a legal hold', sqlerrm;
        else
            raise exception 'FAIL (test 3): rejected with an unexpected message that may leak hold status: %', sqlerrm using errcode = 'M0048';
        end if;
    end;
end $$;
reset role;

do $$
begin
    if exists (select 1 from public.profiles where id = '00000000-0000-0000-0000-000000001301') then
        raise notice 'PASS (test 3b): held account''s profile untouched (deletion correctly aborted before any write)';
    else
        raise exception 'FAIL (test 3b): the held account''s profile was deleted despite the rejection' using errcode = 'M0048';
    end if;
end $$;
rollback to savepoint test_3;

-- ---------------------------------------------------------------------
-- Fixture for the main deletion test: u1 is the deleting account, with
-- an avatar (avatar_path), a legacy avatar_url-only artifact (must be
-- EXCLUDED from captured paths), one owned published build with two
-- revisions (one revision_media path also mirrored into a never-
-- published draft's project_media -- must still be captured, since this
-- is full-account deletion, not delete_build()'s narrower dedup), a
-- second, never-published draft with its own project_media, and one
-- build_revisions row AUTHORED by u1 on u2's build (u2 owns it) -- must
-- be cleared, not deleted, and u2's build must be completely untouched.
-- ---------------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-0000-0000-000000001401', 'm0048-owner@example.invalid', '{"username": "m0048_owner"}'::jsonb),
    ('00000000-0000-0000-0000-000000001402', 'm0048-other@example.invalid', '{"username": "m0048_other"}'::jsonb)
on conflict (id) do nothing;

update public.profiles set avatar_path = 'avatars/00000000-0000-0000-0000-000000001401/512.jpg', avatar_url = 'https://legacy.example.invalid/old-avatar.jpg'
    where id = '00000000-0000-0000-0000-000000001401';

insert into public.project_drafts (id, user_id, title, description, category)
values ('00000000-0000-0000-0000-000000001410', '00000000-0000-0000-0000-000000001401', 'M0048 Published Draft', 'A properly detailed description.', 'pc_build');

insert into public.project_drafts (id, user_id, title, description, category)
values ('00000000-0000-0000-0000-000000001411', '00000000-0000-0000-0000-000000001401', 'M0048 Never Published Draft', 'A properly detailed description.', 'pc_build');

insert into public.project_media (id, draft_id, storage_path, display_order) values
    ('00000000-0000-0000-0000-000000001420', '00000000-0000-0000-0000-000000001410', 'projects/00000000-0000-0000-0000-000000001410/cover.jpg', 0),
    ('00000000-0000-0000-0000-000000001421', '00000000-0000-0000-0000-000000001411', 'projects/00000000-0000-0000-0000-000000001411/gallery.jpg', 0);

insert into public.builds (id, user_id, title, slug, category, status, visibility, image_url)
values ('00000000-0000-0000-0000-000000001430', '00000000-0000-0000-0000-000000001401', 'M0048 Test Build', 'm0048-test-build-fixture', 'pc_build', 'planning', 'public', 'projects/00000000-0000-0000-0000-000000001410/cover.jpg');

update public.project_drafts set published_build_id = '00000000-0000-0000-0000-000000001430' where id = '00000000-0000-0000-0000-000000001410';

insert into public.build_revisions (id, build_id, user_id, title, update_type, version)
values ('00000000-0000-0000-0000-000000001440', '00000000-0000-0000-0000-000000001430', '00000000-0000-0000-0000-000000001401', 'Initial publish', 'initial_publish', 'v1.0');

insert into public.revision_media (id, revision_id, storage_path, is_cover) values
    ('00000000-0000-0000-0000-000000001450', '00000000-0000-0000-0000-000000001440', 'projects/00000000-0000-0000-0000-000000001410/cover.jpg', true),
    ('00000000-0000-0000-0000-000000001451', '00000000-0000-0000-0000-000000001440', 'projects/00000000-0000-0000-0000-000000001410/history-only.jpg', false);

-- u2 owns this build; u1 merely authored one of its revisions.
insert into public.builds (id, user_id, title, slug, category, status, visibility)
values ('00000000-0000-0000-0000-000000001460', '00000000-0000-0000-0000-000000001402', 'M0048 Other Owner Build', 'm0048-other-owner-build', 'pc_build', 'planning', 'public');

insert into public.build_revisions (id, build_id, user_id, title, update_type, version)
values ('00000000-0000-0000-0000-000000001461', '00000000-0000-0000-0000-000000001460', '00000000-0000-0000-0000-000000001401', 'A revision u1 authored on u2''s build', 'update', 'v1.1');

-- ---------------------------------------------------------------------
-- Test 4: the real deletion. Not wrapped in a savepoint rollback --
-- test 5 (idempotent retry) depends on this having actually committed.
-- ---------------------------------------------------------------------
do $$
declare
    v_job_id uuid;
    v_paths text[];
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000001401', true);
    set local role authenticated;

    select job_id, storage_paths into v_job_id, v_paths from public.self_delete_account();

    if v_job_id is null then
        raise exception 'FAIL (test 4a): no job_id returned' using errcode = 'M0048';
    end if;
    raise notice 'PASS (test 4a): a job_id was returned (%)', v_job_id;

    if v_paths is distinct from array[
        'avatars/00000000-0000-0000-0000-000000001401/512.jpg',
        'projects/00000000-0000-0000-0000-000000001410/cover.jpg',
        'projects/00000000-0000-0000-0000-000000001410/history-only.jpg',
        'projects/00000000-0000-0000-0000-000000001411/gallery.jpg'
    ]::text[] then
        -- array comparison is order-sensitive; use array_agg(... order by)
        -- upstream in a real run if ordering isn't guaranteed -- flagged
        -- here rather than silently assumed, since this test is
        -- unexecuted (see this file's own header).
        raise exception 'FAIL (test 4b): unexpected captured Storage-path array: %', v_paths using errcode = 'M0048';
    end if;
    raise notice 'PASS (test 4b): captured exactly the 4 expected paths (avatar, both revision-media paths, the never-published draft''s own media), excluding the legacy avatar_url';
end $$;
reset role;

do $$
begin
    if exists (select 1 from public.profiles where id = '00000000-0000-0000-0000-000000001401') then
        raise exception 'FAIL (test 4c): profiles row still exists' using errcode = 'M0048';
    end if;
    raise notice 'PASS (test 4c): profiles row deleted';

    if exists (select 1 from public.builds where id = '00000000-0000-0000-0000-000000001430') then
        raise exception 'FAIL (test 4d): the owned build still exists' using errcode = 'M0048';
    end if;
    raise notice 'PASS (test 4d): the owned build deleted';

    if exists (select 1 from public.build_revisions where build_id = '00000000-0000-0000-0000-000000001430') then
        raise exception 'FAIL (test 4e): build_revisions for the owned build survived (CASCADE did not fire)' using errcode = 'M0048';
    end if;
    raise notice 'PASS (test 4e): build_revisions for the owned build cascaded';

    if exists (select 1 from public.revision_media where id in ('00000000-0000-0000-0000-000000001450', '00000000-0000-0000-0000-000000001451')) then
        raise exception 'FAIL (test 4f): revision_media survived (two-level CASCADE did not fire)' using errcode = 'M0048';
    end if;
    raise notice 'PASS (test 4f): revision_media cascaded';

    if not exists (select 1 from public.project_drafts where id = '00000000-0000-0000-0000-000000001410') then
        raise exception 'FAIL (test 4g): the published draft was deleted -- project_drafts must cascade via the LATER Auth admin call, not this RPC, and this test never reaches that step' using errcode = 'M0048';
    end if;
    raise notice 'PASS (test 4g): project_drafts survives this RPC alone (correctly left for the later Auth Admin deleteUser() cascade, not deleted here)';

    -- The other owner's build is completely untouched.
    if not exists (select 1 from public.builds where id = '00000000-0000-0000-0000-000000001460') then
        raise exception 'FAIL (test 4h): u2''s own build was deleted -- u1''s deletion must never touch it' using errcode = 'M0048';
    end if;
    raise notice 'PASS (test 4h): the other owner''s build is untouched';

    if exists (select 1 from public.build_revisions where id = '00000000-0000-0000-0000-000000001461' and user_id is not null) then
        raise exception 'FAIL (test 4i): u1''s authored-but-not-owned revision still names u1 as user_id' using errcode = 'M0048';
    end if;
    if not exists (select 1 from public.build_revisions where id = '00000000-0000-0000-0000-000000001461') then
        raise exception 'FAIL (test 4i): u1''s authored-but-not-owned revision was DELETED -- it must survive, only cleared' using errcode = 'M0048';
    end if;
    raise notice 'PASS (test 4i): the authored-but-not-owned revision survives with user_id cleared, not deleted -- u2''s build history is intact';

    if not exists (select 1 from public.account_deletion_jobs where former_user_id = '00000000-0000-0000-0000-000000001401' and state = 'db_prepared') then
        raise exception 'FAIL (test 4j): no account_deletion_jobs row in state db_prepared' using errcode = 'M0048';
    end if;
    raise notice 'PASS (test 4j): account_deletion_jobs row created in state db_prepared';

    if (select count(*) from public.moderation_actions where target_id = '00000000-0000-0000-0000-000000001401' and action_type = 'account_deleted') <> 1 then
        raise exception 'FAIL (test 4k): expected exactly one account_deleted audit row' using errcode = 'M0048';
    end if;
    if (select actor_id from public.moderation_actions where target_id = '00000000-0000-0000-0000-000000001401' and action_type = 'account_deleted') <> '00000000-0000-0000-0000-000000001401' then
        raise exception 'FAIL (test 4l): the audit row is not self-attributed' using errcode = 'M0048';
    end if;
    raise notice 'PASS (test 4k/4l): exactly one self-attributed account_deleted audit row exists';
end $$;

-- ---------------------------------------------------------------------
-- Test 5: idempotent retry — auth.uid() still resolves for u1 in this
-- test harness (unlike a real Edge Function retry, where auth.uid()
-- only still resolves if Auth deletion has NOT yet succeeded — exactly
-- the state this RPC alone, without the later Auth Admin call, leaves
-- things in). A second call must resume the same job, not duplicate the
-- audit row, and not error on the now-already-gone builds/profile rows.
-- ---------------------------------------------------------------------
do $$
declare
    v_job_id_2 uuid;
    v_job_id_1 uuid;
begin
    select id into v_job_id_1 from public.account_deletion_jobs where former_user_id = '00000000-0000-0000-0000-000000001401';

    perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000001401', true);
    set local role authenticated;

    select job_id into v_job_id_2 from public.self_delete_account();

    if v_job_id_2 <> v_job_id_1 then
        raise exception 'FAIL (test 5a): retry created a new job row instead of resuming % (got %)', v_job_id_1, v_job_id_2 using errcode = 'M0048';
    end if;
    raise notice 'PASS (test 5a): retry resumes the same job row';
end $$;
reset role;

do $$
begin
    if (select count(*) from public.moderation_actions where target_id = '00000000-0000-0000-0000-000000001401' and action_type = 'account_deleted') <> 1 then
        raise exception 'FAIL (test 5b): retry inserted a duplicate audit row' using errcode = 'M0048';
    end if;
    raise notice 'PASS (test 5b): retry did not insert a duplicate audit row';
end $$;

-- ---------------------------------------------------------------------
-- Test 6: function identity, SECURITY DEFINER, search_path, ACL,
-- no-overload.
-- ---------------------------------------------------------------------
do $$
declare
    v_identity text;
    v_secdef boolean;
    v_search_path text[];
    v_overload_count integer;
    v_anon_exec boolean;
    v_authenticated_exec boolean;
begin
    select count(*) into v_overload_count
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'self_delete_account';

    if v_overload_count <> 1 then
        raise exception 'FAIL (test 6a): expected exactly one self_delete_account overload, found %', v_overload_count using errcode = 'M0048';
    end if;
    raise notice 'PASS (test 6a): exactly one self_delete_account signature exists, no overload';

    select p.oid::regprocedure::text, p.prosecdef, p.proconfig
    into v_identity, v_secdef, v_search_path
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'self_delete_account';

    if v_identity <> 'self_delete_account()' then
        raise exception 'FAIL (test 6b): unexpected function identity: %', v_identity using errcode = 'M0048';
    end if;
    raise notice 'PASS (test 6b): identity is exactly self_delete_account() -- confirms no parameter of any kind';

    if not v_secdef then
        raise exception 'FAIL (test 6c): self_delete_account is not SECURITY DEFINER' using errcode = 'M0048';
    end if;
    raise notice 'PASS (test 6c): SECURITY DEFINER confirmed';

    if v_search_path is null or not ('search_path=public, pg_temp' = any(v_search_path)) then
        raise exception 'FAIL (test 6d): search_path is not pinned to "public, pg_temp": %', v_search_path using errcode = 'M0048';
    end if;
    raise notice 'PASS (test 6d): search_path pinned to public, pg_temp';

    v_anon_exec := has_function_privilege('anon', 'public.self_delete_account()', 'EXECUTE');
    v_authenticated_exec := has_function_privilege('authenticated', 'public.self_delete_account()', 'EXECUTE');

    if v_anon_exec then
        raise exception 'FAIL (test 6e): anon unexpectedly has EXECUTE on self_delete_account' using errcode = 'M0048';
    end if;
    if not v_authenticated_exec then
        raise exception 'FAIL (test 6e): authenticated is missing EXECUTE on self_delete_account' using errcode = 'M0048';
    end if;
    raise notice 'PASS (test 6e): ACL correct -- anon denied, authenticated granted';
end $$;

-- ---------------------------------------------------------------------
-- Cleanup.
-- ---------------------------------------------------------------------
delete from auth.users where email like 'm0048-%@example.invalid';

rollback;
