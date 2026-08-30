-- Rollback for: 0048_self_delete_account
--
-- Drops self_delete_account(). Cannot restore any account already
-- deleted through this function -- that data loss is permanent and by
-- design, the entire point of this migration, same posture 0043's own
-- rollback already documents for the identical situation.

begin;

drop function if exists public.self_delete_account();

commit;
