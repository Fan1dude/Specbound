-- Migration 0040 test —
-- supabase/tests/migration_0040_handle_new_user_search_path.test.sql
--
-- Covers migration 0040_harden_handle_new_user_search_path: proves the
-- function now carries search_path = public, pg_temp (closing the one
-- gap the Milestone 27 launch audit found across all 30 SECURITY
-- DEFINER functions in this schema), that its real, five-column
-- signup behavior — coalesce-based username/display_name defaulting to
-- the email local-part, empty bio/avatar_url — is completely unchanged
-- (proven by an actual auth.users insert firing the real trigger, not
-- just reading the function's source), that EXECUTE grants (including
-- the PUBLIC pseudo-role grant, present on this function since the
-- 0000 baseline and untouched by a pure `create or replace function`)
-- are byte-for-byte identical before and after, and that the paired
-- rollback/reapplication round-trip leaves the function in the exact
-- same two states each time.
--
-- STATUS: executed against the local disposable Supabase/Docker stack —
-- see this PR's own report for the exact assertion count and pass
-- result. NOT yet executed against a disposable/staging Supabase project
-- or against production; run it there too before trusting the result in
-- an environment closer to production. Depends on migrations 0001-0040
-- already being applied.
--
-- Never run this against a project with real data — same fixture-safety
-- posture as every other test file in this suite (fake auth.users rows,
-- namespaced emails, single outer transaction ending in ROLLBACK, each
-- test in its own SAVEPOINT).
--
-- Fail-closed design: identical convention to migration_0038's own file
-- — every FAIL is raised via `raise exception ... using errcode =
-- 'M0040'`, chosen to be unmistakably this file's own and never collide
-- with a built-in code.

begin;

-- ---------------------------------------------------------------------
-- Test 1: search_path is now pinned, function is still SECURITY
-- DEFINER, still owned by postgres — the migration's actual purpose,
-- checked directly against pg_proc metadata.
-- ---------------------------------------------------------------------
savepoint test_1;
do $$
declare
    v_oid oid := to_regprocedure('public.handle_new_user()');
begin
    if v_oid is null then
        raise exception 'FAIL (test 1): handle_new_user() does not exist' using errcode = 'M0040';
    end if;

    if not exists (
        select 1 from pg_proc where oid = v_oid
            and 'search_path=public, pg_temp' = any(proconfig)
    ) then
        raise exception 'FAIL (test 1): search_path is not "public, pg_temp" after migration 0040' using errcode = 'M0040';
    end if;

    if not (select prosecdef from pg_proc where oid = v_oid) then
        raise exception 'FAIL (test 1): function is no longer SECURITY DEFINER' using errcode = 'M0040';
    end if;

    if (select pg_get_userbyid(proowner) from pg_proc where oid = v_oid) != 'postgres' then
        raise exception 'FAIL (test 1): function ownership changed unexpectedly' using errcode = 'M0040';
    end if;

    raise notice 'PASS (test 1): handle_new_user() has search_path=public, pg_temp, still SECURITY DEFINER, still owned by postgres';
end $$;
rollback to savepoint test_1;

-- ---------------------------------------------------------------------
-- Test 2: real signup behavior with username metadata present — proves
-- the migration preserved production's actual current behavior (five
-- columns, coalesce defaulting), not the older, stale two-column
-- baseline reconstruction. A real insert into auth.users is used
-- (firing the real on_auth_user_created trigger) rather than calling
-- the function directly, since that's the only way this path is ever
-- actually exercised in production.
-- ---------------------------------------------------------------------
savepoint test_2;
insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-0000-0000-000000000601', 'm0040-user@example.invalid', '{"username": "m0040_user_test"}'::jsonb);

do $$
declare
    v_row public.profiles;
begin
    select * into v_row from public.profiles where id = '00000000-0000-0000-0000-000000000601';

    if v_row is null then
        raise exception 'FAIL (test 2): no profiles row was created by the trigger' using errcode = 'M0040';
    end if;

    if v_row.username != 'm0040_user_test' or v_row.display_name != 'm0040_user_test' then
        raise exception 'FAIL (test 2): username/display_name did not use the supplied metadata (got username=%, display_name=%)', v_row.username, v_row.display_name using errcode = 'M0040';
    end if;

    if v_row.bio != '' or v_row.avatar_url != '' then
        raise exception 'FAIL (test 2): bio/avatar_url were not defaulted to empty string' using errcode = 'M0040';
    end if;

    raise notice 'PASS (test 2): a real signup with username metadata correctly creates a five-column profile row matching production''s real behavior';
end $$;
rollback to savepoint test_2;

-- ---------------------------------------------------------------------
-- Test 3: real signup behavior with NO username metadata — proves the
-- coalesce(..., split_part(email, '@', 1)) email-local-part fallback,
-- the exact piece of behavior the older baseline reconstruction lacked
-- entirely and this migration must not have dropped.
-- ---------------------------------------------------------------------
savepoint test_3;
insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-0000-0000-000000000602', 'm0040-fallback@example.invalid', '{}'::jsonb);

do $$
declare
    v_row public.profiles;
begin
    select * into v_row from public.profiles where id = '00000000-0000-0000-0000-000000000602';

    if v_row is null then
        raise exception 'FAIL (test 3): no profiles row was created for the no-metadata signup' using errcode = 'M0040';
    end if;

    if v_row.username != 'm0040-fallback' or v_row.display_name != 'm0040-fallback' then
        raise exception 'FAIL (test 3): email-local-part fallback did not fire correctly (got username=%, display_name=%, expected m0040-fallback)', v_row.username, v_row.display_name using errcode = 'M0040';
    end if;

    raise notice 'PASS (test 3): a signup with no username metadata correctly falls back to the email local-part for both username and display_name';
end $$;
rollback to savepoint test_3;

-- ---------------------------------------------------------------------
-- Test 4: EXECUTE grants are byte-for-byte unchanged by a pure
-- `create or replace function` — including the PUBLIC pseudo-role
-- grant, present on this function since the 0000 baseline and easy to
-- miss with a case-sensitive `grantee = 'public'` filter (the real
-- stored value is 'PUBLIC', not 'public' — checked explicitly here
-- rather than repeating that mistake).
-- ---------------------------------------------------------------------
savepoint test_4;
do $$
declare
    v_oid oid := to_regprocedure('public.handle_new_user()');
    v_grantees text[];
begin
    select array_agg(distinct a.grantee_name order by a.grantee_name) into v_grantees
    from (
        select case when a.grantee = 0 then 'PUBLIC' else pg_get_userbyid(a.grantee) end as grantee_name
        from pg_proc p
        cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) as a
        where p.oid = v_oid and a.privilege_type = 'EXECUTE'
    ) a;

    if v_grantees is distinct from array['PUBLIC', 'anon', 'authenticated', 'postgres', 'service_role'] then
        raise exception 'FAIL (test 4): EXECUTE grantees changed — expected {PUBLIC,anon,authenticated,postgres,service_role}, got %', v_grantees using errcode = 'M0040';
    end if;

    raise notice 'PASS (test 4): EXECUTE grants (PUBLIC, anon, authenticated, postgres, service_role) are unchanged by migration 0040';
end $$;
rollback to savepoint test_4;

-- ---------------------------------------------------------------------
-- Test 5: the rollback restores the exact pre-0040 state — same real
-- five-column, coalesce-based body, search_path removed again — and
-- reapplying 0040 afterward restores the hardened state once more, with
-- a real signup proving behavior at each stage, not just the source text.
-- ---------------------------------------------------------------------
savepoint test_5;

-- Apply the rollback verbatim.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
as $$
begin
    insert into public.profiles (
        id, username, display_name, bio, avatar_url
    )
    values (
        new.id,
        coalesce(new.raw_user_meta_data->>'username', split_part(new.email, '@', 1)),
        coalesce(new.raw_user_meta_data->>'username', split_part(new.email, '@', 1)),
        '', ''
    );
    return new;
end;
$$;

do $$
declare
    v_oid oid := to_regprocedure('public.handle_new_user()');
begin
    if exists (
        select 1 from pg_proc where oid = v_oid and proconfig is not null
    ) then
        raise exception 'FAIL (test 5a): rollback did not remove search_path' using errcode = 'M0040';
    end if;
    raise notice 'PASS (test 5a): rollback correctly removed search_path';
end $$;

insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-0000-0000-000000000603', 'm0040-rollback@example.invalid', '{"username": "m0040_rollback_test"}'::jsonb);

do $$
begin
    if not exists (
        select 1 from public.profiles
        where id = '00000000-0000-0000-0000-000000000603'
          and username = 'm0040_rollback_test'
          and display_name = 'm0040_rollback_test'
          and bio = '' and avatar_url = ''
    ) then
        raise exception 'FAIL (test 5b): post-rollback signup behavior no longer matches production''s real five-column body' using errcode = 'M0040';
    end if;
    raise notice 'PASS (test 5b): post-rollback signup still produces the correct five-column profile — rollback preserved real behavior, not the older two-column stub';
end $$;

-- Reapply migration 0040's own forward statement, verbatim, to restore
-- the hardened state before this savepoint is rolled back.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    insert into public.profiles (
        id, username, display_name, bio, avatar_url
    )
    values (
        new.id,
        coalesce(new.raw_user_meta_data->>'username', split_part(new.email, '@', 1)),
        coalesce(new.raw_user_meta_data->>'username', split_part(new.email, '@', 1)),
        '', ''
    );
    return new;
end;
$$;

do $$
declare
    v_oid oid := to_regprocedure('public.handle_new_user()');
begin
    if not exists (
        select 1 from pg_proc where oid = v_oid
            and 'search_path=public, pg_temp' = any(proconfig)
    ) then
        raise exception 'FAIL (test 5c): reapplying 0040 after the rollback rehearsal did not restore search_path' using errcode = 'M0040';
    end if;
    raise notice 'PASS (test 5c): reapplying migration 0040 after the rollback rehearsal restored the hardened state';
end $$;

-- ---------------------------------------------------------------------
-- Cleanup: remove the disposable auth.users rows created above.
-- Redundant with the final ROLLBACK below (nothing in this file is ever
-- committed), but explicit for the same defense-in-depth reasoning
-- documented in migration_0033/0038's own test files.
-- ---------------------------------------------------------------------
delete from auth.users where email like 'm0040-%@example.invalid';

rollback;
