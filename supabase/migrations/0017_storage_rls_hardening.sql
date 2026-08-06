-- Migration: 0017_storage_rls_hardening
-- Milestone: 9 (Production Cleanup & Launch)
-- Status: PROPOSED — not yet applied. Depends on 0001-0016 being applied
-- first.
--
-- Purpose: remove four storage.objects policies that predate migration
-- tracking and were never part of any tracked migration's intended access
-- model, then add the one legitimately-missing scoped policy they had been
-- accidentally covering for.
--
--   Confirmed live (via a direct pg_policies dump, and via empirical
--   testing against the running app using only the anon/publishable key —
--   no elevated access) that four policies exist beyond the ones this
--   schema's migrations ever created:
--
--     1. "Anyone can view project images" (SELECT, public, no scoping
--        beyond bucket_id) — granted unconditional read on every object in
--        the bucket to everyone.
--     2. "Authenticated users can upload project images" (INSERT,
--        authenticated, no path/ownership scoping) — let any signed-in
--        user write to any path, including another user's avatar or draft
--        folder.
--     3. "Enable insert for authenticated users only" (INSERT, role
--        **anon**, with_check = true, despite the name) — let anonymous,
--        unauthenticated visitors upload arbitrary files to arbitrary
--        paths. The single most severe finding.
--     4. "Enable read access for all users" (SELECT, public, qual = true,
--        not even bucket_id-scoped) — same class of gap as #1, broader
--        still.
--
--   All four match Supabase's own dashboard-generated default-policy
--   template names/shapes, strongly suggesting they were created via the
--   dashboard UI before this project's migrations existed and were never
--   revisited. None of them appear in 0001-0016.
--
--   Empirically, before this fix: an anonymous session (no auth, just the
--   publishable key already shipped to every client) could list the
--   entire bucket root, list into any other user's `projects/{draftId}/`
--   folder, and successfully call createSignedUrl() (then fetch 200) for
--   files having nothing to do with that session — independent of the
--   project-images bucket's public/private flag, since createSignedUrl()
--   and list() both evaluate storage.objects RLS the same way a normal
--   request does (see 0014's header comment for the same point made about
--   signing specifically).
--
--   Removing policies 2 and 3 closes an accidental gap of their own:
--   avatar upload (`avatars/{userId}/{size}.jpg`, via imageService.js's
--   uploadAvatar()) has never had a policy scoped to it in any tracked
--   migration — it only ever worked because of the two broad INSERT
--   policies being dropped here. Two new policies are added, scoped
--   exactly like every other owner-write policy in this schema
--   (storage.foldername(name) + auth.uid()), so avatar upload/re-upload
--   (upsert: true, hence both INSERT and UPDATE) keeps working for the
--   owner only.
--
--   Every other write/read path in the app (draft gallery images, public
--   build/revision reads, owner build/revision reads, avatar reads) is
--   already covered by 0001/0002/0014's policies, untouched by this
--   migration — verified by cross-referencing every storage.objects call
--   in js/services/imageService.js and js/repositories/mediaRepository.js
--   against the full current policy set before writing this file.
--
--   Known, deliberate, out-of-scope-for-this-migration side effect: a
--   small number of legacy builds/build_revisions rows have image_url
--   values that were never captured into revision_media (predating that
--   table). Under the tightened policies, those specific images become
--   unreadable, including for their own owner, until a separate follow-up
--   migration backfills revision_media for them. Not fixed here by design
--   — see docs/MILESTONE_9_STORAGE_RLS_MIGRATION.md §4 for the reasoning
--   (a one-time reviewable data backfill was judged safer than teaching
--   the RLS policies themselves to understand two different storage
--   conventions).
--
--   Deliberately NOT included: flipping the project-images bucket's
--   public/private flag. That is a separate action taken only after this
--   migration is applied and live-verified — see
--   docs/MILESTONE_9_STORAGE_RLS_MIGRATION.md for the full sequencing and
--   verification checklist.
--
-- Touches: storage.objects (four policies dropped, two added). No table,
-- column, or function changes.
--
-- Rollback: see 0017_storage_rls_hardening_rollback.sql in supabase/rollbacks/.
-- Restores all four original policies exactly (same name, same
-- role/qual/with_check as the live pg_policies dump they were removed
-- from) and drops the two new avatar policies — reintroducing the
-- anonymous-listing/upload gap this migration fixes. Only use this if
-- 0017 itself needs to be undone; there is no reason to prefer the
-- original behavior otherwise.

begin;

drop policy "Anyone can view project images" on storage.objects;
drop policy "Authenticated users can upload project images" on storage.objects;
drop policy "Enable insert for authenticated users only" on storage.objects;
drop policy "Enable read access for all users" on storage.objects;

create policy "Owners can upload their own avatar files" on storage.objects
    for insert
    with check (
        bucket_id = 'project-images'
        and (storage.foldername(name))[1] = 'avatars'
        and (storage.foldername(name))[2] = auth.uid()::text
    );

create policy "Owners can update their own avatar files" on storage.objects
    for update
    using (
        bucket_id = 'project-images'
        and (storage.foldername(name))[1] = 'avatars'
        and (storage.foldername(name))[2] = auth.uid()::text
    );

commit;
