-- Migration: 0047_account_deletion_jobs
-- Milestone: none — Launch Readiness self-service account deletion.
-- Status: PROPOSED — not yet applied. Depends on 0000-0046 being
-- applied first.
--
-- Purpose: a durable orchestration record for one self-service account
-- deletion, spanning three genuinely separate, non-transactional
-- systems (Postgres, Supabase Auth admin, Storage — see
-- 0048_self_delete_account.sql and the delete-account Edge Function for
-- the full sequence). This table is what makes that sequence idempotent
-- and recoverable after a partial failure, replacing
-- docs/OPERATIONS.md §10.14's manual "how to tell what already
-- happened" inference procedure with an explicit, stored state instead.
--
--   former_user_id is a PLAIN uuid — deliberately NOT a foreign key to
--   auth.users, and specifically not one with ON DELETE CASCADE. This
--   row's entire purpose is to survive the very deletion of auth.users
--   it's tracking; a cascading FK would delete it at exactly the moment
--   it becomes most necessary (to know Auth deletion succeeded and to
--   drive any still-pending Storage retry). The same "plain uuid, not a
--   FK, so the record survives its subject's removal" pattern
--   content_reports.target_id and moderation_actions.target_id already
--   use (0028_moderation.sql's own header: "A report surviving its
--   target's deletion is a legitimate, still-actionable record, not an
--   integrity error").
--
--   state is a small, explicit checkpoint enum matching the exact
--   sequence in 0048/the Edge Function:
--     'db_prepared'    — the SECURITY DEFINER RPC committed: builds/
--                         profile/build_revisions cleaned up, Storage
--                         paths captured, moderation_actions preserved
--                         per the anonymization rules already in place.
--                         auth.users still exists at this point.
--     'auth_deleted'   — supabase.auth.admin.deleteUser() succeeded.
--                         auth.users, and everything it cascades/
--                         anonymizes, is gone.
--     'storage_cleaned'— best-effort Storage removal finished (whether
--                         or not every path succeeded — see
--                         storage_cleanup_attempts/last_error_code for
--                         partial-failure detail). This is the terminal
--                         success state.
--     'failed'         — a step could not complete and is not expected
--                         to succeed on simple retry; requires manual
--                         (adult-operator/support) attention.
--
--   Explicitly NOT stored, per instruction: no password, no session
--   token, no more personal information than the bare former user id
--   already implies. storage_paths stores object keys only (the same
--   kind of value 0043_delete_build.sql's own return value already
--   carries) — not file contents, not any other user-supplied data.
--
--   RLS enabled, zero policies for any role — this is internal
--   orchestration state, never exposed to any client, including the
--   (former) user themselves. The creating RPC (0048, user-authenticated,
--   SECURITY DEFINER) and the Edge Function's service-role connection
--   (which bypasses RLS entirely, by Supabase's own default posture for
--   that role) are the only writers.
--
-- Touches: none (one new table only).
--
-- Rollback: see 0047_account_deletion_jobs_rollback.sql in
-- supabase/rollbacks/.

begin;

create table public.account_deletion_jobs (
    id uuid primary key default gen_random_uuid(),
    former_user_id uuid not null,
    state text not null default 'db_prepared'
        check (state in ('db_prepared', 'auth_deleted', 'storage_cleaned', 'failed')),
    storage_paths text[] not null default '{}',
    storage_cleanup_attempts integer not null default 0
        check (storage_cleanup_attempts >= 0),
    last_error_code text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    completed_at timestamptz
);

-- One in-flight/most-recent job per former user id is all orchestration
-- needs to look up; a unique index (not a primary key, since former_user_id
-- itself carries no referential integrity guarantee) keeps lookups O(1)
-- without over-constraining — a genuinely repeated deletion attempt after
-- a 'failed' terminal state can still resolve to the same row via
-- on-conflict logic in 0048, rather than accumulating duplicate rows.
create unique index account_deletion_jobs_former_user_id_idx
    on public.account_deletion_jobs (former_user_id);

alter table public.account_deletion_jobs enable row level security;

-- No SELECT/INSERT/UPDATE/DELETE policy for anyone — see this
-- migration's header. Every read/write goes through the RPC (0048) or
-- the Edge Function's service-role connection.

-- Reuses the shared public.set_updated_at() trigger function already
-- defined in 0001_project_drafts_and_media.sql — no new trigger function
-- needed.
create trigger account_deletion_jobs_set_updated_at
    before update on public.account_deletion_jobs
    for each row
    execute function public.set_updated_at();

commit;
