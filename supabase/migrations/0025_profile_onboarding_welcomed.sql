-- Migration: 0025_profile_onboarding_welcomed
-- Milestone: 21 (First-Time Builder Experience)
-- Status: PROPOSED — not yet applied. Depends on 0000-0024 being applied
-- first.
--
-- Purpose: one nullable timestamp recording when a profile was shown (or
-- exited) the first-sign-in Welcome screen. The only Milestone 21 state
-- that must be durable and cross-device — see
-- docs/milestones/MILESTONE_21_FIRST_TIME_BUILDER_EXPERIENCE_SPECIFICATION.md
-- §4, §6.
--
-- Touches: public.profiles (1 new nullable column). No RLS change: the
-- existing "Users can update their own profile" policy (0000) already
-- covers writes to this column — same reasoning as 0024's headline/
-- featured_build_id addition.
--
-- Backfill — decided: every existing row is set to its own created_at,
-- not left null. Left null, every pre-existing user would see the Welcome
-- screen once after this ships, misrepresenting it to established
-- builders as if they were new. created_at is the truthful "this account
-- predates onboarding" signal and needs no invented "now" timestamp for
-- rows this migration didn't create.
--
-- Rollback: see 0025_profile_onboarding_welcomed_rollback.sql in
-- supabase/rollbacks/. Drops the column; backfilled values are not
-- recoverable after rollback — a re-applied migration re-backfills from
-- created_at again, which is fine, since created_at itself is untouched.

begin;

alter table public.profiles
    add column onboarding_welcomed_at timestamptz;

update public.profiles
    set onboarding_welcomed_at = created_at
    where onboarding_welcomed_at is null;

commit;
