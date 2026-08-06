-- Rollback for: 0008_project_likes
--
-- Drops the trigger, both functions, and the table entirely, including
-- every like ever recorded — there's no separate data-preserving option
-- since the table itself is new in this migration. builds.likes_count
-- itself is left as-is (it predates this migration and isn't dropped by
-- it either) but will simply stop being updated once the trigger is gone.

begin;

drop trigger if exists likes_bump_count on public.likes;
drop function if exists public.set_build_like(uuid, boolean);
drop function if exists public.bump_likes_count();
drop table if exists public.likes;

commit;
