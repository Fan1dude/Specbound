-- Rollback for 0031_guidelines_and_notification_types.
--
-- Restoring notifications.build_id to NOT NULL will fail if any row
-- created while this migration was applied has a null build_id (i.e. any
-- role_awarded/report_resolved notification actually fired) — expected
-- and acceptable: those rows are exactly what this migration exists to
-- allow, and rolling back Milestone 22 implies those notification types
-- shouldn't exist anymore either. Delete them first if a clean rollback
-- is genuinely needed against real data.

begin;

create or replace function public.create_notification(
    p_recipient_id uuid,
    p_actor_id uuid,
    p_type text,
    p_build_id uuid,
    p_comment_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    if p_recipient_id = p_actor_id then
        return;
    end if;

    insert into public.notifications (recipient_id, actor_id, type, build_id, comment_id)
    values (p_recipient_id, p_actor_id, p_type, p_build_id, p_comment_id);
end;
$$;

revoke all on function public.create_notification(uuid, uuid, text, uuid, uuid) from public;

alter table public.notifications
    drop constraint notifications_type_check;

alter table public.notifications
    add constraint notifications_type_check
    check (type in ('comment', 'like', 'save', 'reply'));

alter table public.notifications
    alter column build_id set not null;

alter table public.profiles
    drop column if exists guidelines_accepted_at;

commit;
