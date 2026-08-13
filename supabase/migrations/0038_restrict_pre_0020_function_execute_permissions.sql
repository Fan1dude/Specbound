-- Migration: 0038_restrict_pre_0020_function_execute_permissions
-- Milestone: 25 follow-up — security-hardening only, no user-facing
-- behavior change.
--
-- Depends on 0000-0037 being applied first.
--
-- Purpose: 0033_restrict_function_execute_permissions.sql closed the same
-- "anon has a stray EXECUTE grant Supabase's own default privileges put
-- there, despite the migration's `revoke all ... from public` clearly
-- intending authenticated-only" finding for every function introduced by
-- 0020-0032. It was scoped to that generation of functions specifically
-- ("every function 0033 touches") — it never re-examined the *earlier*
-- functions from 0002-0012, which predate it and were therefore never
-- covered. A grant audit performed while reviewing Milestone 25's
-- production release found the exact same pattern still present on
-- set_follow(uuid, boolean) (0012/0037) and confirmed, by direct
-- `pg_proc.proacl` inspection against the linked production project, that
-- nine sibling pre-0020 functions have the identical leftover:
--
--   create_comment(uuid, text)                        -- 0007
--   delete_comment(uuid)                               -- 0007
--   set_build_like(uuid, boolean)                       -- 0008
--   set_build_saved(uuid, boolean)                      -- 0009
--   mark_notification_read(uuid)                        -- 0011
--   mark_all_notifications_read()                       -- 0011
--   publish_draft(uuid, text, text)                     -- 0002/0004/0005/0006
--   restore_revision_to_draft(uuid, timestamptz)        -- 0005
--   set_build_visibility(uuid, text)                    -- 0006
--   set_follow(uuid, boolean)                           -- 0012/0037
--
-- Every one of these has an explicit `grant execute ... to authenticated`
-- still sitting in the migration that introduced it (0037_follow_
-- notifications.sql itself reissued set_follow()'s), confirming
-- authenticated-only was always the intent. None of them ever granted
-- `anon`. `CREATE OR REPLACE FUNCTION` on an already-existing function
-- preserves that function's current ACL rather than resetting it (see
-- 0035's own header for this exact point, made about publish_draft()/
-- restore_revision_to_draft()) — so 0037's redefinition of set_follow()
-- silently carried its pre-0033-fix, ambient-default-privilege anon grant
-- forward untouched, same as the other nine never being redefined at all
-- since their original migration.
--
-- None of this was ever exploitable: every one of these ten functions has
-- its own internal auth.uid()-null check (or, for the two SECURITY
-- DEFINER trigger-adjacent helpers among them — none are — an equivalent
-- guard) that rejects an unauthenticated caller before any read or write
-- happens. This migration is defense-in-depth, matching the intended
-- grant surface exactly, not a fix for a demonstrated access bypass.
--
-- Explicitly NOT touched, and why:
--   - get_activity_feed(text, timestamptz, uuid, integer) — anon+
--     authenticated is the correct, intentional grant (0013's own
--     explicit `to anon, authenticated`); it's a public read with a
--     SECURITY INVOKER, RLS-backed 'explore' scope that works identically
--     signed in or out.
--   - record_build_view(uuid, uuid) — anon+authenticated is intentional
--     (0010's own explicit `to anon, authenticated`); its second
--     parameter, p_anon_id, exists specifically to track anonymous
--     viewers.
--   - get_public_profile_roles(uuid) — anon+authenticated is intentional
--     (0032's own explicit grant, re-confirmed unchanged by 0033); public
--     role badges are meant to be visible to any visitor.
--   - create_notification(...), and every function 0033 already covers
--     (is_catalog_moderator, is_platform_moderator/staff,
--     report_content, resolve_report, grant_profile_role,
--     revoke_profile_role, submit_feedback, redeem_beta_invite,
--     sync_discord_identity, approve_component_submission,
--     reject_component_submission, the four trigger-only functions) —
--     already correctly authenticated-only (or client-inaccessible
--     entirely for create_notification()), confirmed unchanged by direct
--     live `proacl` inspection before writing this migration.
--   - resolve_report(uuid, text, text) — redefined again by 0036, which
--     reissued its own `revoke all ... from public; grant execute ... to
--     authenticated;` — confirmed already anon-free live, nothing to do.
--
-- No new default-privilege statement is added here: 0033 already added
-- both the GLOBAL and SCHEMA-scoped `alter default privileges ... revoke
-- execute ... from public`/`from anon, authenticated` statements, which
-- apply to every function CREATED after 0033 ran. This migration only
-- needs to clean up the ACLs of functions that already existed before
-- 0033 and were never individually redefined since — no future-function
-- protection gap exists to close again.
--
-- Rollback: see 0038_restrict_pre_0020_function_execute_permissions_
-- rollback.sql in supabase/rollbacks/ — restores the exact pre-0038
-- (anon-inclusive) grant on all ten functions. Do not run it without a
-- specific, reviewed reason; it exists for completeness only, matching
-- every other migration/rollback pair in this chain.

begin;

revoke execute on function
    public.create_comment(uuid, text),
    public.delete_comment(uuid),
    public.set_build_like(uuid, boolean),
    public.set_build_saved(uuid, boolean),
    public.mark_notification_read(uuid),
    public.mark_all_notifications_read(),
    public.publish_draft(uuid, text, text),
    public.restore_revision_to_draft(uuid, timestamptz),
    public.set_build_visibility(uuid, text),
    public.set_follow(uuid, boolean)
from anon;

commit;
