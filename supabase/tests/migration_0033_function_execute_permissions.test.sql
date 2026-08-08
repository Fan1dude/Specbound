-- Migration 0033 function-permission test —
-- supabase/tests/migration_0033_function_execute_permissions.test.sql
--
-- Covers the EXECUTE-permission hardening in migration 0033
-- (restrict_function_execute_permissions): proves, at the database
-- level, that the 17 functions 0033 touches now reject the client
-- roles they were never meant to allow, that the 12 genuine signed-in
-- RPCs still work for `authenticated`, that get_public_profile_roles()
-- (0032, unaffected by 0033) still works for both `anon` and
-- `authenticated`, that `service_role` and the function owner keep
-- whatever access they already had, and that a brand-new
-- `postgres`-owned function created AFTER 0033 does NOT automatically
-- receive `public`/`anon`/`authenticated` EXECUTE the way it would have
-- before 0033's `alter default privileges` statement.
--
-- STATUS: executed against the local disposable Supabase/Docker stack
-- (`supabase db reset --local`, Postgres 17.6, Supabase CLI 2.112.0) —
-- 43/43 assertions passed. NOT yet executed against a disposable/staging
-- Supabase project or against production; run it there too before
-- trusting the result in an environment closer to production. Depends
-- on migrations 0001-0033 already being applied.
--
-- Never run this against a project with real data — same fixture-safety
-- posture as milestone_22_profile_roles_visibility.test.sql (fake
-- auth.users rows, namespaced usernames, single outer transaction ending
-- in ROLLBACK, each test in its own SAVEPOINT).
--
-- Permission testing convention used throughout: a nested
-- `begin ... exception when insufficient_privilege then ... end` block
-- inside each `do $$ ... $$` catches Postgres's own ACL rejection
-- (SQLSTATE 42501) without aborting the outer transaction — this is
-- what actually distinguishes "the database refused to run this at
-- all" (the thing 0033 controls) from "the function ran and its own
-- business logic raised an error" (e.g. "Submission not found",
-- "Invalid invite code" — a completely different SQLSTATE, normally
-- P0001 for a plain `raise exception`). For the 12 authenticated-only
-- RPCs, an ordinary signed-in test user who isn't a moderator and
-- doesn't own whatever record they're passing IS expected to hit that
-- second kind of error — that's success for THIS test, which only ever
-- asks "did the database let the call through," never "did the business
-- logic accept it" (the other test files already cover that).
--
-- Role-switch statements are top-level only, never inside a `do $$`
-- block, matching every other SQL test file in this repo.

begin;

insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-0000-0000-000000000401', 'm0033-user@example.invalid', '{"username": "m0033_user_test"}'::jsonb),
    ('00000000-0000-0000-0000-000000000402', 'm0033-recipient@example.invalid', '{"username": "m0033_recipient_test"}'::jsonb)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- Test 1: the 4 trigger-only functions reject anon AND authenticated —
-- neither role has any legitimate reason to call these directly, and
-- 0033 revoked both.
-- ---------------------------------------------------------------------
savepoint test_1;
set local role anon;
do $$
begin
    begin
        perform public.sync_component_legacy_fields();
        raise warning 'FAIL (test 1a): sync_component_legacy_fields() was callable by anon';
    exception
        when insufficient_privilege then
            raise notice 'PASS (test 1a): sync_component_legacy_fields() correctly denied to anon';
    end;

    begin
        perform public.set_component_alias_technology_and_field();
        raise warning 'FAIL (test 1b): set_component_alias_technology_and_field() was callable by anon';
    exception
        when insufficient_privilege then
            raise notice 'PASS (test 1b): set_component_alias_technology_and_field() correctly denied to anon';
    end;

    begin
        perform public.enforce_component_submission_pending_cap();
        raise warning 'FAIL (test 1c): enforce_component_submission_pending_cap() was callable by anon';
    exception
        when insufficient_privilege then
            raise notice 'PASS (test 1c): enforce_component_submission_pending_cap() correctly denied to anon';
    end;

    begin
        perform public.validate_featured_build();
        raise warning 'FAIL (test 1d): validate_featured_build() was callable by anon';
    exception
        when insufficient_privilege then
            raise notice 'PASS (test 1d): validate_featured_build() correctly denied to anon';
    end;
end $$;
reset role;
rollback to savepoint test_1;

savepoint test_1_auth;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000401', true);
set local role authenticated;
do $$
begin
    begin
        perform public.sync_component_legacy_fields();
        raise warning 'FAIL (test 1e): sync_component_legacy_fields() was callable by authenticated';
    exception
        when insufficient_privilege then
            raise notice 'PASS (test 1e): sync_component_legacy_fields() correctly denied to authenticated';
    end;

    begin
        perform public.set_component_alias_technology_and_field();
        raise warning 'FAIL (test 1f): set_component_alias_technology_and_field() was callable by authenticated';
    exception
        when insufficient_privilege then
            raise notice 'PASS (test 1f): set_component_alias_technology_and_field() correctly denied to authenticated';
    end;

    begin
        perform public.enforce_component_submission_pending_cap();
        raise warning 'FAIL (test 1g): enforce_component_submission_pending_cap() was callable by authenticated';
    exception
        when insufficient_privilege then
            raise notice 'PASS (test 1g): enforce_component_submission_pending_cap() correctly denied to authenticated';
    end;

    begin
        perform public.validate_featured_build();
        raise warning 'FAIL (test 1h): validate_featured_build() was callable by authenticated';
    exception
        when insufficient_privilege then
            raise notice 'PASS (test 1h): validate_featured_build() correctly denied to authenticated';
    end;
end $$;
reset role;
rollback to savepoint test_1_auth;

-- ---------------------------------------------------------------------
-- Test 2: create_notification() rejects anon AND authenticated — the
-- highest-severity finding this migration closes. It has no internal
-- auth.uid() check of its own, so before 0033 either role could insert
-- an arbitrary notification; after 0033 the call should never even
-- reach the function body.
-- ---------------------------------------------------------------------
savepoint test_2;
set local role anon;
do $$
begin
    begin
        perform public.create_notification(
            '00000000-0000-0000-0000-000000000402'::uuid,
            '00000000-0000-0000-0000-000000000401'::uuid,
            'comment'
        );
        raise warning 'FAIL (test 2a): create_notification() was callable by anon';
    exception
        when insufficient_privilege then
            raise notice 'PASS (test 2a): create_notification() correctly denied to anon';
    end;
end $$;
reset role;
rollback to savepoint test_2;

savepoint test_2_auth;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000401', true);
set local role authenticated;
do $$
begin
    begin
        perform public.create_notification(
            '00000000-0000-0000-0000-000000000402'::uuid,
            '00000000-0000-0000-0000-000000000401'::uuid,
            'comment'
        );
        raise warning 'FAIL (test 2b): create_notification() was callable by authenticated';
    exception
        when insufficient_privilege then
            raise notice 'PASS (test 2b): create_notification() correctly denied to authenticated';
    end;
end $$;
reset role;
rollback to savepoint test_2_auth;

-- ---------------------------------------------------------------------
-- Test 3: the 12 signed-in RPCs/RLS helpers are executable by
-- authenticated (no insufficient_privilege — a business-logic
-- rejection, e.g. "not a moderator" / "not found", is a PASS here; only
-- a permission error is a FAIL) but rejected outright for anon.
-- ---------------------------------------------------------------------
savepoint test_3_auth;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000401', true);
set local role authenticated;
do $$
begin
    begin perform public.is_catalog_moderator('00000000-0000-0000-0000-000000000401'::uuid);
        raise notice 'PASS (test 3a): is_catalog_moderator(uuid) executable by authenticated';
    exception when insufficient_privilege then
        raise warning 'FAIL (test 3a): is_catalog_moderator(uuid) denied to authenticated';
    end;

    begin perform public.approve_component_submission('00000000-0000-0000-0000-000000000401'::uuid);
        raise notice 'PASS (test 3b): approve_component_submission(uuid,uuid) executable by authenticated (business-logic rejection expected/OK)';
    exception
        when insufficient_privilege then raise warning 'FAIL (test 3b): approve_component_submission(uuid,uuid) denied to authenticated';
        when others then raise notice 'PASS (test 3b): approve_component_submission(uuid,uuid) reached its own logic (%), not a permission error', sqlerrm;
    end;

    begin perform public.reject_component_submission('00000000-0000-0000-0000-000000000401'::uuid, 'permission test');
        raise notice 'PASS (test 3c): reject_component_submission(uuid,text) executable by authenticated';
    exception
        when insufficient_privilege then raise warning 'FAIL (test 3c): reject_component_submission(uuid,text) denied to authenticated';
        when others then raise notice 'PASS (test 3c): reject_component_submission(uuid,text) reached its own logic (%), not a permission error', sqlerrm;
    end;

    begin perform public.is_platform_moderator('00000000-0000-0000-0000-000000000401'::uuid);
        raise notice 'PASS (test 3d): is_platform_moderator(uuid) executable by authenticated';
    exception when insufficient_privilege then
        raise warning 'FAIL (test 3d): is_platform_moderator(uuid) denied to authenticated';
    end;

    begin perform public.is_platform_staff('00000000-0000-0000-0000-000000000401'::uuid);
        raise notice 'PASS (test 3e): is_platform_staff(uuid) executable by authenticated';
    exception when insufficient_privilege then
        raise warning 'FAIL (test 3e): is_platform_staff(uuid) denied to authenticated';
    end;

    begin perform public.report_content('build', '00000000-0000-0000-0000-000000000401'::uuid, 'permission test');
        raise notice 'PASS (test 3f): report_content(text,uuid,text) executable by authenticated';
    exception
        when insufficient_privilege then raise warning 'FAIL (test 3f): report_content(text,uuid,text) denied to authenticated';
        when others then raise notice 'PASS (test 3f): report_content(text,uuid,text) reached its own logic (%), not a permission error', sqlerrm;
    end;

    begin perform public.resolve_report('00000000-0000-0000-0000-000000000401'::uuid, 'dismissed');
        raise notice 'PASS (test 3g): resolve_report(uuid,text,text) executable by authenticated';
    exception
        when insufficient_privilege then raise warning 'FAIL (test 3g): resolve_report(uuid,text,text) denied to authenticated';
        when others then raise notice 'PASS (test 3g): resolve_report(uuid,text,text) reached its own logic (%), not a permission error', sqlerrm;
    end;

    begin perform public.grant_profile_role('00000000-0000-0000-0000-000000000402'::uuid, 'community_builder', 'permission test');
        raise notice 'PASS (test 3h): grant_profile_role(uuid,text,text) executable by authenticated';
    exception
        when insufficient_privilege then raise warning 'FAIL (test 3h): grant_profile_role(uuid,text,text) denied to authenticated';
        when others then raise notice 'PASS (test 3h): grant_profile_role(uuid,text,text) reached its own logic (%), not a permission error', sqlerrm;
    end;

    begin perform public.revoke_profile_role('00000000-0000-0000-0000-000000000402'::uuid, 'community_builder', 'permission test');
        raise notice 'PASS (test 3i): revoke_profile_role(uuid,text,text) executable by authenticated';
    exception
        when insufficient_privilege then raise warning 'FAIL (test 3i): revoke_profile_role(uuid,text,text) denied to authenticated';
        when others then raise notice 'PASS (test 3i): revoke_profile_role(uuid,text,text) reached its own logic (%), not a permission error', sqlerrm;
    end;

    begin perform public.submit_feedback('bug', 'permission test message');
        raise notice 'PASS (test 3j): submit_feedback(text,text,text) executable by authenticated';
    exception
        when insufficient_privilege then raise warning 'FAIL (test 3j): submit_feedback(text,text,text) denied to authenticated';
        when others then raise notice 'PASS (test 3j): submit_feedback(text,text,text) reached its own logic (%), not a permission error', sqlerrm;
    end;

    begin perform public.redeem_beta_invite('this-code-does-not-exist');
        raise notice 'PASS (test 3k): redeem_beta_invite(text) executable by authenticated';
    exception
        when insufficient_privilege then raise warning 'FAIL (test 3k): redeem_beta_invite(text) denied to authenticated';
        when others then raise notice 'PASS (test 3k): redeem_beta_invite(text) reached its own logic (%), not a permission error', sqlerrm;
    end;

    begin perform public.sync_discord_identity();
        raise notice 'PASS (test 3l): sync_discord_identity() executable by authenticated';
    exception
        when insufficient_privilege then raise warning 'FAIL (test 3l): sync_discord_identity() denied to authenticated';
        when others then raise notice 'PASS (test 3l): sync_discord_identity() reached its own logic (%), not a permission error', sqlerrm;
    end;
end $$;
reset role;
rollback to savepoint test_3_auth;

savepoint test_3_anon;
set local role anon;
do $$
begin
    begin perform public.is_catalog_moderator('00000000-0000-0000-0000-000000000401'::uuid);
        raise warning 'FAIL (test 3m): is_catalog_moderator(uuid) was callable by anon';
    exception when insufficient_privilege then
        raise notice 'PASS (test 3m): is_catalog_moderator(uuid) correctly denied to anon';
    end;

    begin perform public.approve_component_submission('00000000-0000-0000-0000-000000000401'::uuid);
        raise warning 'FAIL (test 3n): approve_component_submission(uuid,uuid) was callable by anon';
    exception when insufficient_privilege then
        raise notice 'PASS (test 3n): approve_component_submission(uuid,uuid) correctly denied to anon';
    end;

    begin perform public.reject_component_submission('00000000-0000-0000-0000-000000000401'::uuid, 'x');
        raise warning 'FAIL (test 3o): reject_component_submission(uuid,text) was callable by anon';
    exception when insufficient_privilege then
        raise notice 'PASS (test 3o): reject_component_submission(uuid,text) correctly denied to anon';
    end;

    begin perform public.is_platform_moderator('00000000-0000-0000-0000-000000000401'::uuid);
        raise warning 'FAIL (test 3p): is_platform_moderator(uuid) was callable by anon';
    exception when insufficient_privilege then
        raise notice 'PASS (test 3p): is_platform_moderator(uuid) correctly denied to anon';
    end;

    begin perform public.is_platform_staff('00000000-0000-0000-0000-000000000401'::uuid);
        raise warning 'FAIL (test 3q): is_platform_staff(uuid) was callable by anon';
    exception when insufficient_privilege then
        raise notice 'PASS (test 3q): is_platform_staff(uuid) correctly denied to anon';
    end;

    begin perform public.report_content('build', '00000000-0000-0000-0000-000000000401'::uuid, 'x');
        raise warning 'FAIL (test 3r): report_content(text,uuid,text) was callable by anon';
    exception when insufficient_privilege then
        raise notice 'PASS (test 3r): report_content(text,uuid,text) correctly denied to anon';
    end;

    begin perform public.resolve_report('00000000-0000-0000-0000-000000000401'::uuid, 'dismissed');
        raise warning 'FAIL (test 3s): resolve_report(uuid,text,text) was callable by anon';
    exception when insufficient_privilege then
        raise notice 'PASS (test 3s): resolve_report(uuid,text,text) correctly denied to anon';
    end;

    begin perform public.grant_profile_role('00000000-0000-0000-0000-000000000402'::uuid, 'community_builder', 'x');
        raise warning 'FAIL (test 3t): grant_profile_role(uuid,text,text) was callable by anon';
    exception when insufficient_privilege then
        raise notice 'PASS (test 3t): grant_profile_role(uuid,text,text) correctly denied to anon';
    end;

    begin perform public.revoke_profile_role('00000000-0000-0000-0000-000000000402'::uuid, 'community_builder', 'x');
        raise warning 'FAIL (test 3u): revoke_profile_role(uuid,text,text) was callable by anon';
    exception when insufficient_privilege then
        raise notice 'PASS (test 3u): revoke_profile_role(uuid,text,text) correctly denied to anon';
    end;

    begin perform public.submit_feedback('bug', 'x');
        raise warning 'FAIL (test 3v): submit_feedback(text,text,text) was callable by anon';
    exception when insufficient_privilege then
        raise notice 'PASS (test 3v): submit_feedback(text,text,text) correctly denied to anon';
    end;

    begin perform public.redeem_beta_invite('x');
        raise warning 'FAIL (test 3w): redeem_beta_invite(text) was callable by anon';
    exception when insufficient_privilege then
        raise notice 'PASS (test 3w): redeem_beta_invite(text) correctly denied to anon';
    end;

    begin perform public.sync_discord_identity();
        raise warning 'FAIL (test 3x): sync_discord_identity() was callable by anon';
    exception when insufficient_privilege then
        raise notice 'PASS (test 3x): sync_discord_identity() correctly denied to anon';
    end;
end $$;
reset role;
rollback to savepoint test_3_anon;

-- ---------------------------------------------------------------------
-- Test 4: get_public_profile_roles(uuid) — unaffected by 0033, still
-- callable by both anon and authenticated (0032's own design). Also
-- exercised more thoroughly, with real fixture data, in
-- milestone_22_profile_roles_visibility.test.sql — this is a light
-- confirmation scoped to "0033 didn't break this," not a duplicate of
-- that file's full coverage.
-- ---------------------------------------------------------------------
savepoint test_4;
set local role anon;
do $$
begin
    begin
        perform public.get_public_profile_roles('00000000-0000-0000-0000-000000000401'::uuid);
        raise notice 'PASS (test 4a): get_public_profile_roles(uuid) still executable by anon after 0033';
    exception when insufficient_privilege then
        raise warning 'FAIL (test 4a): get_public_profile_roles(uuid) unexpectedly denied to anon after 0033';
    end;
end $$;
reset role;
rollback to savepoint test_4;

savepoint test_4_auth;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000401', true);
set local role authenticated;
do $$
begin
    begin
        perform public.get_public_profile_roles('00000000-0000-0000-0000-000000000401'::uuid);
        raise notice 'PASS (test 4b): get_public_profile_roles(uuid) still executable by authenticated after 0033';
    exception when insufficient_privilege then
        raise warning 'FAIL (test 4b): get_public_profile_roles(uuid) unexpectedly denied to authenticated after 0033';
    end;
end $$;
reset role;
rollback to savepoint test_4_auth;

-- ---------------------------------------------------------------------
-- Test 5: service_role keeps whatever access it already had (0033 never
-- touches it) — spot-checked across one function from each category.
-- ---------------------------------------------------------------------
savepoint test_5;
set local role service_role;
do $$
begin
    -- sync_component_legacy_fields() is `returns trigger` — Postgres
    -- refuses direct SELECT/PERFORM invocation of any trigger function
    -- for ANY role at all, including service_role and the function
    -- owner ("trigger functions can only be called as triggers"). That
    -- restriction is unconditional and unrelated to the GRANT/REVOKE
    -- permissions 0033 manages, so a direct call can't be used to prove
    -- access here the way it can for the other two functions below —
    -- this checks the ACL directly instead.
    if has_function_privilege('service_role', 'public.sync_component_legacy_fields()'::regprocedure, 'EXECUTE') then
        raise notice 'PASS (test 5a): service_role still holds EXECUTE on sync_component_legacy_fields()';
    else
        raise warning 'FAIL (test 5a): service_role unexpectedly lost EXECUTE on sync_component_legacy_fields()';
    end if;

    begin perform public.create_notification(
            '00000000-0000-0000-0000-000000000402'::uuid,
            '00000000-0000-0000-0000-000000000401'::uuid,
            'comment'
        );
        raise notice 'PASS (test 5b): create_notification(...) still executable by service_role';
    exception when insufficient_privilege then
        raise warning 'FAIL (test 5b): create_notification(...) unexpectedly denied to service_role';
    end;

    begin perform public.is_catalog_moderator('00000000-0000-0000-0000-000000000401'::uuid);
        raise notice 'PASS (test 5c): is_catalog_moderator(uuid) still executable by service_role';
    exception when insufficient_privilege then
        raise warning 'FAIL (test 5c): is_catalog_moderator(uuid) unexpectedly denied to service_role';
    end;
end $$;
reset role;
rollback to savepoint test_5;

-- ---------------------------------------------------------------------
-- Test 6: the function owner always retains access regardless of any
-- ACL entry (Postgres ownership bypasses object privilege checks
-- entirely) — run with NO role switch at all, i.e. as whichever role
-- this test connection authenticated as (the migration-applying
-- superuser, the owner of every function 0020-0033 created).
-- ---------------------------------------------------------------------
savepoint test_6;
do $$
begin
    -- Same trigger-only restriction as test 5a: sync_component_legacy_
    -- fields() cannot be directly invoked by any role, including the
    -- owner, so ownership is proven via the ACL (owners implicitly hold
    -- every privilege on their own object) rather than a call.
    if has_function_privilege(current_user, 'public.sync_component_legacy_fields()'::regprocedure, 'EXECUTE') then
        raise notice 'PASS (test 6a): the connecting/owning role still holds EXECUTE on sync_component_legacy_fields()';
    else
        raise warning 'FAIL (test 6a): the connecting/owning role unexpectedly lacks EXECUTE on sync_component_legacy_fields()';
    end if;

    begin perform public.create_notification(
            '00000000-0000-0000-0000-000000000402'::uuid,
            '00000000-0000-0000-0000-000000000401'::uuid,
            'comment'
        );
        raise notice 'PASS (test 6b): the connecting/owning role can still call create_notification(...)';
    exception when insufficient_privilege then
        raise warning 'FAIL (test 6b): the connecting/owning role was unexpectedly denied create_notification(...)';
    end;
end $$;
rollback to savepoint test_6;

-- ---------------------------------------------------------------------
-- Test 7: default privileges for a NEW postgres-owned public-schema
-- function, covering both scopes 0033 now sets:
--
--   7a — did BOTH of 0033's `alter default privileges` statements take
--        effect on the catalog entries they control? The GLOBAL one
--        (`alter default privileges for role postgres revoke execute on
--        functions from public;`, no `in schema`) must produce a
--        pg_default_acl row with defaclnamespace = 0 and no PUBLIC
--        entry; the SCHEMA-scoped one
--        (`alter default privileges for role postgres in schema public
--        revoke execute on functions from anon, authenticated;`) must
--        produce a row for the public schema with no anon/authenticated
--        entry.
--
--   7b — is a function created after 0033, using those catalog entries,
--        actually unreachable by public/anon/authenticated?
--
-- Local testing found and fixed a real gap here: with only the
-- SCHEMA-scoped revoke (0033's original form), 7a's schema-scoped check
-- passed but 7b failed — a brand-new function still ended up with
-- PUBLIC EXECUTE (and therefore anon/authenticated too, since PUBLIC
-- privileges apply to every role). Root cause, confirmed by direct
-- inspection: PostgreSQL grants EXECUTE to PUBLIC on every new function
-- by default, and that hardcoded GLOBAL default is only overridden by a
-- matching GLOBAL pg_default_acl entry — a schema-scoped entry cannot
-- cancel it (before the fix, no global entry existed at all for
-- (postgres, functions), only the schema-scoped one). No event trigger
-- was involved (checked pg_event_trigger directly; none touch
-- public-schema function grants). Adding the global-scope revoke to
-- 0033 (see its own header) closed this completely. This does NOT
-- affect the 17 functions 0033 already revokes directly (tests 1-6
-- above confirm those are correctly locked down) — it only ever
-- affected functions created AFTER 0033 runs.
--
-- Cleanup safety: CREATE FUNCTION is DDL and can't run as dynamic SQL
-- inside a `do $$ ... $$` block without a second layer of dollar-quote
-- escaping, so it stays a top-level statement, matching this file's own
-- role-switch convention. The check logic below is wrapped in its own
-- `exception when others` so a bug in the check itself can't abort the
-- transaction before reaching the `drop function` two lines down — but
-- even if it did (e.g. under a harness that aborts the whole script on
-- any unhandled error, such as `ON_ERROR_STOP=1`), the probe function
-- still could not survive: this whole file is one outer `begin ...
-- rollback` transaction that never issues a `commit`, and Postgres
-- rolls back any still-open transaction automatically when the
-- connection closes. The explicit `drop function` + `rollback to
-- savepoint` below is defense in depth, not the only thing standing
-- between this probe and a permanent leftover object.
-- ---------------------------------------------------------------------
savepoint test_7;
create function public._m0033_default_privilege_probe() returns void
language sql as $$ select 1 $$;

do $$
declare
    v_probe_oid oid := 'public._m0033_default_privilege_probe()'::regprocedure::oid;
    v_global_defacl_has_public boolean;
    v_schema_defacl_has_client_roles boolean;
    v_public_has_execute boolean;
begin
    begin
        -- 7a: check both catalog entries 0033's two statements control,
        -- independent of what any later CREATE FUNCTION ends up with.
        select exists (
            select 1
            from pg_default_acl da
            cross join lateral aclexplode(da.defaclacl) as a
            where da.defaclrole = 'postgres'::regrole
              and da.defaclnamespace = 0
              and da.defaclobjtype = 'f'
              and a.grantee = 0
              and a.privilege_type = 'EXECUTE'
        ) into v_global_defacl_has_public;

        select exists (
            select 1
            from pg_default_acl da
            cross join lateral aclexplode(da.defaclacl) as a
            where da.defaclrole = 'postgres'::regrole
              and da.defaclnamespace = 'public'::regnamespace
              and da.defaclobjtype = 'f'
              and a.grantee in ('anon'::regrole::oid, 'authenticated'::regrole::oid)
              and a.privilege_type = 'EXECUTE'
        ) into v_schema_defacl_has_client_roles;

        if v_global_defacl_has_public or v_schema_defacl_has_client_roles then
            raise warning 'FAIL (test 7a): pg_default_acl for role postgres/functions still grants public (global scope) or anon/authenticated (public schema scope) EXECUTE — 0033''s alter default privileges statements did not take full effect';
        else
            raise notice 'PASS (test 7a): pg_default_acl for role postgres/functions has no public (global) or anon/authenticated (public schema) EXECUTE entry, as 0033''s statements intend';
        end if;

        -- 7b: check what a real newly-created function actually ends up
        -- with, end to end.
        --
        -- PUBLIC is a pseudo-role, not a real row in pg_roles — it cannot
        -- be passed as the `user` argument to has_function_privilege()
        -- (that would error "role \"public\" does not exist"). Its
        -- EXECUTE grant can only be checked by looking for a
        -- grantee = 0 (PUBLIC's sentinel oid in an exploded ACL) entry
        -- directly.
        select exists (
            select 1
            from pg_proc p
            cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) as a
            where p.oid = v_probe_oid and a.grantee = 0 and a.privilege_type = 'EXECUTE'
        ) into v_public_has_execute;

        if has_function_privilege('anon', v_probe_oid::regprocedure, 'EXECUTE')
            or has_function_privilege('authenticated', v_probe_oid::regprocedure, 'EXECUTE')
            or v_public_has_execute
        then
            raise warning 'FAIL (test 7b): a newly-created postgres-owned function is still reachable by public/anon/authenticated in practice — 0033''s default-privilege statements did not fully close the gap; future migrations must not rely on this alone and should keep explicitly revoking from public on any new non-public function';
        else
            raise notice 'PASS (test 7b): a newly-created postgres-owned function has NO public/anon/authenticated EXECUTE in practice';
        end if;
    exception when others then
        raise warning 'FAIL (test 7): the ACL check itself errored (%) — treat as a failure, not a pass', sqlerrm;
    end;
end $$;

drop function public._m0033_default_privilege_probe();
rollback to savepoint test_7;

rollback;
