-- Rollback for 0000_baseline_pre_tracked_tables.
--
-- WARNING: this is not like any other rollback in this repo. Every other
-- migration's rollback undoes one bounded, additive change. This one
-- undoes the foundation nearly every other tracked migration builds on —
-- rolling it back on a project that has 0001+ applied on top of it will
-- break or orphan almost everything (project_drafts.published_build_id,
-- every comments/likes/saved_builds/notifications/follows row, the
-- entire component-submissions/aliases catalog's created_by references,
-- publish_draft() itself). Only run this to unwind an entire
-- from-empty-database apply during dry-run testing. Never on a project
-- with real user data.
--
-- Drop order: build_revisions before builds (FK dependency), auth.users
-- trigger/function before profiles (the trigger references profiles).
-- The four storage policies use IF EXISTS because 0017 may already have
-- dropped and replaced them by the time this rollback runs — that's the
-- expected, common case, not an error condition.

begin;

drop table if exists public.build_revisions;
drop table if exists public.builds;

drop trigger if exists on_auth_user_created on auth.users;
drop function if exists public.handle_new_user();
drop table if exists public.profiles;

drop policy if exists "Anyone can view project images" on storage.objects;
drop policy if exists "Authenticated users can upload project images" on storage.objects;
drop policy if exists "Enable insert for authenticated users only" on storage.objects;
drop policy if exists "Enable read access for all users" on storage.objects;
-- Also drop 0017's replacements, in case 0017 ran before this rollback —
-- otherwise re-applying 0000 forward would hit "policy already exists"
-- on these two the same way the original bug hit "column already exists".
drop policy if exists "Owners can upload their own avatar files" on storage.objects;
drop policy if exists "Owners can update their own avatar files" on storage.objects;

delete from storage.buckets where id = 'project-images';

commit;
