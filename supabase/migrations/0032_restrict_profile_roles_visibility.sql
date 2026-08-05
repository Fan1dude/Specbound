-- Migration: 0032_restrict_profile_roles_visibility
-- Milestone: 22 (Community Foundation) — post-review security hardening.
-- Status: PROPOSED — not yet applied. Depends on 0000-0031 being applied
-- first (needs profile_roles/is_platform_moderator() from 0027).
--
-- Purpose: fixes a data-exposure finding from the Milestone 20 Builder
-- Portfolio branch's final review. 0027's "Roles are readable by
-- everyone" policy was `using (true)` with no column restriction — row-
-- level security can only filter which ROWS a query returns, not which
-- COLUMNS, so any caller (including an anonymous one, hitting the REST
-- API directly rather than through this app's own UI) could retrieve
-- every column on every row: not just `role` (the only thing
-- js/repositories/communityRepository.js's getProfileRoles() ever
-- selected), but also `note` (a moderator's internal comment when
-- granting a role) and `granted_by` (which staff member granted it).
-- Nothing in the app ever displayed those two columns — the exposure
-- was real regardless, since RLS is enforced at the database, not by
-- the frontend choosing not to ask for them.
--
--   Fix, in two parts:
--
--   1. The table's own SELECT policy is tightened to authenticated
--      users only, and only for their own roles or (if they're a
--      moderator/staff) everyone's — the access
--      ManageRolesControl.js's grant/revoke UI actually needs. Anonymous
--      visitors and an ordinary authenticated user looking at someone
--      else's profile now get zero rows from the table directly.
--
--   2. get_public_profile_roles(uuid) is the replacement public read
--      path — the one a Builder Portfolio's role badges actually need,
--      for any viewer including a signed-out one. It is a function, not
--      a view: a view layered over an RLS-protected table inherits its
--      owner's RLS-bypass in a way that's easy to get subtly wrong
--      (this is exactly what Supabase's own security advisor flags as
--      "security_definer_view" — a view that unintentionally exposes
--      every row, not just the columns you meant to restrict). A
--      function's result shape is exactly what its RETURNS clause says
--      and nothing more; there is no `?select=note,granted_by` a caller
--      can append to a function call the way they could to a table or
--      view. SECURITY DEFINER so it can read every row regardless of
--      the caller's own (now much narrower) RLS visibility — the same
--      "curated read, bypassing RLS on purpose, restricted by the
--      function's own return columns" shape already used by
--      sync_discord_identity() (0026) reading auth.identities.
--
--   grant_profile_role()/revoke_profile_role() (0028) are unaffected —
--   both are already SECURITY DEFINER and write to profile_roles as
--   their own owner, which bypasses RLS the same way it always has
--   (profile_roles was never given FORCE ROW LEVEL SECURITY, so this
--   isn't a new exemption introduced here). is_platform_moderator()/
--   is_platform_staff() (0027) are unaffected for the same reason.
--
--   Every profile_roles consumer was reviewed before writing this file
--   (grep across supabase/migrations/*.sql and js/): the sole client-
--   side read is communityRepository.js's getProfileRoles(), updated in
--   the same commit as this migration to call
--   get_public_profile_roles() instead of selecting from the table
--   directly — its exported signature (userId -> role[]) is unchanged,
--   so every caller (the public profile page's own role badges, and the
--   signed-in viewer's own roles used to decide whether to show
--   ManageRolesControl) keeps working with no call-site changes.
--
-- Touches: public.profile_roles (SELECT policy replaced), one new
-- function.
--
-- Rollback: see 0032_restrict_profile_roles_visibility_rollback.sql in
-- supabase/rollbacks/. Restores the original `using (true)` policy
-- (same name, same shape as 0027 defined it) and drops the new
-- function — reintroducing the exposure this migration fixes. Only use
-- this if 0032 itself needs to be undone.

begin;

drop policy "Roles are readable by everyone" on public.profile_roles;

create policy "Users can view their own roles, moderators can view all" on public.profile_roles
    for select
    to authenticated
    using (auth.uid() = user_id or public.is_platform_moderator(auth.uid()));

create or replace function public.get_public_profile_roles(p_user_id uuid)
returns table (role text)
language sql
security definer
stable
set search_path = public, pg_temp
as $$
    select role from public.profile_roles where user_id = p_user_id;
$$;

revoke all on function public.get_public_profile_roles(uuid) from public;
grant execute on function public.get_public_profile_roles(uuid) to anon, authenticated;

commit;
