-- Rollback for: 0012_follows
--
-- Drops the trigger, both functions, and the follows table entirely,
-- including every follow relationship ever recorded — there's no
-- separate data-preserving option since the table itself is new in this
-- migration. Also drops the two count columns added to profiles; any
-- other column on profiles is left untouched.

begin;

drop trigger if exists follows_bump_counts on public.follows;
drop function if exists public.set_follow(uuid, boolean);
drop function if exists public.bump_follow_counts();
drop table if exists public.follows;

alter table public.profiles
    drop column if exists followers_count,
    drop column if exists following_count;

commit;
