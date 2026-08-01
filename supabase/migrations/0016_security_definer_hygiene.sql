-- Migration: 0016_security_definer_hygiene
-- Milestone: 8A (Security & Data Integrity)
-- Status: PROPOSED — not yet applied. Depends on 0001-0015 being applied
-- first.
--
-- Purpose: close the one gap found by a full re-audit of every custom
-- function's SECURITY DEFINER/INVOKER configuration during Milestone 8.
--
--   All 14 custom functions in this schema were reviewed against a
--   checklist (search_path pinned, revoked from PUBLIC where
--   appropriate, correct grant target, ownership validation) and 13 were
--   already correctly configured. The one gap: set_updated_at()
--   (0001_project_drafts_and_media.sql) is the only trigger function in
--   the schema without a defensive "revoke all ... from public" — its
--   two siblings added since, bump_likes_count()
--   (0008_project_likes.sql) and bump_follow_counts()
--   (0012_follows.sql), both have one, specifically because "any
--   function in the public schema is otherwise callable through
--   PostgREST by a role with execute privilege on it." Not currently
--   exploitable — a RETURNS TRIGGER function cannot actually be invoked
--   outside trigger context, Postgres itself blocks that — but it's a
--   real, fixable inconsistency with its own sibling functions' defense-
--   in-depth posture.
--
--   This is a bare REVOKE, not a CREATE OR REPLACE — 0001 itself is not
--   touched or rewritten, per this project's convention against editing
--   already-applied migrations. The function's behavior is completely
--   unchanged; only PUBLIC's (already-non-exploitable) direct-RPC
--   execute privilege is removed.
--
-- Touches: none — no table, column, or function body changes. Revokes a
-- privilege on public.set_updated_at() only.
--
-- Rollback: see 0016_security_definer_hygiene_rollback.sql in
-- supabase/rollbacks/.

begin;

revoke all on function public.set_updated_at() from public;

commit;
