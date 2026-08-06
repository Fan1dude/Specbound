-- Migration: 0018_legacy_media_linkage_backfill
-- Milestone: 9 (Production Cleanup & Launch) — Migration C
-- Status: PROPOSED — not yet applied. Depends on 0001-0017 being applied
-- first.
--
-- Purpose: restore RLS-authorized access to 7 legacy storage objects that
-- genuinely belong to existing public build_revisions rows, but were
-- uploaded before revision_media tracking existed (pre-Milestone 5A) and
-- so were never captured into it. See
-- docs/MILESTONE_9_MIGRATION_C_LEGACY_BACKFILL.md for the full audit,
-- categorization, dry-run methodology, and rationale.
--
--   Scope is deliberately narrow: "Category A" only — the 7 objects
--   below, each one's revision_id -> storage_path linkage independently
--   proven by an EXISTING build_revisions.image_url value (not inferred,
--   not filename-matched, not guessed). Every one of these 7 revisions
--   currently has zero revision_media rows (confirmed live immediately
--   before writing this migration), so this is a pure addition, not a
--   modification of anything that already exists.
--
--   "Category B" — 3 further legacy objects (what-to-call's and
--   build-soon's build-level covers, plus desk's own build-level cover
--   distinct from its 5 revisions) — is explicitly NOT backfilled here.
--   Ownership is provable for those three (their owning build's own
--   image_url column says so), but revision linkage is not (no revision
--   row's own image_url corroborates it, and what-to-call has zero
--   revisions to link to at all). Attaching them to an unrelated existing
--   revision would be linking on convenience, not proof, and would make
--   that revision's is_cover claim factually wrong. Left for a separate,
--   later, explicitly-scoped decision — see the architecture doc's
--   Category B section for the three options considered.
--
--   Never touches: builds.image_url / build_revisions.image_url (no
--   column is rewritten, per the "read path only" principle carried
--   through Migrations A/B/C), storage.objects, any storage.objects RLS
--   policy, or the project-images bucket's public/private flag. This
--   migration only ever inserts rows into public.revision_media.
--
-- Touches: revision_media (7 new rows, guarded by a NOT EXISTS check so
-- re-running this migration is a no-op the second time).
--
-- Fresh-database safety (added 2026-08-01, after a dev dry run against an
-- empty database failed here): revision_media.revision_id is a NOT NULL
-- foreign key to build_revisions(id) (see 0002). On a freshly-bootstrapped
-- database, none of the 7 hardcoded revision_id values below exist —
-- they're specific rows from the real production database this migration
-- was written against — so the INSERT violated that FK constraint
-- outright instead of just finding nothing to guard against. The `join
-- public.build_revisions br on br.id = v.revision_id` below fixes this:
-- on a fresh/dev database it makes every one of the 7 candidate rows
-- fail the join and the migration becomes a clean no-op (0 rows
-- inserted, no error); on the real production database, where all 7
-- revisions genuinely exist (confirmed live per this file's own header
-- above), the join matches all 7 and behavior is unchanged. The existing
-- NOT EXISTS duplicate guard is unchanged and still the thing preventing
-- a second real-database run from double-inserting.
--
-- Rollback: see 0018_legacy_media_linkage_backfill_rollback.sql in
-- supabase/rollbacks/. Deletes exactly these 7 rows by their precise
-- (revision_id, storage_path) pairs — a no-op on a database where they
-- were never inserted in the first place, same reasoning as above.

begin;

insert into public.revision_media (revision_id, storage_path, display_order, is_cover)
select v.revision_id, v.storage_path, 0, true
from (values
    ('070cc44b-c7fe-4070-bf68-1cb4ce64f4af'::uuid, 'dacdf29e-ea56-4a85-a6a3-6a60cb7c1210/revisions/1783540195367-Screenshot 2026-01-25 203600.png'),
    ('31cdd3f9-fcd2-4509-8d58-f0ed361960f5'::uuid, 'dacdf29e-ea56-4a85-a6a3-6a60cb7c1210/revisions/1783540440054-Screenshot 2026-01-25 203600.png'),
    ('21f12b41-ae58-40e9-b9e6-59c85200369a'::uuid, 'dacdf29e-ea56-4a85-a6a3-6a60cb7c1210/revisions/1783540456590-Screenshot 2026-01-25 203600.png'),
    ('a0c03e2a-57cf-4ce8-9090-cff421a22626'::uuid, 'dacdf29e-ea56-4a85-a6a3-6a60cb7c1210/revisions/1783540460231-Screenshot 2026-01-25 203600.png'),
    ('f70b904c-84c7-42cc-af08-6729cf228d09'::uuid, 'dacdf29e-ea56-4a85-a6a3-6a60cb7c1210/revisions/1783540741159-Screenshot 2026-01-25 203600.png'),
    ('f59e6c5b-a71a-4828-9cd5-37f0d73067a5'::uuid, 'dacdf29e-ea56-4a85-a6a3-6a60cb7c1210/1783986632675-screenshot-2026-06-15-124317.png'),
    ('7f5be50a-f7b4-4f67-b34c-499bd3b5b822'::uuid, 'dacdf29e-ea56-4a85-a6a3-6a60cb7c1210/updates/1784082807634-screenshot-2026-06-15-124311.png')
) as v(revision_id, storage_path)
join public.build_revisions br on br.id = v.revision_id
where not exists (
    select 1 from public.revision_media rm
    where rm.revision_id = v.revision_id and rm.storage_path = v.storage_path
);

commit;
