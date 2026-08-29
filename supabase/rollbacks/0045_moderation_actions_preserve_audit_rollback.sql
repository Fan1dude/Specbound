-- Rollback for: 0045_moderation_actions_preserve_audit
--
-- Restores NOT NULL + ON DELETE CASCADE on moderation_actions.actor_id.
-- Aborts rather than proceeding if any row's actor_id is already null —
-- restoring NOT NULL would either fail outright against such a row, or
-- (if somehow forced) require destroying a real audit record's
-- remaining information to succeed. Neither is acceptable; this mirrors
-- the same reasoning 0041's own rollback already documents for a
-- structurally identical situation on this same table.

begin;

do $$
begin
    if exists (select 1 from public.moderation_actions where actor_id is null) then
        raise exception 'Cannot roll back 0045: at least one moderation_actions row has actor_id = null (a real anonymized audit record). Restoring NOT NULL would fail against it or require destroying it.';
    end if;
end $$;

alter table public.moderation_actions
    drop constraint moderation_actions_actor_id_fkey;

alter table public.moderation_actions
    add constraint moderation_actions_actor_id_fkey
    foreign key (actor_id) references auth.users(id) on delete cascade;

alter table public.moderation_actions
    alter column actor_id set not null;

commit;
