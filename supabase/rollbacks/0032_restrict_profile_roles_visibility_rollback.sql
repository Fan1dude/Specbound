-- Rollback for: 0032_restrict_profile_roles_visibility
--
-- Restores the original 0027 policy exactly (same name, same `using
-- (true)` shape) and drops get_public_profile_roles(). Reintroduces the
-- data-exposure gap 0032 fixes (note/granted_by become readable by
-- anyone again) — only run this if 0032 itself needs to be undone.
--
-- Note: if this rollback is applied, communityRepository.js's
-- getProfileRoles() must also be reverted to select directly from
-- public.profile_roles (see that file's git history alongside this
-- migration's own commit) — otherwise the app keeps calling a function
-- that no longer exists.

begin;

revoke all on function public.get_public_profile_roles(uuid) from anon, authenticated;
drop function if exists public.get_public_profile_roles(uuid);

drop policy "Users can view their own roles, moderators can view all" on public.profile_roles;

create policy "Roles are readable by everyone" on public.profile_roles
    for select using (true);

commit;
