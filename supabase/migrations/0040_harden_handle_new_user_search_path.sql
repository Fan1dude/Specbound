-- Migration: 0040_harden_handle_new_user_search_path
-- Milestone: 27A (Launch Readiness — engineering-controlled hardening)
-- Depends on 0000-0039 being applied first.
--
-- Purpose: closes the one gap the Milestone 27 launch audit found across
-- all 30 SECURITY DEFINER functions in this schema — handle_new_user()
-- (the auth.users signup trigger) is the only one with no SET search_path
-- at all (confirmed via a direct pg_get_functiondef() read against
-- production: proconfig was null). Every other function in the schema
-- already sets search_path = public, pg_temp (or, for four Milestone
-- 19-era functions, the narrower "public" alone — a separate, lower-
-- severity inconsistency intentionally NOT touched by this migration, see
-- the audit's own finding). A SECURITY DEFINER function with no pinned
-- search_path is the exact pattern Supabase's Security Advisor flags as
-- "function search path mutable" — a caller who can create objects
-- earlier in the effective search path could in principle shadow an
-- unqualified reference this function makes.
--
-- A real discrepancy surfaced while preparing this migration, worth
-- recording plainly: 0000_baseline_pre_tracked_tables.sql's own
-- reconstruction of handle_new_user() (a two-column `insert into
-- public.profiles (id, username) values (new.id,
-- new.raw_user_meta_data->>'username')`, with `set search_path =
-- public`) does NOT match what is actually deployed in production today.
-- Production's real function — read directly via pg_get_functiondef()
-- against the linked project, not assumed — inserts five columns
-- (id, username, display_name, bio, avatar_url), defaults username AND
-- display_name via coalesce(raw_user_meta_data->>'username',
-- split_part(email, '@', 1)) rather than the baseline's un-defaulted
-- direct read, defaults bio/avatar_url to empty string, and carries NO
-- search_path clause at all. The baseline file was already known-
-- unverified against real production definitions (see its own header,
-- and docs/ROADMAP.md's backlog entry tracking that gap) — this is the
-- first concrete instance of that gap being found and closed. This
-- migration's job is to preserve production's REAL current behavior
-- while adding the missing search_path, not to reproduce the baseline
-- file's stale reconstruction — doing the latter would silently regress
-- live signup behavior (dropping display_name/bio/avatar_url defaulting
-- and the email-local-part username fallback), which is exactly the kind
-- of change this migration must not make.
--
-- The baseline migration file itself (0000_...) is NOT edited here —
-- it is already applied to production, and this project's convention is
-- to never edit an already-shipped migration, only ever add a new one
-- that corrects forward. A fresh install applying 0000 through this
-- migration ends up at the same real, correct function body production
-- already has; only a fresh install stopping exactly at 0039 would still
-- see the baseline's stale two-column version, same as it does today.
--
-- Ownership, the on_auth_user_created trigger wiring, and grants
-- (anon + authenticated currently hold EXECUTE, matching every other
-- function created by 0000's baseline reconstruction) are all left
-- exactly as they are — this migration touches only the function body's
-- SET search_path clause and, as an unavoidable consequence of using
-- `create or replace function`, restates the existing (unchanged) insert
-- logic verbatim.
--
-- Full design: docs/milestones (Milestone 27A specification, published
-- 2026-08-14).
--
-- Rollback: see 0040_harden_handle_new_user_search_path_rollback.sql in
-- supabase/rollbacks/ — restores the exact pre-migration function body
-- (production's real five-column version, minus the search_path clause),
-- not the baseline's older two-column stub. A pure function-body swap is
-- fully, safely reversible either direction — no data is ever touched by
-- either this migration or its rollback, since replacing a trigger
-- function never rewrites rows already inserted under the prior version.

begin;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    insert into public.profiles (
        id,
        username,
        display_name,
        bio,
        avatar_url
    )
    values (
        new.id,
        coalesce(new.raw_user_meta_data->>'username', split_part(new.email, '@', 1)),
        coalesce(new.raw_user_meta_data->>'username', split_part(new.email, '@', 1)),
        '',
        ''
    );

    return new;
end;
$$;

commit;
