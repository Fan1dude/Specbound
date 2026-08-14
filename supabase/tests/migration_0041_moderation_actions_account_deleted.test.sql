-- Migration 0041 test —
-- supabase/tests/migration_0041_moderation_actions_account_deleted.test.sql
--
-- Covers migration 0041_add_account_deleted_action_type: proves
-- moderation_actions.action_type now accepts 'account_deleted' (schema
-- support only — no deletion procedure is implemented or run by this
-- migration or this test), that every pre-existing value
-- ('report_resolved', 'role_granted', 'role_revoked', 'content_removed')
-- still works unchanged, that a genuinely invalid value is still
-- rejected, and that the rollback/reapplication round-trip behaves
-- exactly as its own header documents: the rollback is an intentional
-- no-op (matching 0037's and 0039's established asymmetric-rollback
-- convention for widened CHECK constraints), so "rolling back" and
-- "reapplying" both leave 'account_deleted' accepted throughout.
--
-- STATUS: executed against the local disposable Supabase/Docker stack —
-- see this PR's own report for the exact assertion count and pass
-- result. NOT yet executed against a disposable/staging Supabase project
-- or against production. Depends on migrations 0001-0041 already being
-- applied.
--
-- Never run this against a project with real data — same fixture-safety
-- posture as every other test file in this suite. Fail-closed: every
-- FAIL is raised via `raise exception ... using errcode = 'M0041'`.

begin;

insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-0000-0000-000000000701', 'm0041-actor@example.invalid', '{"username": "m0041_actor_test"}'::jsonb),
    ('00000000-0000-0000-0000-000000000702', 'm0041-target@example.invalid', '{"username": "m0041_target_test"}'::jsonb)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- Test 1: 'account_deleted' is now a valid action_type — a direct
-- insert (this migration adds schema support only; the actual
-- account-deletion procedure that would eventually write a row like
-- this is explicitly not implemented here).
-- ---------------------------------------------------------------------
savepoint test_1;
do $$
begin
    insert into public.moderation_actions (actor_id, action_type, target_type, target_id, note)
    values (
        '00000000-0000-0000-0000-000000000701', 'account_deleted', 'profile',
        '00000000-0000-0000-0000-000000000702', 'M0041 test row — not a real deletion'
    );
    raise notice 'PASS (test 1): account_deleted is now accepted by the widened CHECK constraint';
exception when check_violation then
    raise exception 'FAIL (test 1): account_deleted was rejected — migration 0041 did not widen the constraint correctly' using errcode = 'M0041';
end $$;
rollback to savepoint test_1;

-- ---------------------------------------------------------------------
-- Test 2: every pre-existing value still works — non-regression, all
-- four checked in one pass.
-- ---------------------------------------------------------------------
savepoint test_2;
do $$
declare
    v_type text;
begin
    for v_type in select unnest(array['report_resolved', 'role_granted', 'role_revoked', 'content_removed'])
    loop
        begin
            insert into public.moderation_actions (actor_id, action_type, target_type, target_id, note)
            values ('00000000-0000-0000-0000-000000000701', v_type, 'profile', '00000000-0000-0000-0000-000000000702', 'M0041 regression check');
        exception when check_violation then
            raise exception 'FAIL (test 2, %): pre-existing action_type value was unexpectedly rejected after migration 0041', v_type using errcode = 'M0041';
        end;
    end loop;
    raise notice 'PASS (test 2): all four pre-existing action_type values still accepted';
end $$;
rollback to savepoint test_2;

-- ---------------------------------------------------------------------
-- Test 3: a genuinely invalid value is still rejected — proves the
-- constraint is still a real, closed allow-list, not accidentally
-- widened into "anything goes".
-- ---------------------------------------------------------------------
savepoint test_3;
do $$
begin
    begin
        insert into public.moderation_actions (actor_id, action_type, target_type, target_id, note)
        values ('00000000-0000-0000-0000-000000000701', 'not_a_real_action_type', 'profile', '00000000-0000-0000-0000-000000000702', null);
        raise exception 'FAIL (test 3): a bogus action_type value was accepted' using errcode = 'M0041';
    exception when check_violation then
        raise notice 'PASS (test 3): a bogus action_type value is still correctly rejected';
    end;
end $$;
rollback to savepoint test_3;

-- ---------------------------------------------------------------------
-- Test 4: rollback/reapplication round-trip — the rollback file is an
-- intentional no-op (see its own header), so 'account_deleted' remains
-- accepted after "rolling back", and remains accepted after reapplying
-- 0041's own statements again. Both legs are exercised explicitly
-- rather than assumed from the rollback file's comment alone.
-- ---------------------------------------------------------------------
savepoint test_4;

-- The rollback file has no DDL to run (see its header) — nothing to
-- execute here for that leg beyond confirming the constraint is
-- unchanged, which is the entire point of it being a no-op.
do $$
begin
    if not exists (
        select 1 from pg_constraint
        where conrelid = 'public.moderation_actions'::regclass
          and contype = 'c'
          and pg_get_constraintdef(oid) like '%account_deleted%'
    ) then
        raise exception 'FAIL (test 4a): account_deleted unexpectedly absent before the rollback no-op even runs' using errcode = 'M0041';
    end if;
    raise notice 'PASS (test 4a): constraint carries account_deleted going into the rollback rehearsal (rollback has nothing to do, by design)';
end $$;

-- Reapply migration 0041's own statements verbatim — drop/add is always
-- safe to repeat, proving reapplication after a (no-op) rollback works.
alter table public.moderation_actions
    drop constraint moderation_actions_action_type_check;

alter table public.moderation_actions
    add constraint moderation_actions_action_type_check
    check (action_type in (
        'report_resolved', 'role_granted', 'role_revoked', 'content_removed',
        'account_deleted'
    ));

do $$
begin
    insert into public.moderation_actions (actor_id, action_type, target_type, target_id, note)
    values ('00000000-0000-0000-0000-000000000701', 'account_deleted', 'profile', '00000000-0000-0000-0000-000000000702', 'M0041 reapplication check');
    raise notice 'PASS (test 4b): reapplying migration 0041''s statements after the rollback rehearsal leaves account_deleted accepted';
exception when check_violation then
    raise exception 'FAIL (test 4b): reapplying migration 0041 did not restore account_deleted support' using errcode = 'M0041';
end $$;

-- ---------------------------------------------------------------------
-- Cleanup: remove the disposable auth.users rows created above.
-- Redundant with the final ROLLBACK below, but explicit for the same
-- defense-in-depth reasoning documented in this suite's other files.
-- ---------------------------------------------------------------------
delete from auth.users where email like 'm0041-%@example.invalid';

rollback;
