-- Migration: 0030_beta_invites
-- Milestone: 22 (Community Foundation)
-- Status: PROPOSED — not yet applied. Depends on 0000-0029 being applied
-- first.
--
-- Full design: docs/milestones/MILESTONE_22_COMMUNITY_FOUNDATION_SPECIFICATION.md
-- §10, §0.2.
--
-- Purpose: shareable, redeemable invite codes for the closed beta — the
-- one half of "invite builders" that genuinely needs schema. Per the
-- Milestone 22 final design review (spec §0.2), manual invitations (a
-- staff member inviting one specific, already-known person by email)
-- need no schema at all — Supabase Auth's own admin invite-by-email
-- (supabase.auth.admin.inviteUserByEmail(), service-role key only, run
-- from the Supabase dashboard directly) already covers that case. This
-- table exists only for a code redeemable by someone whose email isn't
-- known in advance.
--
--   used_by is `unique` — fits the single-use-per-person case a closed
--   ~25-person beta actually needs. max_uses/use_count exist so a
--   single "posted in Discord" code good for several redemptions is
--   possible later without a schema change, without forcing that
--   complexity into V1's real usage (every code minted at launch is
--   expected to be max_uses = 1, the column default).
--
--   redeem_beta_invite() takes `for update` row lock for the duration of
--   its check-and-increment — closes the same race condition Milestone
--   19's SQL security audit found and fixed in
--   approve_component_submission() (0022_component_submissions.sql):
--   two people redeeming the last use of the same code at once must not
--   both succeed.
--
--   No insert policy for any client role — codes are minted directly via
--   the Supabase SQL editor (the same "operated outside the app"
--   posture already used for applying every migration in this project),
--   not through application code. No admin UI is proposed this
--   milestone.
--
-- Touches: none.
--
-- Rollback: see 0030_beta_invites_rollback.sql in supabase/rollbacks/.

begin;

create table public.beta_invites (
    code text primary key check (char_length(trim(code)) > 0),
    created_by uuid references auth.users(id) on delete set null,
    used_by uuid unique references auth.users(id) on delete set null,
    max_uses integer not null default 1 check (max_uses > 0),
    use_count integer not null default 0 check (use_count >= 0 and use_count <= max_uses),
    expires_at timestamptz,
    created_at timestamptz not null default now(),
    used_at timestamptz
);

alter table public.beta_invites enable row level security;

-- No SELECT policy for any client role either — a code's validity is
-- checked exclusively through redeem_beta_invite() below, never by a
-- client listing/browsing codes directly (which would let someone
-- enumerate valid-but-unused codes).

create or replace function public.redeem_beta_invite(p_code text)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_invite public.beta_invites;
begin
    if auth.uid() is null then
        raise exception 'You must be signed in.';
    end if;

    select * into v_invite from public.beta_invites where code = p_code for update;

    if v_invite is null then
        raise exception 'Invalid invite code.';
    end if;

    if v_invite.expires_at is not null and v_invite.expires_at < now() then
        raise exception 'This invite code has expired.';
    end if;

    if v_invite.use_count >= v_invite.max_uses then
        raise exception 'This invite code has already been used.';
    end if;

    update public.beta_invites
        set use_count = use_count + 1,
            used_by = coalesce(used_by, auth.uid()),
            used_at = now()
        where code = p_code;

    return true;
end;
$$;

revoke all on function public.redeem_beta_invite(text) from public;
grant execute on function public.redeem_beta_invite(text) to authenticated;

commit;
