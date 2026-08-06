-- Migration: 0024_profile_headline_and_featured_build
-- Milestone: 20 (Builder Portfolio)
-- Status: PROPOSED — not yet applied. Depends on 0000-0023 being applied
-- first.
--
-- Purpose: adds the two profiles columns the Builder Portfolio redesign
-- needs (see docs/milestones/MILESTONE_20_BUILDER_PORTFOLIO_SPECIFICATION.md
-- §3.3, §16):
--   - headline: a short (<=120 char) hero tagline, distinct from the
--     existing longer `bio` column (About Builder section). Optional —
--     both columns may be null independently.
--   - featured_build_id: the builder's own explicit pin for the Featured
--     Project section. Builder-controlled by design decision — never
--     selected by likes_count or any other engagement metric.
--
-- Touches: public.profiles (2 new nullable columns, 1 new CHECK, 1 new FK
-- to public.builds), 1 new trigger function + trigger. Does not touch RLS:
-- the existing "Users can update their own profile" policy (0000) already
-- covers write access to these two new columns, since it's a whole-row
-- policy keyed on auth.uid() = id, not a column allowlist. What that
-- policy can't express is "the referenced build must belong to the same
-- profile" — a cross-row constraint — so a trigger enforces that
-- separately. The trigger checks ownership only, not visibility: a builder
-- may pin a build that isn't currently public (e.g. still finishing it).
-- Visibility eligibility is re-checked every time the page renders (see
-- spec §17.2), not enforced at write time. The application layer (Settings
-- UI, spec §19 Phase 5 / §20.2) additionally restricts the picker to only
-- ever offer the builder's own published builds as options — this trigger
-- is defense in depth, not the primary correctness mechanism.
--
-- featured_build_id uses ON DELETE SET NULL: deleting the referenced build
-- silently un-pins it rather than blocking the delete or leaving a
-- dangling reference. A profile left with featured_build_id = null (either
-- from this or from never having set one) falls through to the documented
-- fallback chain (spec §17.2) at render time, never an error.
--
-- Rollback: see 0024_profile_headline_and_featured_build_rollback.sql in
-- supabase/rollbacks/. Drops the trigger/function first, then both new
-- columns (the CHECK constraint and the FK both drop automatically with
-- their owning column).

begin;

alter table public.profiles
    add column headline text,
    add column featured_build_id uuid references public.builds(id) on delete set null;

alter table public.profiles
    add constraint profiles_headline_length_check
    check (headline is null or char_length(headline) <= 120);

-- Runs with the invoking user's own privileges (no reason to elevate — it
-- only checks a row the invoking user already owns via the outer UPDATE's
-- own RLS pass) and pins search_path defensively, matching the convention
-- set by public.set_updated_at() in 0001.
create or replace function public.validate_featured_build()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
    if new.featured_build_id is not null then
        if not exists (
            select 1 from public.builds
            where id = new.featured_build_id
              and user_id = new.id
        ) then
            raise exception 'featured_build_id must reference a build owned by this profile';
        end if;
    end if;
    return new;
end;
$$;

create trigger validate_featured_build_before_write
    before insert or update of featured_build_id on public.profiles
    for each row
    execute function public.validate_featured_build();

commit;
