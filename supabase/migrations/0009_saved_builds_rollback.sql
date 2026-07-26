-- Rollback for: 0009_saved_builds
--
-- Drops the function and the table entirely, including every saved-project
-- bookmark ever recorded — there's no separate data-preserving option
-- since the table itself is new in this migration.

begin;

drop function if exists public.set_build_saved(uuid, boolean);
drop table if exists public.saved_builds;

commit;
