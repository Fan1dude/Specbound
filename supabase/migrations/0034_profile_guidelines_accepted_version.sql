-- Migration: 0034_profile_guidelines_accepted_version
-- Milestone: 22 (Community Foundation) follow-up — Community Guidelines
-- finalization.
-- Status: PROPOSED — not yet applied. Depends on 0000-0033 being applied
-- first (specifically 0031, which introduced guidelines_accepted_at).
--
-- Purpose: the Community Guidelines page shipped in 0031/Milestone 22 as
-- a draft. Some users already have a non-null guidelines_accepted_at from
-- accepting that draft page. Now that the guidelines have been finalized,
-- that draft-era acceptance must not count as acceptance of the final
-- text — the gate needs to know *which* version of the guidelines a user
-- last agreed to, not just *whether* they ever agreed to something.
--
-- Touches: public.profiles (1 new nullable column + 1 CHECK constraint).
-- No RLS change: the existing "Users can update their own profile"
-- policy (0000) already covers writes to this column — same reasoning as
-- 0024's headline/featured_build_id and 0025's onboarding_welcomed_at.
--
-- Backfill — deliberately NONE, unlike 0025's created_at backfill. Every
-- existing row (whether guidelines_accepted_at is null or not) is left
-- with guidelines_accepted_version = null. A pre-existing non-null
-- guidelines_accepted_at reflects acceptance of the earlier draft text,
-- not the finalized version, so it must not be treated as satisfying the
-- current version check. Leaving version null for those rows is what
-- makes that distinction real: the application gate compares the stored
-- version against js/config/guidelines.js's CURRENT_GUIDELINES_VERSION
-- and re-prompts whenever they don't match, regardless of
-- guidelines_accepted_at.
--
-- Type/constraint: text, not a date/timestamp column. The version is a
-- human-assigned label for a specific published revision of the
-- guidelines copy (currently "2026-08-11", matching the page's "Last
-- updated" date), not a timestamp of the acceptance event itself — that
-- remains guidelines_accepted_at's job. The CHECK constraint below only
-- guards against obviously malformed values; it does not pin the column
-- to today's specific version so future guideline revisions don't
-- require another migration just to accept a new version string.
--
-- Rollback: see 0034_profile_guidelines_accepted_version_rollback.sql in
-- supabase/rollbacks/. Drops the column and its constraint;
-- guidelines_accepted_at is untouched by both this migration and its
-- rollback.

begin;

alter table public.profiles
    add column guidelines_accepted_version text;

alter table public.profiles
    add constraint profiles_guidelines_accepted_version_format_check
    check (
        guidelines_accepted_version is null
        or guidelines_accepted_version ~ '^\d{4}-\d{2}-\d{2}$'
    );

commit;
