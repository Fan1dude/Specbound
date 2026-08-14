-- Rollback for: 0041_add_account_deleted_action_type
--
-- *** Deliberately does NOT narrow moderation_actions_action_type_check
-- *** back to exclude 'account_deleted'. If any real row already uses
-- *** that value by the time this ever runs, narrowing would either fail
-- *** outright or require deleting a real audit record to succeed —
-- *** both unacceptable once this has run in production. Identical
-- *** reasoning to 0037_follow_notifications_rollback.sql (for 'follow')
-- *** and 0039_feedback_status_workflow_rollback.sql (for
-- *** 'feedback_reviewed'/'feedback_closed').
--
-- Net effect of running this: nothing. This migration made no other
-- schema change and wrote no data — there is no forward effect to
-- reverse. The file exists for completeness and convention only,
-- matching every other migration in this chain having a paired rollback
-- file, even one that intentionally has no work to do.

begin;

-- No-op, on purpose — see header.

commit;
