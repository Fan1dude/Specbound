-- Migration: 0029_feedback_submissions
-- Milestone: 22 (Community Foundation)
-- Status: PROPOSED — not yet applied. Depends on 0000-0028 being applied
-- first.
--
-- Full design: docs/milestones/MILESTONE_22_COMMUNITY_FOUNDATION_SPECIFICATION.md
-- §9.
--
-- Purpose: a lightweight, category-tagged feedback entry point. No admin
-- triage UI is built this milestone — this table only needs to exist and
-- be writable by a signed-in user and readable by moderators; a future
-- status-workflow RPC can be added without a schema change (status is
-- already a plain CHECK-constrained column, ready to widen).
--
--   user_id is nullable with `on delete set null`, not `on delete
--   cascade` — deliberately different from every other user-owned row
--   in this schema. Feedback is product signal that should outlive the
--   account that submitted it; a builder deleting their account
--   shouldn't silently delete their bug reports too.
--
--   category is a plain CHECK-constrained column, not an enum type or a
--   lookup table — adding a fifth category later is a one-line
--   constraint change, the same low-ceremony extensibility already
--   established for notifications.type.
--
-- Touches: none.
--
-- Rollback: see 0029_feedback_submissions_rollback.sql in supabase/rollbacks/.

begin;

create table public.feedback_submissions (
    id uuid primary key default gen_random_uuid(),
    user_id uuid references auth.users(id) on delete set null,
    category text not null check (category in ('bug', 'confusing', 'suggestion', 'feature_request')),
    message text not null check (char_length(trim(message)) > 0 and char_length(message) <= 2000),
    page_url text,
    status text not null default 'open' check (status in ('open', 'reviewed', 'closed')),
    created_at timestamptz not null default now()
);

create index feedback_submissions_status_idx
    on public.feedback_submissions (status)
    where status = 'open';

alter table public.feedback_submissions enable row level security;

create policy "Users can view their own feedback" on public.feedback_submissions
    for select
    to authenticated
    using (auth.uid() = user_id);

create policy "Moderators can view all feedback" on public.feedback_submissions
    for select
    to authenticated
    using (public.is_platform_moderator(auth.uid()));

-- No insert policy — writes go through submit_feedback() below, which
-- pins user_id to the caller server-side rather than trusting a client-
-- supplied value.

create or replace function public.submit_feedback(
    p_category text,
    p_message text,
    p_page_url text default null
)
returns public.feedback_submissions
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_feedback public.feedback_submissions;
begin
    if auth.uid() is null then
        raise exception 'You must be signed in to send feedback.';
    end if;

    if trim(coalesce(p_message, '')) = '' then
        raise exception 'Feedback message cannot be empty.';
    end if;

    insert into public.feedback_submissions (user_id, category, message, page_url)
    values (auth.uid(), p_category, trim(p_message), p_page_url)
    returning * into v_feedback;

    return v_feedback;
end;
$$;

revoke all on function public.submit_feedback(text, text, text) from public;
grant execute on function public.submit_feedback(text, text, text) to authenticated;

commit;
