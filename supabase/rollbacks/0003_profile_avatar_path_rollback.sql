-- Rollback for: 0003_profile_avatar_path
--
-- Safe, plain rollback: avatar_path is purely additive (avatar_url was
-- never touched), so dropping it loses nothing but newly-uploaded avatar
-- paths recorded since 0003 was applied. Any profile that has re-uploaded
-- an avatar since then would fall back to whatever avatar_url still holds
-- (likely stale/unset), the same as before 0003 ran.

begin;

alter table public.profiles drop column if exists avatar_path;

commit;
