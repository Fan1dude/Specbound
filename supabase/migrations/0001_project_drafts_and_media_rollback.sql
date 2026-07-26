-- Rollback for 0001_project_drafts_and_media.sql
-- Safe as long as no meaningful data has been written to these tables yet.
-- Drops the cover_media_id FK first to break the circular reference before
-- dropping project_media, so drop order doesn't matter otherwise.

begin;

drop policy if exists "Owners can select their draft media files" on storage.objects;
drop policy if exists "Owners can insert their draft media files" on storage.objects;
drop policy if exists "Owners can update their draft media files" on storage.objects;
drop policy if exists "Owners can delete their draft media files" on storage.objects;

alter table public.project_drafts drop column if exists cover_media_id;

drop table if exists public.project_media;
drop table if exists public.project_drafts;

-- The trigger on project_drafts is dropped automatically with the table.
-- The function itself is a separate object — only drop it if nothing else
-- has started using it since this migration was applied.
drop function if exists public.set_updated_at();

commit;
