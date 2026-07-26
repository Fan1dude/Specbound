-- Rollback for: 0014_storage_visibility_fix
--
-- Drops both replacement policies and restores the original policy from
-- 0002_publish_draft_and_visibility.sql exactly as it was, including its
-- original name — reintroducing the privacy gap this migration fixed.
-- Only use this if 0014 itself needs to be undone; there is no reason to
-- prefer the original behavior otherwise.

begin;

drop policy "Public can read revision media for public builds" on storage.objects;
drop policy "Owners can read their revision media" on storage.objects;

create policy "Anyone can read files referenced by a published revision" on storage.objects
    for select using (
        bucket_id = 'project-images'
        and exists (
            select 1 from public.revision_media rm
            where rm.storage_path = storage.objects.name
        )
    );

commit;
