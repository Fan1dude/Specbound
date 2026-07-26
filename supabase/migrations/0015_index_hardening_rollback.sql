-- Rollback for: 0015_index_hardening
--
-- Drops all three indexes added by this migration. No data is affected —
-- these were pure index additions with no column or constraint changes
-- beyond the indexes themselves.

begin;

drop index if exists public.builds_slug_unique_idx;
drop index if exists public.build_revisions_build_id_created_at_id_idx;
drop index if exists public.build_revisions_created_at_id_idx;

commit;
