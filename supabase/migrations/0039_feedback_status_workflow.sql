-- Migration: 0039_feedback_status_workflow
-- Milestone: 26 (Feedback Review)
-- Depends on 0000-0038 being applied first.
--
-- Purpose: closes the gap Milestone 26's own planning audit confirmed —
-- feedback_submissions (0029_feedback_submissions.sql, Milestone 22) has
-- carried a `status` column with three values since it shipped, but
-- nothing has ever written anything past the `'open'` default: no RPC,
-- no UPDATE RLS policy. This migration adds the one function that can
-- move a submission through Open -> Reviewed -> Closed, plus the small
-- amount of supporting schema that decision requires.
--
-- Full design: docs/milestones/MILESTONE_26_FEEDBACK_REVIEW_SPECIFICATION.md
--
-- Four changes:
--
--   1. feedback_submissions gains a nullable `status_updated_at
--      timestamptz` column. Existing/new Open rows keep it null (a
--      submission that has never been actioned has no "last actioned"
--      time to report); update_feedback_status() below is the only
--      thing that ever sets it, and only on a successful transition.
--      This is what lets the reviewer queue's History view sort by "most
--      recently actioned" instead of falling back to created_at (which
--      would put a submission filed months ago but reviewed five minutes
--      ago at the bottom of the list — the wrong order for a queue).
--
--   2. notifications_type_check widened to add 'feedback_reviewed' and
--      'feedback_closed' — two distinct types, not one generic type with
--      a live join back to feedback_submissions.status. A live join
--      would make an OLD notification's rendered text silently change
--      later (a "your feedback was reviewed" notification would start
--      rendering as "closed" once that same submission is later closed),
--      misrepresenting a past, discrete event as a different one. Every
--      other event type in this table (comment/like/save/follow/...) is
--      already a frozen descriptor of what happened, not a live pointer
--      — this follows that same convention rather than the "render from
--      a live join" behavior create_notification()'s own header
--      describes for username/build-title cosmetics, which is a
--      different (purely cosmetic, non-event-changing) kind of "live."
--
--   3. notifications.actor_id becomes nullable (`drop not null`) — the
--      reviewer-identity privacy fix. Every existing notification type
--      sets actor_id to a real user (the commenter, the liker, the
--      follower, the resolving moderator for report_resolved) and
--      that's unchanged here. But report_resolved's own precedent
--      (fixed, generic text, never rendering the actor) turned out on
--      inspection to be privacy-safe only in the *rendered UI* — the
--      raw notifications row (returned verbatim by
--      getRecentNotifications()/getNotificationsPage()'s `select("*")`)
--      still carries the real moderator's uuid in actor_id, and
--      enrichNotifications() separately fetches and attaches that
--      moderator's public profile — both inspectable over the network
--      regardless of what notificationFormat.js chooses to render. For
--      feedback status-change notifications specifically, the product
--      requirement is stricter: the submitter must not be able to learn
--      *which* moderator/staff member reviewed or closed their
--      submission through ANY client-visible channel, not just the
--      rendered text. The only way to guarantee that is for the row
--      itself to carry no reviewer identity at all — actor_id = null.
--
--      This is safe to do narrowly:
--        - A null foreign-key value never needs to satisfy the
--          `references auth.users(id)` constraint (Postgres FK checks
--          only apply to non-null values) — dropping NOT NULL is the
--          only change needed, no FK redefinition.
--        - create_notification()'s existing self-notification guard
--          (`if p_recipient_id = p_actor_id then return;`) evaluates to
--          NULL (not true) when p_actor_id is null, so it's correctly a
--          no-op for an actorless call — there's no "self" to guard
--          against when there's no actor, and a moderator reviewing
--          their own submitted feedback (an edge case, but possible)
--          correctly still gets notified.
--        - Every existing call site (create_comment, set_build_like,
--          set_build_saved, resolve_report, set_follow) always passes a
--          real, non-null actor_id and is completely unaffected —
--          dropping NOT NULL only permits a new possibility, it doesn't
--          require it anywhere it wasn't already guaranteed.
--        - enrichNotifications() (js/repositories/notificationRepository.js)
--          is updated in this same milestone to filter out null actor
--          ids before batching the profile lookup (`.filter(Boolean)`,
--          the same guard already used there for build_id), so an
--          actorless notification never sends `id=in.(...,null,...)` to
--          PostgREST and never crashes.
--
--   4. update_feedback_status(p_feedback_id, p_expected_status,
--      p_new_status) — the only function that can change
--      feedback_submissions.status. SECURITY DEFINER, re-checks
--      is_platform_moderator(auth.uid()) itself (the client-side page
--      gate is UX only), validates the requested transition against an
--      explicit three-entry allow-list (open->reviewed, open->closed,
--      reviewed->closed — Closed is terminal, no no-op transition is
--      ever in the list), and claims the row atomically by matching
--      `status = p_expected_status` in the same UPDATE that performs the
--      change — same concurrency technique as resolve_report()'s guard
--      (migration 0036), generalized with an explicit expected-status
--      parameter instead of a hardcoded 'open' since feedback's
--      transition graph has a second valid source status (reviewed)
--      that a report's single-hop graph never had. status_updated_at is
--      set to now() only inside that same atomic UPDATE, so it can never
--      be set by a failed/stale/unauthorized/invalid call. On success,
--      exactly one notification is created (skipped entirely when
--      user_id is null — a deleted submitter's row updates silently),
--      with actor_id passed as NULL per point 3 above.
--
-- No UPDATE RLS policy is added to feedback_submissions — it keeps its
-- existing "zero direct-write policies, every write goes through a
-- SECURITY DEFINER function" posture (submit_feedback() for inserts,
-- this function for status). Existing RLS (self-read, moderator-read)
-- is untouched.
--
-- Rollback: see 0039_feedback_status_workflow_rollback.sql in
-- supabase/rollbacks/ — deliberately narrow. It drops ONLY the function,
-- so no future status change is possible after rolling back. It does
-- NOT drop status_updated_at, does NOT narrow notifications_type_check,
-- and does NOT restore actor_id's NOT NULL constraint — see that file's
-- own header for the full reasoning (each of those three reversals
-- risks destroying or breaking real production data once this has run
-- live, the same asymmetric-rollback shape already established by
-- 0037_follow_notifications_rollback.sql, extended here to cover a
-- populated column and a loosened constraint in addition to a CHECK).

begin;

-- IF NOT EXISTS is required here, not defensive habit: this migration's
-- own rollback (see supabase/rollbacks/0039_feedback_status_workflow_
-- rollback.sql) deliberately leaves this column in place. Reapplying
-- this migration forward after that rollback — the exact sequence this
-- migration's own live rollback rehearsal exercises — must succeed, not
-- fail with "column already exists".
alter table public.feedback_submissions
    add column if not exists status_updated_at timestamptz;

alter table public.notifications
    drop constraint notifications_type_check;

alter table public.notifications
    add constraint notifications_type_check
    check (type in (
        'comment', 'like', 'save', 'reply', 'role_awarded',
        'report_resolved', 'follow', 'feedback_reviewed', 'feedback_closed'
    ));

alter table public.notifications
    alter column actor_id drop not null;

create or replace function public.update_feedback_status(
    p_feedback_id uuid,
    p_expected_status text,
    p_new_status text
)
returns public.feedback_submissions
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_row public.feedback_submissions;
    v_notification_type text;
begin
    if not public.is_platform_moderator(auth.uid()) then
        raise exception 'Only moderators or staff can update feedback status.';
    end if;

    -- The full transition graph as an explicit allow-list — this is what
    -- makes Reviewed -> Open, Closed -> anything, and every no-op
    -- (open->open, reviewed->reviewed, closed->closed) impossible in one
    -- place, rather than several independent range checks that could
    -- drift out of sync with each other. Closed never appears as a
    -- source here, which is what makes it terminal.
    if (p_expected_status, p_new_status) not in (
        ('open', 'reviewed'),
        ('open', 'closed'),
        ('reviewed', 'closed')
    ) then
        raise exception 'Invalid status transition.';
    end if;

    -- The atomic claim: matching on status = p_expected_status in the
    -- same statement that performs the UPDATE is the concurrency
    -- boundary itself, not a separate pre-check. Under READ COMMITTED
    -- (the default, unchanged), a second concurrent call against the
    -- same row either blocks on the row lock and then re-evaluates this
    -- predicate against the now-updated row (no longer matches), or
    -- simply arrives after the first commit and finds the same mismatch
    -- — either way it can never return a row here, so it can never
    -- silently overwrite the first accepted transition.
    update public.feedback_submissions
        set status = p_new_status, status_updated_at = now()
        where id = p_feedback_id
          and status = p_expected_status
        returning * into v_row;

    if v_row is null then
        if exists (select 1 from public.feedback_submissions where id = p_feedback_id) then
            raise exception 'This feedback was already updated. Refresh to see its current status.';
        else
            raise exception 'Feedback submission not found.';
        end if;
    end if;

    if v_row.user_id is not null then
        v_notification_type := case p_new_status
            when 'reviewed' then 'feedback_reviewed'
            else 'feedback_closed'
        end;

        -- actor_id is deliberately NULL, not auth.uid() — see this
        -- migration's header, point 3. This is what makes the reviewer's
        -- identity genuinely absent from the row, not merely unrendered.
        perform public.create_notification(v_row.user_id, null, v_notification_type);
    end if;

    return v_row;
end;
$$;

revoke all on function public.update_feedback_status(uuid, text, text) from public, anon;
grant execute on function public.update_feedback_status(uuid, text, text) to authenticated;

commit;
