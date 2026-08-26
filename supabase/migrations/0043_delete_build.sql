-- Migration: 0043_delete_build
-- Milestone: none — Launch Readiness Audit Finding 02 (permanent build
-- deletion). Status: PROPOSED — not yet applied. Depends on 0000-0042
-- being applied first.
--
-- Scope, per explicit product decision: PUBLISHED-build deletion only.
-- A never-published draft (project_drafts with published_build_id null)
-- has no builds row for this function to operate on at all — deleting
-- one of those is a separate, deliberately out-of-scope follow-up (the
-- row is already owner-deletable today via project_drafts' existing RLS
-- DELETE policy from 0001; only its Storage cleanup story is unbuilt,
-- same unbuilt-for-a-different-reason gap restore_revision_to_draft()
-- already discloses for project_media). This migration does not touch
-- that case.
--
-- Purpose: delete_build(p_build_id) permanently removes a published
-- build and everything that exists only because that build does,
-- relying entirely on the FK ON DELETE behavior already established
-- across 0000-0024 — this migration adds no new FK, changes no existing
-- one, and adds no new column:
--
--   CASCADE (rows disappear with the build):
--     build_revisions -> revision_media (two-level cascade, both already
--     ON DELETE CASCADE since 0000/0002)
--     comments (0007), likes (0008), saved_builds (0009),
--     build_view_cooldowns (0010), notifications (0011)
--
--   SET NULL (the referencing row survives, silently unlinked):
--     project_drafts.published_build_id (0002) — this is the explicit
--     product decision this migration relies on: the owner's draft is
--     NEVER deleted by this function. It becomes an ordinary
--     unpublished, fully editable draft the moment the build is gone,
--     republishable at any time through the existing publish_draft()
--     path with no special-casing needed anywhere else in the schema.
--     profiles.featured_build_id (0024) — a profile that had this build
--     pinned falls through to its documented fallback chain, not an
--     error.
--
--   Deliberately, explicitly NOT touched — content_reports.target_id and
--   moderation_actions.target_id are plain uuids, not foreign keys, by
--   original design (0028_moderation.sql's own header: "A report
--   surviving its target's deletion is a legitimate, still-actionable
--   record, not an integrity error"). js/repositories/
--   moderationRepository.js's getReportTargetContext() already has
--   working, documented handling for a build that no longer resolves
--   (returns {available: false}) — zero application changes are needed
--   for this to render correctly. moderation_actions is a permanent
--   audit log by definition and must never be affected by its subject's
--   later removal.
--
-- Storage: SQL cannot call the Storage API (same limitation
-- restore_revision_to_draft() already discloses), so this function
-- cannot delete files itself. Instead it computes, inside the same
-- transaction as the delete (so the answer can never go stale between
-- computing it and the DELETE that follows), every Storage path this
-- build's published history ever referenced via revision_media, MINUS
-- any path still referenced by project_media — i.e. minus any image the
-- owner's now-surviving draft still needs for its own gallery, since
-- publish_draft() never copies files, it only ever references the
-- draft's own upload path directly. Returns exactly that array; the
-- caller removes those paths from Storage afterward, using its own
-- authenticated session. This is NOT atomic with the database delete —
-- disclosed explicitly, not implied otherwise: if the Storage removal
-- step fails or is interrupted after this function has already
-- committed, the result is orphaned Storage OBJECTS (files with no
-- referencing row), never an orphaned rows (a row referencing a deleted
-- file) — the same accepted-risk direction already established by
-- restore_revision_to_draft()'s own comment on this exact limitation.
-- The existing "Owners can delete their draft media files" storage.objects
-- policy (0001, replaced by 0002) already rejects deleting a path still
-- referenced by revision_media — meaning the database delete below MUST
-- run before the caller's Storage removal call, not after; attempting
-- Storage removal first would simply fail under that policy while these
-- rows still exist.
--
-- Security: owner-only, SECURITY DEFINER, matching this schema's
-- universal write-RPC convention exactly (publish_draft,
-- restore_revision_to_draft, delete_comment, set_build_like,
-- report_content, ...). No DELETE policy is added to public.builds —
-- deliberately: direct client deletes stay denied outright by RLS
-- (enabled, zero matching policy), same posture as every other
-- protected write in this schema. This function is the only path.
--
-- notifications(build_id) index: notifications had no index with
-- build_id as a leading column (0011) — every other FK'd table above
-- already does (build_revisions, comments via their own composite
-- indexes; likes/saved_builds via their unique(build_id, user_id);
-- build_view_cooldowns via its build_id-leading primary key). Added here
-- so the CASCADE delete this function triggers doesn't do an unindexed
-- scan of notifications for every deletion.
--
-- Touches: notifications (one new index). Adds delete_build(uuid). Does
-- not modify 0042 or any other existing migration/function/policy.
--
-- Rollback: see 0043_delete_build_rollback.sql in supabase/rollbacks/.
-- Drops delete_build(uuid) and the new notifications index. Cannot
-- undo any build already deleted through this function — that data loss
-- is real and permanent by design, the entire point of this migration.

begin;

create index notifications_build_id_idx
    on public.notifications (build_id);

create or replace function public.delete_build(
    p_build_id uuid
)
returns text[]
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_build public.builds;
    v_paths text[];
begin
    if auth.uid() is null then
        raise exception 'You must be signed in to delete a project.';
    end if;

    select * into v_build from public.builds where id = p_build_id;

    if v_build is null then
        raise exception 'Build not found.';
    end if;

    if v_build.user_id <> auth.uid() then
        raise exception 'Only the build owner can delete this project.';
    end if;

    -- Computed before the delete below, in the same transaction, so this
    -- can never observe a state the DELETE has already changed.
    select coalesce(array_agg(distinct rm.storage_path), '{}')
    into v_paths
    from public.revision_media rm
    join public.build_revisions br on br.id = rm.revision_id
    where br.build_id = p_build_id
      and not exists (
          select 1 from public.project_media pm
          where pm.storage_path = rm.storage_path
      );

    -- Cascades to build_revisions -> revision_media, comments, likes,
    -- saved_builds, build_view_cooldowns, notifications (all pre-existing
    -- ON DELETE CASCADE FKs — see this migration's header). Sets
    -- project_drafts.published_build_id and profiles.featured_build_id
    -- to null on any row that referenced this build (pre-existing ON
    -- DELETE SET NULL FKs). content_reports and moderation_actions are
    -- untouched, by design.
    delete from public.builds where id = p_build_id;

    return v_paths;
end;
$$;

revoke all on function public.delete_build(uuid) from public;
grant execute on function public.delete_build(uuid) to authenticated;

commit;
