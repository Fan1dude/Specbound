-- Migration 0046 test —
-- supabase/tests/migration_0046_legal_holds.test.sql
--
-- Covers migration 0046_legal_holds: zero client-readable RLS policies
-- on legal_holds (not even the affected user's own session), staff-only
-- gating on place_legal_hold()/release_legal_hold(), a non-staff/
-- moderator rejection, a non-signed-in rejection, the upsert-on-place
-- behavior, and release requiring an active hold to exist.
--
-- STATUS: intended to run against the local disposable Supabase/Docker
-- stack only — NOT executed in the authoring session (no `supabase`
-- CLI, no reachable Docker daemon, no `psql` were available). Depends
-- on migrations 0000-0046 already being applied.
--
-- Fail-closed: every assertion raises via `raise exception ... using
-- errcode = 'M0046'`.

begin;

-- ---------------------------------------------------------------------
-- Fixture: one staff account (u1), one ordinary account (u2, the held
-- account), one moderator-but-not-staff account (u3, to prove
-- moderator-tier is not sufficient).
-- ---------------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-0000-0000-000000001101', 'm0046-staff@example.invalid', '{"username": "m0046_staff"}'::jsonb),
    ('00000000-0000-0000-0000-000000001102', 'm0046-held@example.invalid', '{"username": "m0046_held"}'::jsonb),
    ('00000000-0000-0000-0000-000000001103', 'm0046-mod@example.invalid', '{"username": "m0046_mod"}'::jsonb)
on conflict (id) do nothing;

insert into public.profile_roles (user_id, role, granted_by)
values
    ('00000000-0000-0000-0000-000000001101', 'staff', null),
    ('00000000-0000-0000-0000-000000001103', 'moderator', null);

-- ---------------------------------------------------------------------
-- Test 1: RLS — zero policies for any role, including the held user's
-- own session.
-- ---------------------------------------------------------------------
savepoint test_1;
do $$
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000001102', true);
    set local role authenticated;

    if exists (select 1 from public.legal_holds where user_id = '00000000-0000-0000-0000-000000001102') then
        raise exception 'FAIL (test 1): the held user''s own session could read legal_holds directly' using errcode = 'M0046';
    end if;
    raise notice 'PASS (test 1): direct client SELECT on legal_holds returns nothing, even for the affected user''s own session (RLS enabled, zero policies)';
end $$;
reset role;
rollback to savepoint test_1;

-- ---------------------------------------------------------------------
-- Test 2: an anonymous caller is rejected by place_legal_hold().
-- ---------------------------------------------------------------------
savepoint test_2;
do $$
begin
    perform set_config('request.jwt.claim.sub', '', true);
    set local role authenticated;

    begin
        perform public.place_legal_hold('00000000-0000-0000-0000-000000001102', 'Test reason.');
        raise exception 'FAIL (test 2): an anonymous caller was allowed to place a legal hold' using errcode = 'M0046';
    exception when others then
        if sqlerrm like '%must be signed in%' then
            raise notice 'PASS (test 2): anonymous caller correctly rejected (%)', sqlerrm;
        else
            raise exception 'FAIL (test 2): rejected for the wrong reason: %', sqlerrm using errcode = 'M0046';
        end if;
    end;
end $$;
reset role;
rollback to savepoint test_2;

-- ---------------------------------------------------------------------
-- Test 3: a moderator (not staff) is rejected — staff-tier only.
-- ---------------------------------------------------------------------
savepoint test_3;
do $$
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000001103', true);
    set local role authenticated;

    begin
        perform public.place_legal_hold('00000000-0000-0000-0000-000000001102', 'Test reason.');
        raise exception 'FAIL (test 3): a moderator (not staff) was allowed to place a legal hold' using errcode = 'M0046';
    exception when others then
        if sqlerrm like '%Only staff%' then
            raise notice 'PASS (test 3): moderator-tier correctly rejected (%)', sqlerrm;
        else
            raise exception 'FAIL (test 3): rejected for the wrong reason: %', sqlerrm using errcode = 'M0046';
        end if;
    end;
end $$;
reset role;
rollback to savepoint test_3;

-- ---------------------------------------------------------------------
-- Test 4: a blank reason is rejected, even for staff.
-- ---------------------------------------------------------------------
savepoint test_4;
do $$
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000001101', true);
    set local role authenticated;

    begin
        perform public.place_legal_hold('00000000-0000-0000-0000-000000001102', '   ');
        raise exception 'FAIL (test 4): a blank reason was accepted' using errcode = 'M0046';
    exception when others then
        if sqlerrm like '%reason is required%' then
            raise notice 'PASS (test 4): blank reason correctly rejected (%)', sqlerrm;
        else
            raise exception 'FAIL (test 4): rejected for the wrong reason: %', sqlerrm using errcode = 'M0046';
        end if;
    end;
end $$;
reset role;
rollback to savepoint test_4;

-- ---------------------------------------------------------------------
-- Test 5: staff can place a hold; placing it again (upsert) refreshes
-- reason/placed_by/placed_at and clears any prior release. Not wrapped
-- in a savepoint rollback -- test 6 (release) depends on this hold
-- existing.
-- ---------------------------------------------------------------------
do $$
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000001101', true);
    set local role authenticated;

    perform public.place_legal_hold('00000000-0000-0000-0000-000000001102', 'First reason.');
    perform public.place_legal_hold('00000000-0000-0000-0000-000000001102', 'Second reason (upsert).');
end $$;
reset role;

do $$
declare
    v_reason text;
    v_released_at timestamptz;
begin
    select reason, released_at into v_reason, v_released_at
    from public.legal_holds
    where user_id = '00000000-0000-0000-0000-000000001102';

    if v_reason <> 'Second reason (upsert).' then
        raise exception 'FAIL (test 5a): upsert did not refresh the reason: %', v_reason using errcode = 'M0046';
    end if;
    raise notice 'PASS (test 5a): a second place_legal_hold() call upserts rather than erroring or duplicating';

    if v_released_at is not null then
        raise exception 'FAIL (test 5b): released_at was not cleared by the upsert' using errcode = 'M0046';
    end if;
    raise notice 'PASS (test 5b): released_at is null on an active hold';
end $$;

-- ---------------------------------------------------------------------
-- Test 6: staff can release the hold; releasing an already-released (or
-- nonexistent) hold is rejected, not silently accepted.
-- ---------------------------------------------------------------------
do $$
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000001101', true);
    set local role authenticated;

    perform public.release_legal_hold('00000000-0000-0000-0000-000000001102');
end $$;
reset role;

do $$
begin
    if (select released_at from public.legal_holds where user_id = '00000000-0000-0000-0000-000000001102') is null then
        raise exception 'FAIL (test 6a): released_at was not set' using errcode = 'M0046';
    end if;
    raise notice 'PASS (test 6a): release_legal_hold() sets released_at';
end $$;

do $$
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000001101', true);
    set local role authenticated;

    begin
        perform public.release_legal_hold('00000000-0000-0000-0000-000000001102');
        raise exception 'FAIL (test 6b): releasing an already-released hold was accepted' using errcode = 'M0046';
    exception when others then
        if sqlerrm like '%No active legal hold%' then
            raise notice 'PASS (test 6b): releasing an already-released hold correctly rejected (%)', sqlerrm;
        else
            raise exception 'FAIL (test 6b): rejected for the wrong reason: %', sqlerrm using errcode = 'M0046';
        end if;
    end;
end $$;
reset role;

-- ---------------------------------------------------------------------
-- Cleanup.
-- ---------------------------------------------------------------------
delete from auth.users where email like 'm0046-%@example.invalid';

rollback;
