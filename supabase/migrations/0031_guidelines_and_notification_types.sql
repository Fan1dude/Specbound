-- Migration: 0031_guidelines_and_notification_types
-- Milestone: 22 (Community Foundation)
-- Status: PROPOSED — not yet applied. Depends on 0000-0030 being applied
-- first (0028's resolve_report()/grant_profile_role() already call
-- create_notification() with no build_id — this migration is what makes
-- that call valid; applying 0028 before this one leaves those two calls
-- referencing a not-yet-widened signature, so 0028 and this file must be
-- applied together in the same sitting, same as any other multi-file
-- Milestone 22 batch).
--
-- Full design: docs/milestones/MILESTONE_22_COMMUNITY_FOUNDATION_SPECIFICATION.md
-- §7, §11.
--
-- Purpose: two small, independent additions bundled in one file because
-- both are one-line-scale changes to already-existing objects, not new
-- tables:
--
--   1. profiles.guidelines_accepted_at — one nullable timestamp, set the
--      first time a builder accepts the Community Guidelines. Checked
--      lazily at the first moment a builder does something community-
--      facing (publishing a build, or posting a comment, whichever
--      happens first) — never wired into sign-up or the Milestone 21
--      Welcome dialog, per the "do not redesign onboarding" constraint.
--      Same "essential, minimal" bar Milestone 21 held
--      onboarding_welcomed_at to.
--
--   2. notifications.type widened to add 'role_awarded' and
--      'report_resolved' (0028's grant_profile_role()/resolve_report()
--      already call create_notification() with these) — reuses
--      create_notification() verbatim, no new notification
--      infrastructure. notifications.build_id is also relaxed from NOT
--      NULL to nullable, and create_notification()'s p_build_id
--      parameter gains a default of null, because a role grant or a
--      report resolution isn't necessarily about a build at all — unlike
--      every notification type that existed before this milestone,
--      which always was. Existing rows are entirely unaffected (their
--      build_id stays populated exactly as it already was); this only
--      permits new rows to omit it.
--
-- Touches: public.profiles (1 new nullable column), public.notifications
-- (widened CHECK, build_id now nullable), public.create_notification()
-- (CREATE OR REPLACE — same "modify via replace, not edit the original
-- migration" convention 0011 itself already used on 0007/0008/0009's
-- functions).
--
-- Rollback: see 0031_guidelines_and_notification_types_rollback.sql in
-- supabase/rollbacks/. Widening a CHECK and relaxing NOT NULL are both
-- safely reversible as long as no row created while this migration was
-- applied violates the narrower constraint being restored — true by
-- construction here, since only this migration's own new code paths
-- (0028's two RPCs) ever produce a null build_id or a
-- role_awarded/report_resolved row.

begin;

alter table public.profiles
    add column guidelines_accepted_at timestamptz;

alter table public.notifications
    alter column build_id drop not null;

-- notifications_type_check is Postgres's default auto-generated name for
-- an unnamed single-column inline CHECK ({table}_{column}_check) — 0011
-- never named it explicitly. Not verifiable against a live database from
-- this environment (anon-key only); smoke-test this exact statement
-- against \d public.notifications on a real dev project before applying,
-- same category of caveat as Milestone 20's builds!inner embedded-filter
-- note. If the name differs, the fix is a one-line edit to this
-- statement, not a redesign.
alter table public.notifications
    drop constraint notifications_type_check;

alter table public.notifications
    add constraint notifications_type_check
    check (type in ('comment', 'like', 'save', 'reply', 'role_awarded', 'report_resolved'));

create or replace function public.create_notification(
    p_recipient_id uuid,
    p_actor_id uuid,
    p_type text,
    p_build_id uuid default null,
    p_comment_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    if p_recipient_id = p_actor_id then
        return; -- never notify users about their own actions
    end if;

    insert into public.notifications (recipient_id, actor_id, type, build_id, comment_id)
    values (p_recipient_id, p_actor_id, p_type, p_build_id, p_comment_id);
end;
$$;

revoke all on function public.create_notification(uuid, uuid, text, uuid, uuid) from public;

commit;
