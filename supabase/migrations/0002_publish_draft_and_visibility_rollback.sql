-- Rollback for: 0002_publish_draft_and_visibility
--
-- IMPORTANT — read before running: 0002 dropped every pre-existing RLS
-- policy on public.builds and public.build_revisions (their exact names
-- were unknown from this environment, so it dropped-and-recreated rather
-- than targeting specific policies). This rollback cannot restore those
-- original policies, because their definitions were never captured
-- anywhere in this repo. After running this rollback, builds and
-- build_revisions will have RLS enabled with NO policies at all, which
-- means deny-all for every role, including reads, until new policies are
-- added by hand. Do not run this rollback against a database with live
-- traffic depending on those tables reading correctly without first
-- writing the replacement policies you actually want.

begin;

-- 6. publish_draft() --------------------------------------------------
drop function if exists public.publish_draft(uuid, text, text);

-- 5b/5a. Storage policies -----------------------------------------------
drop policy if exists "Anyone can read files referenced by a published revision" on storage.objects;
drop policy if exists "Anyone can read avatar files" on storage.objects;

drop policy if exists "Owners can delete their draft media files" on storage.objects;

-- Restored verbatim from 0001_project_drafts_and_media.sql.
create policy "Owners can delete their draft media files" on storage.objects
    for delete using (
        bucket_id = 'project-images'
        and (storage.foldername(name))[1] = 'projects'
        and exists (
            select 1 from public.project_drafts d
            where d.id::text = (storage.foldername(name))[2]
            and d.user_id = auth.uid()
        )
    );

-- 4. RLS policies added by 0002 on builds/build_revisions/revision_media --
-- (revision_media's policy is dropped along with the table itself below;
-- these two are dropped explicitly since builds/build_revisions survive.)
drop policy if exists "Public builds are readable by everyone, private builds by their owner" on public.builds;
drop policy if exists "Revisions are readable when their build is readable" on public.build_revisions;

-- 3. revision_media ------------------------------------------------------
drop table if exists public.revision_media;

-- 2. builds.visibility ----------------------------------------------------
alter table public.builds drop column if exists visibility;

-- 1. project_drafts.published_build_id -------------------------------------
alter table public.project_drafts drop column if exists published_build_id;

commit;
