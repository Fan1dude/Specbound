-- Rollback for 0027_profile_roles.

begin;

drop function if exists public.is_platform_staff(uuid);
drop function if exists public.is_platform_moderator(uuid);
drop table if exists public.profile_roles;

commit;
