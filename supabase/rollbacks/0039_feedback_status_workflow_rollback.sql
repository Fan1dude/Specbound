-- Rollback for: 0039_feedback_status_workflow
--
-- *** WARNING: running this removes update_feedback_status() — after
-- *** this runs, NO client can move a feedback submission through
-- *** Open/Reviewed/Closed until 0039 is re-applied. Do not run this
-- *** without a specific, reviewed reason; it exists only for
-- *** completeness, matching every other migration/rollback pair in
-- *** this chain — reverting 0039 is not expected or recommended in
-- *** normal operation.
--
-- Deliberately narrow — drops ONLY the function. It does NOT:
--
--   - Drop feedback_submissions.status_updated_at. By the time a
--     rollback could ever run against a real database, real submissions
--     may already carry a real "last actioned" timestamp. Dropping a
--     populated column destroys that data outright and can never be
--     undone by re-applying 0039 forward (a fresh `add column` starts
--     null again, it doesn't recover what was dropped). The column is
--     left in place, permanently nullable, causing no harm to any
--     query or constraint on its own — the only thing that changes is
--     that nothing can set it going forward until re-applied.
--
--   - Narrow notifications_type_check back to exclude
--     'feedback_reviewed'/'feedback_closed'. If either type has already
--     been used by a real notification row, narrowing the CHECK would
--     either fail outright or require deleting real users' legitimate
--     notifications to succeed — both unacceptable once this has run in
--     production. Same reasoning 0037_follow_notifications_rollback.sql
--     already applied to 'follow'.
--
--   - Restore notifications.actor_id's NOT NULL constraint. If any
--     actorless (feedback) notification already exists, re-adding NOT
--     NULL fails outright against that row. Even before any such row
--     exists, restoring it serves no purpose once the function that
--     relied on the nullability is already gone — there is nothing left
--     that would ever insert an actorless row after this rollback runs,
--     so the constraint has no protective value to restore, only
--     destructive potential if timed wrong.
--
-- Net effect of running this: the schema stays exactly as 0039 left it
-- (extra nullable column, wider CHECK, nullable actor_id), all existing
-- feedback_submissions rows, their statuses, and their
-- status_updated_at values are untouched, all existing notifications
-- (actor-backed and actorless alike) remain intact and readable — the
-- only behavioral change is that update_feedback_status() no longer
-- exists, so status changes stop being possible until 0039 is
-- re-applied, at which point normal operation resumes immediately (the
-- forward migration's `create or replace function` recreates it
-- identically; nothing about a prior rollback leaves the re-applied
-- function in a different state).

begin;

drop function if exists public.update_feedback_status(uuid, text, text);

commit;
