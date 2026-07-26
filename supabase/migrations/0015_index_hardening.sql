-- Migration: 0015_index_hardening
-- Milestone: 8A (Security & Data Integrity)
-- Status: PROPOSED — not yet applied. Depends on 0001-0014 being applied
-- first.
--
-- Purpose: close two missing-index gaps found during the Milestone 8
-- audit.
--
--   1. builds.slug had no unique index or constraint anywhere in this
--      schema's tracked history, despite being the primary lookup key
--      for getBuildBySlug() on every single project-page view, and being
--      checked in a loop during publish_draft()'s first-publish
--      slug-uniqueness logic. With no index this was an unindexed
--      sequential-scan lookup on the app's single most common query;
--      with no unique constraint, uniqueness was purely an
--      application-level, check-then-insert guarantee — racy in theory
--      (two concurrent first-publishes with colliding generated slugs
--      could both pass the "exists" check before either inserts). The
--      preflight check below (same pattern as the duplicate-draft check
--      in 0005_revision_history_and_restore.sql) fails clearly and
--      explicitly rather than letting the unique index creation fail
--      opaquely, and deliberately does NOT rename/merge duplicates
--      automatically.
--   2. build_revisions had zero indexes beyond its primary key. This
--      table is read by getBuildRevisions() (every build-page load,
--      ordered by created_at), publish_draft()'s republish version-bump
--      lookup (WHERE build_id = ... ORDER BY created_at DESC LIMIT 1),
--      and — most severely — get_activity_feed()
--      (0013_activity_feed.sql), which needs ORDER BY created_at DESC,
--      id DESC across the whole table for its keyset pagination AND runs
--      a correlated subquery filtered by build_id and ordered by
--      (created_at, id) once per candidate row for activity-type
--      classification. This table is the direct content source for the
--      home page's Activity Feed.
--
-- Touches: builds (new unique index), build_revisions (two new
-- indexes). No column or function changes.
--
-- Rollback: see 0015_index_hardening_rollback.sql in this folder.

begin;

-- Preflight: fail clearly rather than let the unique index creation
-- below fail opaquely, and never rename/merge duplicates automatically.
do $$
declare
    v_duplicate_count integer;
begin
    select count(*) into v_duplicate_count
    from (
        select slug
        from public.builds
        group by slug
        having count(*) > 1
    ) dupes;

    if v_duplicate_count > 0 then
        raise exception
            'Found % build slug(s) with duplicates. This migration will not rename or merge them automatically — resolve by hand first. Run this to see exactly what''s duplicated: select slug, array_agg(id) as build_ids from public.builds group by slug having count(*) > 1;',
            v_duplicate_count;
    end if;
end $$;

create unique index builds_slug_unique_idx on public.builds (slug);

create index build_revisions_build_id_created_at_id_idx
    on public.build_revisions (build_id, created_at, id);

create index build_revisions_created_at_id_idx
    on public.build_revisions (created_at desc, id desc);

commit;
