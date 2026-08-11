-- Rollback for 0034_profile_guidelines_accepted_version.
-- Drops the column (and its CHECK constraint along with it).
-- guidelines_accepted_at is untouched.

begin;

alter table public.profiles
    drop column if exists guidelines_accepted_version;

commit;
