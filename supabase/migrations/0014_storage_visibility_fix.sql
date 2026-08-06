-- Migration: 0014_storage_visibility_fix
-- Milestone: 8A (Security & Data Integrity)
-- Status: PROPOSED — not yet applied. Depends on 0001-0013 being applied
-- first.
--
-- Purpose: close a real privacy gap found during the Milestone 8 audit.
--
--   The original policy from 0002_publish_draft_and_visibility.sql,
--   "Anyone can read files referenced by a published revision", only
--   checked that a revision_media row referenced the requested storage
--   path — it never checked the parent build's visibility. Every
--   *database-row* read path (builds, build_revisions, revision_media
--   SELECT policies) correctly gates on visibility = 'public' or
--   user_id = auth.uid(), but this one storage.objects policy did not.
--   Practical consequence: an owner who unpublishes a project via
--   set_build_visibility() correctly hides the build/revision rows from
--   everyone else, but the underlying image FILES remained signable and
--   fetchable by anyone who could still reach this policy — including via
--   a brand-new signed-URL request made after unpublishing.
--
--   Fixed as two separately-named policies (public direct-request per
--   Milestone 8A review, rather than one policy combining both
--   conditions with OR) so each is individually readable and droppable,
--   matching this schema's existing per-operation storage policy style
--   (see 0001's four separate CRUD policies for draft media):
--     1. "Public can read revision media for public builds" —
--        visibility = 'public' only.
--     2. "Owners can read their revision media" — user_id = auth.uid()
--        only, so an owner can still preview their own unpublished
--        project's images (e.g. in the editor or their own private build
--        page), matching the "public or owner" rule used everywhere else.
--   Both require bucket_id = 'project-images' and the same
--   revision_media -> build_revisions -> builds join to match
--   storage.objects.name.
--
--   Known, disclosed limitation (not fixed by this migration, cannot be
--   fixed retroactively by any RLS change): Supabase signed URLs embed a
--   time-limited bypass at GENERATION time — RLS is evaluated when
--   createSignedUrl() is called, not on every subsequent fetch through an
--   already-issued URL. This fix stops any NEW signed URL from being
--   generated for a now-private build's images once applied; it cannot
--   invalidate a URL issued before the fix, which simply expires on its
--   own (signed URLs in this app are issued for 7 days — see
--   mediaRepository.js's SIGNED_URL_EXPIRY_SECONDS). Same category of
--   accepted limitation as the orphaned-Storage-files gap disclosed in
--   0005_revision_history_and_restore.sql.
--
-- Touches: storage.objects (one policy replaced by two). No table,
-- column, or function changes.
--
-- Rollback: see 0014_storage_visibility_fix_rollback.sql in supabase/rollbacks/.
-- Drops both replacement policies and restores the original policy
-- exactly as it was in 0002, including its original name.

begin;

drop policy "Anyone can read files referenced by a published revision" on storage.objects;

create policy "Public can read revision media for public builds" on storage.objects
    for select using (
        bucket_id = 'project-images'
        and exists (
            select 1 from public.revision_media rm
            join public.build_revisions br on br.id = rm.revision_id
            join public.builds b on b.id = br.build_id
            where rm.storage_path = storage.objects.name
              and b.visibility = 'public'
        )
    );

create policy "Owners can read their revision media" on storage.objects
    for select using (
        bucket_id = 'project-images'
        and exists (
            select 1 from public.revision_media rm
            join public.build_revisions br on br.id = rm.revision_id
            join public.builds b on b.id = br.build_id
            where rm.storage_path = storage.objects.name
              and b.user_id = auth.uid()
        )
    );

commit;
