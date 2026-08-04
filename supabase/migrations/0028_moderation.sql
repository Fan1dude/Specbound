-- Migration: 0028_moderation
-- Milestone: 22 (Community Foundation)
-- Status: PROPOSED — not yet applied. Depends on 0000-0027 being applied
-- first (needs profile_roles/is_platform_moderator()/is_platform_staff()
-- from 0027).
--
-- Full design: docs/milestones/MILESTONE_22_COMMUNITY_FOUNDATION_SPECIFICATION.md
-- §8, §0.2 decision 2.
--
-- Purpose: the moderator foundation's two remaining primitives —
-- reporting content, and an audit trail of moderator actions — plus the
-- role-grant/revoke RPCs deferred from 0027 (they need to log into
-- moderation_actions, which this file defines; see 0027's own header for
-- why the split).
--
--   content_reports and moderation_actions are deliberately two tables,
--   not one "moderation events" table with a type discriminator —
--   considered and rejected during the Milestone 22 final design review
--   (spec §0.2): a report has a reporter and, until resolved, no actor;
--   an action always has an actor and doesn't require a prior report
--   (a moderator can act on something nobody reported). Merging them
--   would mean more nullable, conditionally-meaningful columns on one
--   table, a partial index instead of a plain WHERE status = 'open' for
--   the moderation queue's most common query, and a strictly worse
--   design by every concrete measure the review checked — not merely a
--   stylistic preference.
--
--   content_reports.target_id is a plain uuid, not a foreign key — it
--   can point at builds, comments, or profiles, three different tables a
--   single FK column can't express without a partial/polymorphic
--   constraint this schema doesn't need yet. A report surviving its
--   target's deletion is a legitimate, still-actionable record, not an
--   integrity error.
--
--   unique (reporter_id, target_type, target_id): one open report per
--   (reporter, target) — re-reporting the same thing updates the
--   existing row via report_content()'s on-conflict clause rather than
--   piling up duplicates, the same minimal anti-spam shape as Milestone
--   19's per-user pending-submission cap.
--
--   No client INSERT policy on moderation_actions at all — every row is
--   written by the SECURITY DEFINER functions below, which are the only
--   path to the privileged action being logged in the first place. An
--   audit entry can't be forged or skipped by a caller who has moderator
--   access but bypasses the "proper" RPC, because there is no other RPC
--   that performs the action.
--
--   grant_profile_role()/revoke_profile_role(): 'moderator'/'staff'
--   require is_platform_staff(); 'community_builder'/'project_mentor'
--   require is_platform_moderator() (which already returns true for
--   staff too). Self-grant is explicitly rejected regardless of role —
--   a moderator/staff account can't promote itself. grant is
--   idempotent (on conflict do nothing) rather than erroring on an
--   already-held role.
--
-- Touches: none new beyond 0027 (two new tables, four new functions:
-- report_content(), resolve_report(), grant_profile_role(),
-- revoke_profile_role()).
--
-- Rollback: see 0028_moderation_rollback.sql in supabase/rollbacks/.

begin;

create table public.content_reports (
    id uuid primary key default gen_random_uuid(),
    reporter_id uuid not null references auth.users(id) on delete cascade,
    target_type text not null check (target_type in ('build', 'comment', 'profile')),
    target_id uuid not null,
    reason text not null check (char_length(trim(reason)) > 0),
    status text not null default 'open' check (status in ('open', 'reviewed', 'dismissed')),
    reviewed_by uuid references auth.users(id) on delete set null,
    reviewed_at timestamptz,
    created_at timestamptz not null default now(),

    unique (reporter_id, target_type, target_id)
);

create index content_reports_status_idx
    on public.content_reports (status)
    where status = 'open';

alter table public.content_reports enable row level security;

create policy "Users can view their own reports" on public.content_reports
    for select
    to authenticated
    using (auth.uid() = reporter_id);

create policy "Moderators can view all reports" on public.content_reports
    for select
    to authenticated
    using (public.is_platform_moderator(auth.uid()));

-- No insert/update/delete policy for any role — writes only through
-- report_content()/resolve_report() below.

create table public.moderation_actions (
    id uuid primary key default gen_random_uuid(),
    actor_id uuid not null references auth.users(id) on delete cascade,
    action_type text not null check (action_type in (
        'report_resolved', 'role_granted', 'role_revoked', 'content_removed'
    )),
    target_type text not null,
    target_id uuid not null,
    note text,
    created_at timestamptz not null default now()
);

create index moderation_actions_created_idx
    on public.moderation_actions (created_at desc);

alter table public.moderation_actions enable row level security;

create policy "Moderators can view the audit log" on public.moderation_actions
    for select
    to authenticated
    using (public.is_platform_moderator(auth.uid()));

-- No insert/update/delete policy for any role — every row is written by
-- the functions below, never directly.

create or replace function public.report_content(
    p_target_type text,
    p_target_id uuid,
    p_reason text
)
returns public.content_reports
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_report public.content_reports;
begin
    if auth.uid() is null then
        raise exception 'You must be signed in to report content.';
    end if;

    if trim(coalesce(p_reason, '')) = '' then
        raise exception 'A reason is required.';
    end if;

    insert into public.content_reports (reporter_id, target_type, target_id, reason)
    values (auth.uid(), p_target_type, p_target_id, trim(p_reason))
    on conflict (reporter_id, target_type, target_id)
        do update set reason = excluded.reason, status = 'open', reviewed_by = null, reviewed_at = null
    returning * into v_report;

    return v_report;
end;
$$;

revoke all on function public.report_content(text, uuid, text) from public;
grant execute on function public.report_content(text, uuid, text) to authenticated;

create or replace function public.resolve_report(
    p_report_id uuid,
    p_status text,
    p_note text default null
)
returns public.content_reports
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_report public.content_reports;
begin
    if not public.is_platform_moderator(auth.uid()) then
        raise exception 'Only moderators can resolve reports.';
    end if;

    if p_status not in ('reviewed', 'dismissed') then
        raise exception 'Invalid resolution status.';
    end if;

    update public.content_reports
        set status = p_status, reviewed_by = auth.uid(), reviewed_at = now()
        where id = p_report_id
        returning * into v_report;

    if v_report is null then
        raise exception 'Report not found.';
    end if;

    insert into public.moderation_actions (actor_id, action_type, target_type, target_id, note)
    values (auth.uid(), 'report_resolved', v_report.target_type, v_report.target_id, p_note);

    -- Notifies the reporter their report was actioned — build_id is
    -- intentionally omitted (defaults to null; see 0031's widening of
    -- create_notification() and notifications.build_id, since a report
    -- resolution isn't necessarily about a build at all).
    perform public.create_notification(v_report.reporter_id, auth.uid(), 'report_resolved');

    return v_report;
end;
$$;

revoke all on function public.resolve_report(uuid, text, text) from public;
grant execute on function public.resolve_report(uuid, text, text) to authenticated;

create or replace function public.grant_profile_role(
    p_user_id uuid,
    p_role text,
    p_note text default null
)
returns public.profile_roles
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_role public.profile_roles;
begin
    if auth.uid() is null then
        raise exception 'You must be signed in.';
    end if;

    if p_user_id = auth.uid() then
        raise exception 'You cannot grant yourself a role.';
    end if;

    if p_role in ('moderator', 'staff') then
        if not public.is_platform_staff(auth.uid()) then
            raise exception 'Only staff can grant the % role.', p_role;
        end if;
    elsif p_role in ('community_builder', 'project_mentor') then
        if not public.is_platform_moderator(auth.uid()) then
            raise exception 'Only moderators or staff can grant the % role.', p_role;
        end if;
    else
        raise exception 'Unknown role: %', p_role;
    end if;

    insert into public.profile_roles (user_id, role, granted_by, note)
    values (p_user_id, p_role, auth.uid(), p_note)
    on conflict (user_id, role) do nothing
    returning * into v_role;

    if v_role is null then
        select * into v_role from public.profile_roles where user_id = p_user_id and role = p_role;
    else
        insert into public.moderation_actions (actor_id, action_type, target_type, target_id, note)
        values (auth.uid(), 'role_granted', 'profile', p_user_id, p_note);

        perform public.create_notification(p_user_id, auth.uid(), 'role_awarded');
    end if;

    return v_role;
end;
$$;

revoke all on function public.grant_profile_role(uuid, text, text) from public;
grant execute on function public.grant_profile_role(uuid, text, text) to authenticated;

create or replace function public.revoke_profile_role(
    p_user_id uuid,
    p_role text,
    p_note text default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    if auth.uid() is null then
        raise exception 'You must be signed in.';
    end if;

    if p_role in ('moderator', 'staff') then
        if not public.is_platform_staff(auth.uid()) then
            raise exception 'Only staff can revoke the % role.', p_role;
        end if;
    elsif not public.is_platform_moderator(auth.uid()) then
        raise exception 'Only moderators or staff can revoke roles.';
    end if;

    delete from public.profile_roles where user_id = p_user_id and role = p_role;

    insert into public.moderation_actions (actor_id, action_type, target_type, target_id, note)
    values (auth.uid(), 'role_revoked', 'profile', p_user_id, p_note);
end;
$$;

revoke all on function public.revoke_profile_role(uuid, text, text) from public;
grant execute on function public.revoke_profile_role(uuid, text, text) to authenticated;

commit;
