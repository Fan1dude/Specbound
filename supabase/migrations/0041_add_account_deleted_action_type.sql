-- Migration: 0041_add_account_deleted_action_type
-- Milestone: 27A (Launch Readiness — engineering-controlled hardening)
-- Depends on 0000-0040 being applied first.
--
-- Purpose: schema support only — this migration does NOT implement
-- account deletion, and no deletion procedure runs against production as
-- part of it. It exists because the Milestone 27A specification's
-- account-deletion design (a manual, staff-executed support-request
-- procedure — self-service deletion is explicitly out of scope for v1)
-- calls for logging each deletion to moderation_actions, the same audit
-- table every other privileged moderation action already uses. Reading
-- moderation_actions.action_type's current CHECK constraint directly
-- (0028_moderation.sql) shows it allows exactly four values:
-- 'report_resolved', 'role_granted', 'role_revoked', 'content_removed'.
-- 'account_deleted' is not among them, so logging a deletion there would
-- fail outright the moment it's actually attempted. Adding it now, ahead
-- of need, means the audit infrastructure is ready whenever the first
-- real deletion request happens, rather than discovering this gap under
-- time pressure during an actual support case.
--
-- Same additive-widen shape already used twice in this schema for an
-- identical reason: 0037_follow_notifications.sql widened
-- notifications_type_check to add 'follow', and 0039_feedback_status_
-- workflow.sql widened it again to add 'feedback_reviewed'/
-- 'feedback_closed'. Existing rows and every other allowed value are
-- completely unaffected — a CHECK constraint widen only ever permits a
-- new value, it can never invalidate a row that already satisfied the
-- narrower constraint.
--
-- No RLS change: moderation_actions already has no client INSERT policy
-- at all (every row is written by a SECURITY DEFINER function, per
-- 0028's own header) — this migration doesn't touch that posture, and
-- the eventual account-deletion procedure will follow the same rule,
-- writing its audit row from a controlled server-side context, not a
-- direct client insert.
--
-- Full design: docs/milestones (Milestone 27A specification, published
-- 2026-08-14), account-deletion section.
--
-- Rollback: see 0041_add_account_deleted_action_type_rollback.sql in
-- supabase/rollbacks/ — deliberately does NOT narrow the constraint back.
-- Same reasoning 0037's and 0039's rollbacks already established: if any
-- real 'account_deleted' row exists by the time a rollback ever runs,
-- narrowing the CHECK would either fail outright or require destroying a
-- real audit record to succeed — both unacceptable. The rollback file
-- exists for completeness and convention only, matching every other
-- migration/rollback pair in this chain.

begin;

alter table public.moderation_actions
    drop constraint moderation_actions_action_type_check;

alter table public.moderation_actions
    add constraint moderation_actions_action_type_check
    check (action_type in (
        'report_resolved', 'role_granted', 'role_revoked', 'content_removed',
        'account_deleted'
    ));

commit;
