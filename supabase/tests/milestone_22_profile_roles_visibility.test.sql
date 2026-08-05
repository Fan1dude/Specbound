-- Milestone 22 SQL test suite — supabase/tests/milestone_22_profile_roles_visibility.test.sql
--
-- Covers the data-exposure fix in migration 0032
-- (restrict_profile_roles_visibility): proves, at the database level —
-- not by trusting that the frontend only ever asks for `role` — that an
-- anonymous caller and an ordinary authenticated caller can no longer
-- read another user's profile_roles row directly (and therefore can't
-- retrieve `note`/`granted_by` through it), while role badges (via
-- get_public_profile_roles()) and moderator role-management workflows
-- (grant_profile_role()/revoke_profile_role(), direct table access for
-- a moderator) keep working exactly as before.
--
-- STATUS: written, NOT executed. This implementation environment has no
-- database access (anon-key only) — there is nowhere to run this
-- against. Run it once against a disposable/staging Supabase project
-- (never production) before trusting the result, via the SQL editor or
-- `psql`. Depends on migrations 0001-0032 already being applied there.
--
-- Never run this against a project with real data: it inserts three
-- fake auth.users rows and a profile_roles row. The entire file is
-- wrapped in one transaction that ends in ROLLBACK, so if it runs to
-- completion (or aborts) without a manual COMMIT, none of it persists —
-- but that safety net only helps if nothing outside this transaction
-- observes the intermediate state first.
--
-- auth.users' exact required columns vary by Supabase/GoTrue version —
-- the minimal (id, email) insert below is the commonly-documented
-- pattern but may need adjusting for a given project's schema (same
-- caveat the Milestone 19 suite carries).
--
-- Each test runs inside its own SAVEPOINT and always rolls back to it
-- afterward (pass or fail). Identity simulation follows the exact
-- pattern established by the Milestone 19 suite (supabase/tests/
-- milestone_19_parts_catalog.test.sql): `set local role authenticated`
-- plus `set_config('request.jwt.claim.sub', '<uuid>', true)` for
-- auth.uid(), and `set local role anon` with no jwt claim (auth.uid()
-- then returns null, matching a real signed-out request) for anonymous
-- calls. Both are issued as plain top-level statements, immediately
-- before the `do $$ ... $$` block they apply to, never from inside one
-- — SET ROLE's behavior when issued from within PL/pgSQL is not
-- something this unexecuted file should gamble on; top-level is
-- unambiguous, the same reasoning the Milestone 19 suite's own header
-- already gives for the identical choice. `reset role` returns to the
-- original privileged connecting role (which bypasses RLS) between
-- tests for fixture setup, also issued top-level.

begin;

-- ---------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------

insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000000101', 'm22-alice@example.invalid'),
    ('00000000-0000-0000-0000-000000000102', 'm22-bob@example.invalid'),
    ('00000000-0000-0000-0000-000000000103', 'm22-mod@example.invalid')
on conflict (id) do nothing;

-- mod is a moderator (inserted directly for fixture speed, same
-- convention the Milestone 19 suite uses for catalog_moderators).
insert into public.profile_roles (user_id, role, granted_by)
values ('00000000-0000-0000-0000-000000000103', 'moderator', '00000000-0000-0000-0000-000000000103');

-- alice holds a role with a note attached — the exact shape of data
-- this migration exists to stop leaking.
insert into public.profile_roles (user_id, role, granted_by, note)
values (
    '00000000-0000-0000-0000-000000000101',
    'community_builder',
    '00000000-0000-0000-0000-000000000103',
    'internal: vouched for by the Discord mod team, do not publish'
);

-- ---------------------------------------------------------------------
-- Test 1: an anonymous caller gets zero rows from the table directly
-- ---------------------------------------------------------------------
savepoint test_1;
set local role anon;
do $$
declare
    v_count int;
begin
    select count(*) into v_count from public.profile_roles;

    if v_count = 0 then
        raise notice 'PASS (test 1): anon sees 0 profile_roles rows via direct table SELECT';
    else
        raise warning 'FAIL (test 1): anon saw % row(s) via direct table SELECT, expected 0', v_count;
    end if;
end $$;
reset role;
rollback to savepoint test_1;

-- ---------------------------------------------------------------------
-- Test 2: an ordinary authenticated user (bob) cannot see alice's row
-- ---------------------------------------------------------------------
savepoint test_2;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000102', true);
set local role authenticated;
do $$
declare
    v_count int;
begin
    select count(*) into v_count
    from public.profile_roles
    where user_id = '00000000-0000-0000-0000-000000000101';

    if v_count = 0 then
        raise notice 'PASS (test 2): an ordinary authenticated user sees 0 rows for another user''s roles via direct table SELECT';
    else
        raise warning 'FAIL (test 2): an ordinary authenticated user saw % row(s) for another user''s roles, expected 0', v_count;
    end if;
end $$;
reset role;
rollback to savepoint test_2;

-- ---------------------------------------------------------------------
-- Test 3: a user can still see their OWN row directly (policy isn't
-- overly restrictive — this is a sanity check, not the security fix)
-- ---------------------------------------------------------------------
savepoint test_3;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000101', true);
set local role authenticated;
do $$
declare
    v_count int;
begin
    select count(*) into v_count
    from public.profile_roles
    where user_id = '00000000-0000-0000-0000-000000000101';

    if v_count = 1 then
        raise notice 'PASS (test 3): alice sees her own profile_roles row via direct table SELECT';
    else
        raise warning 'FAIL (test 3): alice saw % row(s) for her own roles, expected 1', v_count;
    end if;
end $$;
reset role;
rollback to savepoint test_3;

-- ---------------------------------------------------------------------
-- Test 4: a moderator can see another user's row directly (the access
-- ManageRolesControl.js's grant/revoke UI needs)
-- ---------------------------------------------------------------------
savepoint test_4;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000103', true);
set local role authenticated;
do $$
declare
    v_count int;
begin
    select count(*) into v_count
    from public.profile_roles
    where user_id = '00000000-0000-0000-0000-000000000101';

    if v_count = 1 then
        raise notice 'PASS (test 4): a moderator sees another user''s profile_roles row via direct table SELECT';
    else
        raise warning 'FAIL (test 4): a moderator saw % row(s) for another user''s roles, expected 1', v_count;
    end if;
end $$;
reset role;
rollback to savepoint test_4;

-- ---------------------------------------------------------------------
-- Test 5: get_public_profile_roles() still returns the role badge data
-- for an ANONYMOUS caller — the actual public.profile.html use case
-- ---------------------------------------------------------------------
savepoint test_5;
set local role anon;
do $$
declare
    v_role text;
    v_count int;
begin
    select count(*) into v_count from public.get_public_profile_roles('00000000-0000-0000-0000-000000000101');
    select role into v_role from public.get_public_profile_roles('00000000-0000-0000-0000-000000000101');

    if v_count = 1 and v_role = 'community_builder' then
        raise notice 'PASS (test 5): anon gets the correct role badge data via get_public_profile_roles()';
    else
        raise warning 'FAIL (test 5): anon got % row(s), role=% via get_public_profile_roles(), expected 1 row / community_builder', v_count, v_role;
    end if;
end $$;
reset role;
rollback to savepoint test_5;

-- ---------------------------------------------------------------------
-- Test 6: same, for an ordinary authenticated caller viewing someone
-- else's profile — confirms the badge still renders on a signed-in
-- visitor's view of another builder's portfolio
-- ---------------------------------------------------------------------
savepoint test_6;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000102', true);
set local role authenticated;
do $$
declare
    v_role text;
    v_count int;
begin
    select count(*) into v_count from public.get_public_profile_roles('00000000-0000-0000-0000-000000000101');
    select role into v_role from public.get_public_profile_roles('00000000-0000-0000-0000-000000000101');

    if v_count = 1 and v_role = 'community_builder' then
        raise notice 'PASS (test 6): an ordinary authenticated caller gets the correct role badge data via get_public_profile_roles()';
    else
        raise warning 'FAIL (test 6): got % row(s), role=% via get_public_profile_roles(), expected 1 row / community_builder', v_count, v_role;
    end if;
end $$;
reset role;
rollback to savepoint test_6;

-- ---------------------------------------------------------------------
-- Test 7: grant_profile_role()/revoke_profile_role() still work for a
-- moderator — regression check that the role-management workflow
-- (0028) wasn't broken by tightening profile_roles' SELECT policy
-- ---------------------------------------------------------------------
savepoint test_7;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000103', true);
set local role authenticated;
do $$
declare
    v_count int;
begin
    perform public.grant_profile_role('00000000-0000-0000-0000-000000000102', 'project_mentor', 'test grant');

    select count(*) into v_count
    from public.profile_roles
    where user_id = '00000000-0000-0000-0000-000000000102' and role = 'project_mentor';

    if v_count = 1 then
        raise notice 'PASS (test 7a): moderator can still grant a role after the visibility fix';
    else
        raise warning 'FAIL (test 7a): grant_profile_role() did not create the expected row (found %)', v_count;
    end if;

    perform public.revoke_profile_role('00000000-0000-0000-0000-000000000102', 'project_mentor', 'test revoke');

    select count(*) into v_count
    from public.profile_roles
    where user_id = '00000000-0000-0000-0000-000000000102' and role = 'project_mentor';

    if v_count = 0 then
        raise notice 'PASS (test 7b): moderator can still revoke a role after the visibility fix';
    else
        raise warning 'FAIL (test 7b): revoke_profile_role() did not remove the expected row (found %)', v_count;
    end if;
end $$;
reset role;
rollback to savepoint test_7;

rollback;
