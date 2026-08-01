-- Rollback for: 0010_build_view_tracking
--
-- Drops the function and the cooldown table entirely, including every
-- viewer/build cooldown timestamp ever recorded — there's no separate
-- data-preserving option since the table itself is new in this migration.
-- builds.views itself is left as-is (it predates this migration and isn't
-- dropped by it either) but will simply stop being updated once the
-- function is gone.

begin;

drop function if exists public.record_build_view(uuid, uuid);
drop table if exists public.build_view_cooldowns;

commit;
