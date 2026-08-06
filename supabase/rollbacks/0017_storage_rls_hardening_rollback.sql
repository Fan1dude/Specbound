-- Rollback for: 0017_storage_rls_hardening
--
-- Drops the two new avatar policies and restores all four removed
-- policies exactly as they existed live (captured directly from a
-- pg_policies dump before this migration was applied) — reintroducing
-- the anonymous bucket-listing/enumeration/signing and anonymous-upload
-- gap this migration fixes. Only use this if 0017 itself needs to be
-- undone; there is no reason to prefer the original behavior otherwise.

begin;

drop policy "Owners can upload their own avatar files" on storage.objects;
drop policy "Owners can update their own avatar files" on storage.objects;

create policy "Anyone can view project images" on storage.objects
    for select
    to public
    using (bucket_id = 'project-images');

create policy "Authenticated users can upload project images" on storage.objects
    for insert
    to authenticated
    with check (bucket_id = 'project-images');

create policy "Enable insert for authenticated users only" on storage.objects
    for insert
    to anon
    with check (true);

create policy "Enable read access for all users" on storage.objects
    for select
    to public
    using (true);

commit;
