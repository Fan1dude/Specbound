-- Migration: 0046_legal_holds
-- Milestone: none — Launch Readiness self-service account deletion.
-- Status: PROPOSED — not yet applied. Depends on 0000-0045 being
-- applied first.
--
-- Purpose: implements decision packet item 11 (documented, private
-- legal hold, used only when legally necessary, to pause deletion for a
-- specific account) without exposing hold existence or reason to the
-- held user or the public database.
--
--   public.profiles is fully public-readable (`for select using
--   (true)`, 0000) — a hold flag or reason stored there, or on any
--   publicly-readable table, would leak "this specific user is under
--   legal hold" to anyone, including an unauthenticated request
--   directly against the Supabase REST API. This table therefore lives
--   entirely outside that surface: RLS enabled, ZERO policies of any
--   kind for any role, the same maximally-restrictive pattern already
--   established by public.catalog_moderators (0020_components_catalog.sql)
--   for an equivalently sensitive flag. Only a SECURITY DEFINER function
--   running with elevated privilege can ever read or write this table —
--   there is deliberately no standalone "check my hold status" function
--   grantable to `authenticated`, since even a boolean-only answer taking
--   an arbitrary target id would let anyone probe another account's hold
--   status. The check itself is written inline inside
--   0048_self_delete_account.sql's RPC, which only ever operates on
--   auth.uid() (its own caller), never an arbitrary target.
--
--   place_legal_hold()/release_legal_hold() below are staff-gated
--   (is_platform_staff(), the same tier grant_profile_role() already
--   requires for granting the moderator/staff roles themselves —
--   0028_moderation.sql) — never self-service, never moderator-tier.
--
-- Touches: none (one new table, two new functions).
--
-- Rollback: see 0046_legal_holds_rollback.sql in supabase/rollbacks/.

begin;

create table public.legal_holds (
    user_id uuid primary key references auth.users(id) on delete cascade,
    placed_by uuid references auth.users(id) on delete set null,
    placed_at timestamptz not null default now(),
    released_at timestamptz,
    released_by uuid references auth.users(id) on delete set null,
    reason text
);

alter table public.legal_holds enable row level security;

-- No SELECT/INSERT/UPDATE/DELETE policy for anyone, deliberately — see
-- this migration's header. With RLS enabled and no policy, all direct
-- client access (including the affected user's own session) is denied
-- outright.

create or replace function public.place_legal_hold(
    p_user_id uuid,
    p_reason text
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    if auth.uid() is null then
        raise exception 'You must be signed in.';
    end if;

    if not public.is_platform_staff(auth.uid()) then
        raise exception 'Only staff can place a legal hold.';
    end if;

    if p_reason is null or char_length(trim(p_reason)) = 0 then
        raise exception 'A reason is required to place a legal hold.';
    end if;

    insert into public.legal_holds (user_id, placed_by, placed_at, reason, released_at, released_by)
    values (p_user_id, auth.uid(), now(), p_reason, null, null)
    on conflict (user_id) do update
        set placed_by = excluded.placed_by,
            placed_at = excluded.placed_at,
            reason = excluded.reason,
            released_at = null,
            released_by = null;
end;
$$;

revoke all on function public.place_legal_hold(uuid, text) from public;
grant execute on function public.place_legal_hold(uuid, text) to authenticated;

create or replace function public.release_legal_hold(
    p_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    if auth.uid() is null then
        raise exception 'You must be signed in.';
    end if;

    if not public.is_platform_staff(auth.uid()) then
        raise exception 'Only staff can release a legal hold.';
    end if;

    update public.legal_holds
        set released_at = now(), released_by = auth.uid()
        where user_id = p_user_id and released_at is null;

    if not found then
        raise exception 'No active legal hold found for this account.';
    end if;
end;
$$;

revoke all on function public.release_legal_hold(uuid) from public;
grant execute on function public.release_legal_hold(uuid) to authenticated;

commit;
