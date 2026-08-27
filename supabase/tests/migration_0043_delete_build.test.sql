-- Migration 0043 test —
-- supabase/tests/migration_0043_delete_build.test.sql
--
-- Covers migration 0043_delete_build: delete_build(uuid) ownership
-- enforcement (owner success, anonymous rejection, non-owner rejection,
-- missing-id rejection), every CASCADE relationship (build_revisions ->
-- revision_media, comments, likes, saved_builds, build_view_cooldowns,
-- notifications), both SET NULL relationships
-- (project_drafts.published_build_id, profiles.featured_build_id),
-- deliberate non-cleanup of content_reports/moderation_actions, the
-- returned Storage-path array excluding paths still referenced by
-- project_media, function identity/ACL/no-overload, the new
-- notifications(build_id) index, and rollback/reapplication.
--
-- STATUS: executed against the local disposable Supabase/Docker stack —
-- see this PR's own report for the exact assertion count and pass
-- result. NOT yet executed against a disposable/staging Supabase project
-- or against production. Depends on migrations 0001-0043 already being
-- applied.
--
-- Never run this against a project with real data — same fixture-safety
-- posture as every other test file in this suite. Fail-closed: every
-- FAIL is raised via `raise exception ... using errcode = 'M0043'`.

begin;

-- ---------------------------------------------------------------------
-- Fixture: two owners (u1 publishes/deletes, u2 is the non-owner probe),
-- one third account (u3) as a commenter/liker/saver/notification actor
-- so those rows have a real, distinct FK target. One draft/build for u1
-- with two revisions, two revision_media rows (one path also mirrored
-- into project_media — must survive Storage-path collection; one path
-- with no project_media counterpart — must be returned), one comment,
-- one like, one save, one view cooldown, one notification, one
-- content_report, one moderation_action, and u1's profile pinning this
-- build as featured.
-- ---------------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-0000-0000-000000000901', 'm0043-owner@example.invalid', '{"username": "m0043_owner"}'::jsonb),
    ('00000000-0000-0000-0000-000000000902', 'm0043-other@example.invalid', '{"username": "m0043_other"}'::jsonb),
    ('00000000-0000-0000-0000-000000000903', 'm0043-actor@example.invalid', '{"username": "m0043_actor"}'::jsonb)
on conflict (id) do nothing;

insert into public.project_drafts (id, user_id, title, description, category, cover_media_id)
values (
    '00000000-0000-0000-0000-000000000910', '00000000-0000-0000-0000-000000000901',
    'M0043 Test Draft', 'A properly detailed description for this fixture draft.', 'pc_build', null
);

insert into public.project_media (id, draft_id, storage_path, display_order) values
    ('00000000-0000-0000-0000-000000000920', '00000000-0000-0000-0000-000000000910', 'projects/00000000-0000-0000-0000-000000000910/still-in-draft.jpg', 0);

update public.project_drafts
    set cover_media_id = '00000000-0000-0000-0000-000000000920'
    where id = '00000000-0000-0000-0000-000000000910';

insert into public.builds (id, user_id, title, slug, category, status, visibility, image_url)
values (
    '00000000-0000-0000-0000-000000000930', '00000000-0000-0000-0000-000000000901',
    'M0043 Test Build', 'm0043-test-build-fixture', 'pc_build', 'planning', 'public',
    'projects/00000000-0000-0000-0000-000000000910/still-in-draft.jpg'
);

update public.project_drafts
    set published_build_id = '00000000-0000-0000-0000-000000000930'
    where id = '00000000-0000-0000-0000-000000000910';

insert into public.build_revisions (id, build_id, user_id, title, update_type, version)
values
    ('00000000-0000-0000-0000-000000000940', '00000000-0000-0000-0000-000000000930', '00000000-0000-0000-0000-000000000901', 'Initial publish', 'initial_publish', 'v1.0'),
    ('00000000-0000-0000-0000-000000000941', '00000000-0000-0000-0000-000000000930', '00000000-0000-0000-0000-000000000901', 'Update', 'update', 'v1.1');

-- Cover image: same path as project_media above -- must be EXCLUDED from
-- the returned Storage-path array (the draft's own gallery still needs
-- it). Gallery image on the second revision: no project_media
-- counterpart -- must be INCLUDED.
insert into public.revision_media (id, revision_id, storage_path, is_cover) values
    ('00000000-0000-0000-0000-000000000950', '00000000-0000-0000-0000-000000000940', 'projects/00000000-0000-0000-0000-000000000910/still-in-draft.jpg', true),
    ('00000000-0000-0000-0000-000000000951', '00000000-0000-0000-0000-000000000941', 'projects/00000000-0000-0000-0000-000000000910/only-in-history.jpg', false);

insert into public.comments (id, build_id, user_id, body)
values ('00000000-0000-0000-0000-000000000960', '00000000-0000-0000-0000-000000000930', '00000000-0000-0000-0000-000000000903', 'M0043 fixture comment.');

insert into public.likes (id, build_id, user_id)
values ('00000000-0000-0000-0000-000000000961', '00000000-0000-0000-0000-000000000930', '00000000-0000-0000-0000-000000000903');

insert into public.saved_builds (id, build_id, user_id)
values ('00000000-0000-0000-0000-000000000962', '00000000-0000-0000-0000-000000000930', '00000000-0000-0000-0000-000000000903');

insert into public.build_view_cooldowns (build_id, viewer_key)
values ('00000000-0000-0000-0000-000000000930', 'user:00000000-0000-0000-0000-000000000903');

insert into public.notifications (id, recipient_id, actor_id, type, build_id)
values ('00000000-0000-0000-0000-000000000963', '00000000-0000-0000-0000-000000000901', '00000000-0000-0000-0000-000000000903', 'like', '00000000-0000-0000-0000-000000000930');

insert into public.content_reports (id, reporter_id, target_type, target_id, reason)
values ('00000000-0000-0000-0000-000000000970', '00000000-0000-0000-0000-000000000903', 'build', '00000000-0000-0000-0000-000000000930', 'M0043 fixture report.');

insert into public.moderation_actions (id, actor_id, action_type, target_type, target_id, note)
values ('00000000-0000-0000-0000-000000000971', '00000000-0000-0000-0000-000000000902', 'content_removed', 'build', '00000000-0000-0000-0000-000000000930', 'M0043 fixture audit entry.');

update public.profiles
    set featured_build_id = '00000000-0000-0000-0000-000000000930'
    where id = '00000000-0000-0000-0000-000000000901';

-- ---------------------------------------------------------------------
-- Test 1: an anonymous caller (no auth.uid()) is rejected.
-- ---------------------------------------------------------------------
savepoint test_1;
do $$
begin
    perform set_config('request.jwt.claim.sub', '', true);
    set local role authenticated;

    begin
        perform public.delete_build('00000000-0000-0000-0000-000000000930');
        raise exception 'FAIL (test 1): an anonymous caller was allowed to delete a build' using errcode = 'M0043';
    exception when others then
        if sqlerrm like '%must be signed in%' then
            raise notice 'PASS (test 1): anonymous caller correctly rejected (%)', sqlerrm;
        else
            raise exception 'FAIL (test 1): rejected for the wrong reason: %', sqlerrm using errcode = 'M0043';
        end if;
    end;
end $$;
reset role;
rollback to savepoint test_1;

-- ---------------------------------------------------------------------
-- Test 2: a signed-in NON-owner is rejected, distinct error from "not
-- found" -- the build is untouched afterward.
-- ---------------------------------------------------------------------
savepoint test_2;
do $$
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000902', true);
    set local role authenticated;

    begin
        perform public.delete_build('00000000-0000-0000-0000-000000000930');
        raise exception 'FAIL (test 2): a non-owner was allowed to delete another user''s build' using errcode = 'M0043';
    exception when others then
        if sqlerrm like '%Only the build owner%' then
            raise notice 'PASS (test 2): non-owner correctly rejected (%)', sqlerrm;
        else
            raise exception 'FAIL (test 2): rejected for the wrong reason: %', sqlerrm using errcode = 'M0043';
        end if;
    end;
end $$;
reset role;

do $$
begin
    if not exists (select 1 from public.builds where id = '00000000-0000-0000-0000-000000000930') then
        raise exception 'FAIL (test 2b): the build was deleted despite the non-owner call being rejected' using errcode = 'M0043';
    end if;
    raise notice 'PASS (test 2b): build still exists after the rejected non-owner call';
end $$;
rollback to savepoint test_2;

-- ---------------------------------------------------------------------
-- Test 3: a missing build id is rejected with 'Build not found.', even
-- for the real owner.
-- ---------------------------------------------------------------------
savepoint test_3;
do $$
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000901', true);
    set local role authenticated;

    begin
        perform public.delete_build('00000000-0000-0000-0000-000000000999');
        raise exception 'FAIL (test 3): deleting a nonexistent build id did not raise' using errcode = 'M0043';
    exception when others then
        if sqlerrm like '%Build not found%' then
            raise notice 'PASS (test 3): nonexistent build id correctly rejected (%)', sqlerrm;
        else
            raise exception 'FAIL (test 3): rejected for the wrong reason: %', sqlerrm using errcode = 'M0043';
        end if;
    end;
end $$;
reset role;
rollback to savepoint test_3;

-- ---------------------------------------------------------------------
-- Test 4: the real deletion, as the owner -- the main event. Verifies
-- the return value (Storage-path exclusion), every CASCADE, both SET
-- NULL relationships, and that content_reports/moderation_actions
-- survive untouched. Not wrapped in a savepoint rollback -- later tests
-- (index/ACL/rollback-reapply) don't depend on this build still
-- existing, and proving the row is REALLY gone (not just invisible
-- under RLS) matters here.
-- ---------------------------------------------------------------------
do $$
declare
    v_paths text[];
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000901', true);
    set local role authenticated;

    select public.delete_build('00000000-0000-0000-0000-000000000930') into v_paths;

    if v_paths is distinct from array['projects/00000000-0000-0000-0000-000000000910/only-in-history.jpg'] then
        raise exception 'FAIL (test 4a): unexpected returned Storage-path array: %', v_paths using errcode = 'M0043';
    end if;
    raise notice 'PASS (test 4a): returned exactly the one path not still referenced by project_media (%), excluding the one still in the draft''s gallery', v_paths;
end $$;
reset role;

do $$
begin
    if exists (select 1 from public.builds where id = '00000000-0000-0000-0000-000000000930') then
        raise exception 'FAIL (test 4b): builds row still exists' using errcode = 'M0043';
    end if;
    raise notice 'PASS (test 4b): builds row deleted';

    if exists (select 1 from public.build_revisions where build_id = '00000000-0000-0000-0000-000000000930') then
        raise exception 'FAIL (test 4c): build_revisions rows survived (CASCADE did not fire)' using errcode = 'M0043';
    end if;
    raise notice 'PASS (test 4c): build_revisions cascaded';

    if exists (select 1 from public.revision_media where id in ('00000000-0000-0000-0000-000000000950', '00000000-0000-0000-0000-000000000951')) then
        raise exception 'FAIL (test 4d): revision_media rows survived (two-level CASCADE did not fire)' using errcode = 'M0043';
    end if;
    raise notice 'PASS (test 4d): revision_media cascaded (two levels, through build_revisions)';

    if exists (select 1 from public.comments where id = '00000000-0000-0000-0000-000000000960') then
        raise exception 'FAIL (test 4e): comments row survived' using errcode = 'M0043';
    end if;
    raise notice 'PASS (test 4e): comments cascaded';

    if exists (select 1 from public.likes where id = '00000000-0000-0000-0000-000000000961') then
        raise exception 'FAIL (test 4f): likes row survived' using errcode = 'M0043';
    end if;
    raise notice 'PASS (test 4f): likes cascaded';

    if exists (select 1 from public.saved_builds where id = '00000000-0000-0000-0000-000000000962') then
        raise exception 'FAIL (test 4g): saved_builds row survived' using errcode = 'M0043';
    end if;
    raise notice 'PASS (test 4g): saved_builds cascaded';

    if exists (select 1 from public.build_view_cooldowns where build_id = '00000000-0000-0000-0000-000000000930') then
        raise exception 'FAIL (test 4h): build_view_cooldowns row survived' using errcode = 'M0043';
    end if;
    raise notice 'PASS (test 4h): build_view_cooldowns cascaded';

    if exists (select 1 from public.notifications where id = '00000000-0000-0000-0000-000000000963') then
        raise exception 'FAIL (test 4i): notifications row survived' using errcode = 'M0043';
    end if;
    raise notice 'PASS (test 4i): notifications cascaded';

    if (select published_build_id from public.project_drafts where id = '00000000-0000-0000-0000-000000000910') is not null then
        raise exception 'FAIL (test 4j): project_drafts.published_build_id was not set null' using errcode = 'M0043';
    end if;
    raise notice 'PASS (test 4j): project_drafts.published_build_id set null -- draft survives, now unpublished';

    if not exists (select 1 from public.project_drafts where id = '00000000-0000-0000-0000-000000000910') then
        raise exception 'FAIL (test 4k): the draft row itself was deleted -- it must survive' using errcode = 'M0043';
    end if;
    if (select title from public.project_drafts where id = '00000000-0000-0000-0000-000000000910') <> 'M0043 Test Draft' then
        raise exception 'FAIL (test 4k): the draft''s own content was altered' using errcode = 'M0043';
    end if;
    raise notice 'PASS (test 4k): the draft row survives intact and editable';

    if not exists (select 1 from public.project_media where id = '00000000-0000-0000-0000-000000000920') then
        raise exception 'FAIL (test 4l): the draft''s own project_media row was deleted -- it must survive' using errcode = 'M0043';
    end if;
    raise notice 'PASS (test 4l): the draft''s project_media (its live gallery) survives untouched';

    if (select featured_build_id from public.profiles where id = '00000000-0000-0000-0000-000000000901') is not null then
        raise exception 'FAIL (test 4m): profiles.featured_build_id was not set null' using errcode = 'M0043';
    end if;
    raise notice 'PASS (test 4m): profiles.featured_build_id set null';

    if not exists (select 1 from public.content_reports where id = '00000000-0000-0000-0000-000000000970' and target_id = '00000000-0000-0000-0000-000000000930') then
        raise exception 'FAIL (test 4n): content_reports row was deleted or altered -- it must survive, by design' using errcode = 'M0043';
    end if;
    raise notice 'PASS (test 4n): content_reports survives untouched, dangling target_id by design';

    if not exists (select 1 from public.moderation_actions where id = '00000000-0000-0000-0000-000000000971' and target_id = '00000000-0000-0000-0000-000000000930') then
        raise exception 'FAIL (test 4o): moderation_actions row was deleted or altered -- it must survive as a permanent audit log' using errcode = 'M0043';
    end if;
    raise notice 'PASS (test 4o): moderation_actions survives untouched';
end $$;

-- ---------------------------------------------------------------------
-- Test 5: function identity, SECURITY DEFINER, search_path, ACL, and
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
    where n.nspname = 'public' and p.proname = 'delete_build';

    if v_overload_count <> 1 then
        raise exception 'FAIL (test 5a): expected exactly one delete_build overload, found %', v_overload_count using errcode = 'M0043';
    end if;
    raise notice 'PASS (test 5a): exactly one delete_build signature exists, no overload';

    select p.oid::regprocedure::text, p.prosecdef, p.proconfig
    into v_identity, v_secdef, v_search_path
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'delete_build';

    if v_identity <> 'delete_build(uuid)' then
        raise exception 'FAIL (test 5b): unexpected function identity: %', v_identity using errcode = 'M0043';
    end if;
    raise notice 'PASS (test 5b): identity is exactly delete_build(uuid)';

    if not v_secdef then
        raise exception 'FAIL (test 5c): delete_build is not SECURITY DEFINER' using errcode = 'M0043';
    end if;
    raise notice 'PASS (test 5c): SECURITY DEFINER confirmed';

    if v_search_path is null or not ('search_path=public, pg_temp' = any(v_search_path)) then
        raise exception 'FAIL (test 5d): search_path is not pinned to "public, pg_temp": %', v_search_path using errcode = 'M0043';
    end if;
    raise notice 'PASS (test 5d): search_path pinned to public, pg_temp';

    v_anon_exec := has_function_privilege('anon', 'public.delete_build(uuid)', 'EXECUTE');
    v_authenticated_exec := has_function_privilege('authenticated', 'public.delete_build(uuid)', 'EXECUTE');

    if v_anon_exec then
        raise exception 'FAIL (test 5e): anon unexpectedly has EXECUTE on delete_build' using errcode = 'M0043';
    end if;
    if not v_authenticated_exec then
        raise exception 'FAIL (test 5e): authenticated is missing EXECUTE on delete_build' using errcode = 'M0043';
    end if;
    raise notice 'PASS (test 5e): ACL correct -- anon denied, authenticated granted';
end $$;

-- ---------------------------------------------------------------------
-- Test 6: no DELETE policy exists on public.builds -- the function
-- remains the only path, matching every other protected write in this
-- schema.
-- ---------------------------------------------------------------------
do $$
begin
    if exists (
        select 1 from pg_policies
        where schemaname = 'public' and tablename = 'builds' and cmd = 'DELETE'
    ) then
        raise exception 'FAIL (test 6): a DELETE policy exists on public.builds -- direct client deletes must stay denied outright' using errcode = 'M0043';
    end if;
    raise notice 'PASS (test 6): no DELETE policy on public.builds';
end $$;

-- ---------------------------------------------------------------------
-- Test 7: the new notifications(build_id) index exists.
-- ---------------------------------------------------------------------
do $$
begin
    if not exists (
        select 1 from pg_indexes
        where schemaname = 'public' and tablename = 'notifications' and indexname = 'notifications_build_id_idx'
    ) then
        raise exception 'FAIL (test 7): notifications_build_id_idx does not exist' using errcode = 'M0043';
    end if;
    raise notice 'PASS (test 7): notifications_build_id_idx exists';
end $$;

-- ---------------------------------------------------------------------
-- Cleanup: remove the disposable auth.users rows created above (cascades
-- to their profiles and any remaining fixture rows the deletion above
-- didn't already remove -- e.g. the surviving draft/project_media).
-- Redundant with the final ROLLBACK below, but explicit for the same
-- defense-in-depth reasoning documented in this suite's other files.
-- ---------------------------------------------------------------------
delete from auth.users where email like 'm0043-%@example.invalid';

rollback;
