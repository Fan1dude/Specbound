-- Rollback for 0025_profile_onboarding_welcomed.

begin;

alter table public.profiles
    drop column if exists onboarding_welcomed_at;

commit;
