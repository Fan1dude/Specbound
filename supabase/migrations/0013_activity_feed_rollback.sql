-- Rollback for: 0013_activity_feed
--
-- Drops get_activity_feed() only — no table, no columns, and no RLS
-- policy were added by this migration, so there is nothing else to undo.

begin;

drop function if exists public.get_activity_feed(text, timestamptz, uuid, integer);

commit;
