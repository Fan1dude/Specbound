-- Rollback for 0029_feedback_submissions.

begin;

drop function if exists public.submit_feedback(text, text, text);
drop table if exists public.feedback_submissions;

commit;
