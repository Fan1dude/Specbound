-- Rollback for 0022_component_submissions.
-- Drops the two moderation functions, the anti-spam trigger's function
-- (the trigger itself drops automatically with the table, but a function
-- is an independent object and doesn't), and the submissions table. Only
-- use this if 0022 itself needs to be undone — dropping this table loses
-- the moderation audit trail (who submitted what, who approved/rejected
-- it, and when) for anything already resolved.

begin;

drop function if exists public.approve_component_submission(uuid, uuid);
drop function if exists public.reject_component_submission(uuid, text);
drop table if exists public.component_submissions;
drop function if exists public.enforce_component_submission_pending_cap();

commit;
