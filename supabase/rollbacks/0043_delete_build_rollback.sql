-- Rollback for: 0043_delete_build
--
-- Drops delete_build(uuid) and the notifications(build_id) index this
-- migration added. Cannot restore any build the function was actually
-- used to delete — that data loss is permanent and by design; this
-- rollback only undoes the migration's own schema/function change, not
-- any of its runtime effects.

begin;

drop function if exists public.delete_build(uuid);

drop index if exists public.notifications_build_id_idx;

commit;
