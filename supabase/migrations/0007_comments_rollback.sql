-- Rollback for: 0007_comments
--
-- Drops both functions and the table entirely, including every comment
-- ever posted (soft-deleted or not) — there's no separate data-preserving
-- option since the table itself is new in this migration.

begin;

drop function if exists public.create_comment(uuid, text);
drop function if exists public.delete_comment(uuid);
drop table if exists public.comments;

commit;
