-- Migration: 0045_moderation_actions_preserve_audit
-- Milestone: none — Launch Readiness self-service account deletion.
-- Status: PROPOSED — not yet applied. Depends on 0000-0044 being
-- applied first.
--
-- Purpose: implements decision packet item 12
-- (docs/milestones/MILESTONE_27B_ADULT_OWNER_DECISION_PACKET.md) —
-- "preserve moderation audit records while removing departed users' or
-- moderators' identities where necessary." Today,
-- `moderation_actions.actor_id` is `not null references auth.users(id)
-- on delete cascade` (0028_moderation.sql) — deleting the acting
-- account destroys the entire audit row, not just the attribution. This
-- is a hard prerequisite for self-service account deletion generally,
-- not only for a departing-moderator edge case: a self-deletion's own
-- `account_deleted` audit row (0048_self_delete_account.sql) is
-- authored with `actor_id = auth.uid()` — the deleting user's own id —
-- so without this fix, every self-deletion's audit trail would destroy
-- itself the instant the Auth user is actually removed, defeating the
-- entire purpose of writing it.
--
--   1. `alter column actor_id drop not null` — required before the FK
--      can target SET NULL; a NOT NULL column can never be nulled by a
--      referencing delete.
--   2. Drop the existing `on delete cascade` FK, re-add it as
--      `on delete set null`.
--
-- No data is deleted or altered by this migration itself — only the
-- constraint shape changes. Every existing `moderation_actions` row's
-- `actor_id` value is preserved exactly as-is.
--
-- Touches: moderation_actions (nullability + FK behavior only).
--
-- Rollback: see 0045_moderation_actions_preserve_audit_rollback.sql in
-- supabase/rollbacks/. Restoring `not null`/`cascade` is only safe if no
-- row's `actor_id` is currently null — the rollback file checks this
-- explicitly and aborts rather than silently failing or destroying data.

begin;

alter table public.moderation_actions
    alter column actor_id drop not null;

-- Looked up by querying pg_constraint rather than hardcoding
-- "moderation_actions_actor_id_fkey" — this schema has at least one
-- precedent (0043's own header references "build_updates_user_id_fkey"
-- surviving a table rename to build_revisions) of an auto-generated FK
-- name not matching its current table/column names, so this migration
-- doesn't assume the name matches Postgres's default-naming convention.
do $$
declare
    v_conname text;
begin
    select conname into v_conname
    from pg_constraint
    where conrelid = 'public.moderation_actions'::regclass
      and contype = 'f'
      and confrelid = 'auth.users'::regclass;

    if v_conname is null then
        raise exception 'moderation_actions has no FK to auth.users on actor_id — expected one to exist (0028_moderation.sql)';
    end if;

    execute format('alter table public.moderation_actions drop constraint %I', v_conname);
end $$;

alter table public.moderation_actions
    add constraint moderation_actions_actor_id_fkey
    foreign key (actor_id) references auth.users(id) on delete set null;

commit;
