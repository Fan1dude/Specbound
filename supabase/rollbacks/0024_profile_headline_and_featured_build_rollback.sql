-- Rollback for 0024_profile_headline_and_featured_build.
-- Drop order: trigger before function (dependency), then both columns
-- (the CHECK constraint and the FK both drop automatically with their
-- owning column — no separate `drop constraint` needed for either).

begin;

drop trigger if exists validate_featured_build_before_write on public.profiles;
drop function if exists public.validate_featured_build();

alter table public.profiles
    drop column if exists featured_build_id,
    drop column if exists headline;

commit;
