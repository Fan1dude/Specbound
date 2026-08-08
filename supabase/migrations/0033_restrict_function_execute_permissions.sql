-- Migration: 0033_restrict_function_execute_permissions
-- Milestone: 22 (Community Foundation) — post-audit security hardening.
-- Status: the 17 explicit per-function REVOKE/GRANT statements below
-- (statement groups 2-4) were MANUALLY APPLIED to production via the
-- Supabase SQL Editor (verified successful) BEFORE this file was
-- committed — see the PR description's "What was found" and
-- "Production status" sections for the full audit trail. Those
-- statements secure the 17 existing functions in production today.
--
-- The GLOBAL default-privilege statement in group 1 below
-- (`alter default privileges for role postgres revoke execute on
-- functions from public;`, no `in schema`) is a correction added after
-- that manual production run, found and verified only in local testing
-- (see "Local verification" below) — it has NOT yet been applied to
-- production. Do not describe future-function protection as complete
-- in production until this file is deployed there.
--
-- Because the per-function statements were run manually, that action
-- did not create a production migration-history record for 0033. This
-- file exists so the tracked chain matches what's actually live (for
-- the 17-function part) and so a normal `supabase db push`/deploy can
-- apply the remaining global default-privilege statement and record
-- 0033 going forward — every statement below is idempotent (REVOKE/
-- GRANT on a privilege state that already matches is a no-op), so
-- re-running the whole file is safe.
-- Depends on 0000-0032 being applied first.
--
-- Purpose: closes a real, confirmed production finding — a read-only
-- SQL audit (pg_catalog/information_schema only, no writes) found that
-- every function introduced by 0020-0032 had effective EXECUTE access
-- for BOTH `anon` and `authenticated`, regardless of what each
-- migration's own GRANT/REVOKE statements declared. `REVOKE ... FROM
-- PUBLIC` (the pattern every one of those migrations used) only removes
-- the privilege the PUBLIC pseudo-role held — it does not remove a
-- privilege granted directly to `anon`/`authenticated` as their own
-- roles, which is what Supabase's own default-privilege configuration
-- for the public schema was doing on every new `postgres`-owned
-- function. See the accompanying rollback file and PR description for
-- the full function-by-function analysis (which grants were required by
-- RLS policies, which were trigger-only and therefore never directly
-- reachable, and which — `create_notification()` specifically — had no
-- internal authorization check of its own and depended entirely on the
-- grant being correct).
--
-- The five statement groups below, in order:
--   1. Two separate `alter default privileges` statements — this is the
--      part corrected after the manual production run (see "Local
--      verification" below):
--      a. `alter default privileges for role postgres revoke execute on
--         functions from public;` — GLOBAL scope (no `in schema`).
--         PostgreSQL grants EXECUTE to the PUBLIC pseudo-role on every
--         new function by default; that hardcoded global default is
--         only overridden by a matching GLOBAL pg_default_acl entry, not
--         a schema-scoped one. Without this statement, a schema-scoped
--         revoke alone leaves that global PUBLIC grant in effect for
--         every future function, and PUBLIC access always extends to
--         every role, including anon/authenticated.
--      b. `alter default privileges for role postgres in schema public
--         revoke execute on functions from anon, authenticated;` —
--         SCHEMA-scoped, removes Supabase's own default-privilege
--         configuration that directly grants anon/authenticated
--         (independent of PUBLIC) on every new postgres-owned function
--         in the public schema.
--      Together, these stop this from recurring for every FUTURE
--      postgres-owned function created in this schema. Neither touches
--      any already-existing function's own ACL; that's the next three
--      groups' job.
--   2. Explicit REVOKE on every function this audit found broader than
--      intended, from public/anon/authenticated.
--   3. Explicit GRANT to `authenticated` only, for every RPC/RLS-helper
--      genuinely meant for signed-in users (including
--      is_catalog_moderator(uuid) and is_platform_moderator(uuid),
--      which RLS policies on components/component_submissions/
--      content_reports/moderation_actions/feedback_submissions/
--      profile_roles depend on `authenticated` being able to execute —
--      revoking authenticated here would turn ordinary reads on those
--      tables into permission-denied errors for every signed-in user,
--      not just a hardening). Every function in this list already had
--      its own internal auth.uid()/role check as defense in depth;
--      trigger-only functions (sync_component_legacy_fields,
--      set_component_alias_technology_and_field,
--      enforce_component_submission_pending_cap, validate_featured_build)
--      and create_notification() are deliberately NOT in this list —
--      none of them are meant to be callable by a client role at all.
--   4. get_public_profile_roles(uuid) is the one intentionally-public,
--      column-restricted RPC (0032) — explicitly re-confirmed for both
--      anon and authenticated, unaffected by everything above it.
--
-- service_role and the function owner are untouched by this migration —
-- neither is a client-facing PostgREST role, and this migration doesn't
-- attempt to manage that surface (see the PR description for why that's
-- explicitly out of scope here, not an oversight).
--
-- Rollback: see 0033_restrict_function_execute_permissions_rollback.sql
-- in supabase/rollbacks/ — restores the exact pre-0033 (insecure) grant
-- state. Do not run it without a specific reason; it exists for
-- completeness, matching every other migration in this chain, not
-- because reverting this one is expected.
--
-- Local verification (confirmed by direct inspection against the local
-- disposable Supabase/Docker stack, not theoretical): before statement
-- 1a existed, `pg_default_acl` had a SCHEMA-scoped row for
-- (role=postgres, schema=public, objtype=function) with no PUBLIC entry,
-- but NO global row — so PostgreSQL's hardcoded global default (PUBLIC
-- EXECUTE on new functions) still applied, confirmed by creating a
-- throwaway function and inspecting its resulting proacl (it included
-- `=X/postgres`, i.e. PUBLIC). `anon`/`authenticated` had no direct ACL
-- entries at all — their access came solely through PUBLIC membership.
-- No event trigger touches public-schema function grants (checked
-- pg_event_trigger directly). Adding statement 1a (the global-scope
-- revoke) closed this completely: the same throwaway-function test
-- afterward showed no PUBLIC entry and both anon/authenticated denied.
-- See migration_0033_function_execute_permissions.test.sql test 7 for
-- the full regression coverage of both scopes.

begin;

-- Remove PostgreSQL's global PUBLIC EXECUTE default for future
-- postgres-owned functions.
alter default privileges for role postgres
    revoke execute on functions from public;

-- Remove Supabase's schema-specific direct client-role grants.
alter default privileges for role postgres in schema public
    revoke execute on functions from anon, authenticated;

-- Remove unintended client access from every affected function.
revoke execute on function
    public.is_catalog_moderator(uuid),
    public.sync_component_legacy_fields(),
    public.set_component_alias_technology_and_field(),
    public.enforce_component_submission_pending_cap(),
    public.approve_component_submission(uuid, uuid),
    public.reject_component_submission(uuid, text),
    public.validate_featured_build(),
    public.is_platform_moderator(uuid),
    public.is_platform_staff(uuid),
    public.report_content(text, uuid, text),
    public.resolve_report(uuid, text, text),
    public.grant_profile_role(uuid, text, text),
    public.revoke_profile_role(uuid, text, text),
    public.submit_feedback(text, text, text),
    public.redeem_beta_invite(text),
    public.create_notification(uuid, uuid, text, uuid, uuid),
    public.sync_discord_identity()
from public, anon, authenticated;

-- RPCs and RLS helpers intended for signed-in users.
grant execute on function
    public.is_catalog_moderator(uuid),
    public.approve_component_submission(uuid, uuid),
    public.reject_component_submission(uuid, text),
    public.is_platform_moderator(uuid),
    public.is_platform_staff(uuid),
    public.report_content(text, uuid, text),
    public.resolve_report(uuid, text, text),
    public.grant_profile_role(uuid, text, text),
    public.revoke_profile_role(uuid, text, text),
    public.submit_feedback(text, text, text),
    public.redeem_beta_invite(text),
    public.sync_discord_identity()
to authenticated;

-- Intentionally public, restricted-output RPC.
revoke execute on function public.get_public_profile_roles(uuid)
    from public;

grant execute on function public.get_public_profile_roles(uuid)
    to anon, authenticated;

commit;
