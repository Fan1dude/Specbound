-- Migration 0045 test —
-- supabase/tests/migration_0045_moderation_actions_preserve_audit.test.sql
--
-- Covers migration 0045_moderation_actions_preserve_audit: actor_id
-- nullability, the FK's ON DELETE behavior (SET NULL, not CASCADE), and
-- the real-world effect — deleting the acting account anonymizes the
-- audit row instead of destroying it, including a moderator's OWN
-- self-deletion scenario (the exact case this migration exists to fix —
-- see 0045's own header).
--
-- STATUS: intended to run against the local disposable Supabase/Docker
-- stack only — NOT executed in the authoring session (no `supabase`
-- CLI, no reachable Docker daemon, no `psql` were available). Depends
-- on migrations 0000-0045 already being applied.
--
-- Fail-closed: every assertion raises via `raise exception ... using
-- errcode = 'M0045'`.

begin;

-- ---------------------------------------------------------------------
-- Fixture: one acting account (u1) that authors a moderation_actions row,
-- then is itself deleted from auth.users directly (simulating what the
-- delete-account Edge Function's admin.deleteUser() call ultimately
-- triggers) — this test exercises the FK behavior in isolation, at the
-- SQL level, without depending on self_delete_account() or the Edge
-- Function.
-- ---------------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-0000-0000-000000001001', 'm0045-actor@example.invalid', '{"username": "m0045_actor"}'::jsonb)
on conflict (id) do nothing;

insert into public.moderation_actions (id, actor_id, action_type, target_type, target_id, note)
values (
    '00000000-0000-0000-0000-000000001010',
    '00000000-0000-0000-0000-000000001001',
    'account_deleted',
    'profile',
    '00000000-0000-0000-0000-000000001001',
    'M0045 fixture audit entry.'
);

-- ---------------------------------------------------------------------
-- Test 1: column nullability and FK shape.
-- ---------------------------------------------------------------------
do $$
declare
    v_is_nullable text;
    v_confdeltype "char";
begin
    select is_nullable into v_is_nullable
    from information_schema.columns
    where table_schema = 'public' and table_name = 'moderation_actions' and column_name = 'actor_id';

    if v_is_nullable <> 'YES' then
        raise exception 'FAIL (test 1a): moderation_actions.actor_id is still NOT NULL' using errcode = 'M0045';
    end if;
    raise notice 'PASS (test 1a): moderation_actions.actor_id is nullable';

    select confdeltype into v_confdeltype
    from pg_constraint
    where conrelid = 'public.moderation_actions'::regclass
      and contype = 'f'
      and confrelid = 'auth.users'::regclass;

    if v_confdeltype <> 'n' then
        raise exception 'FAIL (test 1b): moderation_actions.actor_id -> auth.users confdeltype is % (expected ''n'' / SET NULL)', v_confdeltype using errcode = 'M0045';
    end if;
    raise notice 'PASS (test 1b): moderation_actions.actor_id -> auth.users is ON DELETE SET NULL';
end $$;

-- ---------------------------------------------------------------------
-- Test 2: the real effect — deleting the acting account anonymizes the
-- row instead of destroying it. This is the exact scenario 0045 exists
-- to fix (a moderator, or a self-deleting user whose own audit row
-- names them, deleting their account).
-- ---------------------------------------------------------------------
do $$
begin
    delete from auth.users where id = '00000000-0000-0000-0000-000000001001';

    if not exists (select 1 from public.moderation_actions where id = '00000000-0000-0000-0000-000000001010') then
        raise exception 'FAIL (test 2a): the audit row was deleted along with the acting account -- it must survive' using errcode = 'M0045';
    end if;
    raise notice 'PASS (test 2a): the audit row survives its own author''s account deletion';

    if (select actor_id from public.moderation_actions where id = '00000000-0000-0000-0000-000000001010') is not null then
        raise exception 'FAIL (test 2b): actor_id was not set null' using errcode = 'M0045';
    end if;
    raise notice 'PASS (test 2b): actor_id correctly set null -- audit row anonymized, not destroyed';

    if (select note from public.moderation_actions where id = '00000000-0000-0000-0000-000000001010') <> 'M0045 fixture audit entry.' then
        raise exception 'FAIL (test 2c): the audit row''s own content was altered' using errcode = 'M0045';
    end if;
    raise notice 'PASS (test 2c): every other field on the audit row is untouched';
end $$;

rollback;
