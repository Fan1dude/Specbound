-- Legacy build-status/progress fixture —
-- supabase/tests/fixtures/legacy_build_status_fixture.sql
--
-- Reproduces the SHAPE of Specbound's real production data, confirmed by
-- a read-only production preflight (SELECT-only, via
-- `supabase db query --linked`) run before migration 0042 was first
-- attempted there: builds mostly 'planning', one build stuck on the
-- legacy 'building' alias, one build already 'completed' whose own most
-- recent revision recorded 99% (not 100), and real non-zero historical
-- build_revisions.progress values (the exact set found live: 0, 50, 51,
-- 58, 75, 99). Also mutates build_revisions.progress to `smallint` after
-- inserting this data, matching production's real column type — the
-- reconstructed 0000_baseline_pre_tracked_tables.sql claims `integer`,
-- which is itself a drift from production this fixture deliberately
-- reproduces rather than papers over.
--
-- Used by migration_0042_legacy_upgrade.test.sql to prove 0042: never
-- rewrites a single historical build_revisions.progress value; correctly
-- backfills each build's CURRENT progress from its own latest revision
-- (deterministic order); reconciles a Completed build's current progress
-- to exactly 100 without touching its historical 99; normalizes
-- 'building' to 'in_progress' while mirroring that build's own latest
-- revision progress; leaves a no-revision build at 0; backfills a linked
-- draft from its build; and works whether build_revisions.progress is
-- smallint or integer. Must be applied to a database that already has
-- 0000-0041 (and only 0000-0041) applied — run BEFORE
-- `supabase migration up`, never after.
--
-- Deliberately plain SQL only — no psql meta-commands — so this runs the
-- same way through any client. Wrapped in its own begin/commit (not
-- begin/rollback): this must actually persist, since 0042 is applied in
-- a separate step afterward and needs to see this data.

begin;

insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-0000-0000-000000000601', 'legacy-fixture-owner@example.invalid', '{"username": "legacy_fixture_owner"}'::jsonb)
on conflict (id) do nothing;

-- --- Build P1: planning, zero revisions -- "no revisions -> progress 0" ---
insert into public.builds (
    id, user_id, title, slug, description, category, status, specifications
) values (
    '00000000-0000-0000-0000-0000000000a1',
    '00000000-0000-0000-0000-000000000601',
    'Legacy Planning No Revisions', 'legacy-planning-no-revisions-fixture',
    'A pre-existing published build with no revision history at all.',
    'pc_build', 'planning', '{}'::jsonb
);

-- --- Build P2: planning, one revision (progress=50) -- "planning mirrors
-- its latest historical progress, not forced to 0" -------------------------
insert into public.builds (
    id, user_id, title, slug, description, category, status, specifications
) values (
    '00000000-0000-0000-0000-0000000000a2',
    '00000000-0000-0000-0000-000000000601',
    'Legacy Planning One Revision', 'legacy-planning-one-revision-fixture',
    'A pre-existing published build with a single revision.',
    'pc_build', 'planning', '{}'::jsonb
);

insert into public.build_revisions (
    id, build_id, user_id, title, description, version, progress, update_type
) values (
    '00000000-0000-0000-0000-0000000000e1',
    '00000000-0000-0000-0000-0000000000a2',
    '00000000-0000-0000-0000-000000000601',
    'Initial publish', '', 'v1.0', 50, 'documentation'
);

-- --- Build P3: planning, two revisions (0 then 58 latest) -- proves the
-- deterministic "latest by created_at desc" ordering picks 58, not the
-- earlier 0. -------------------------------------------------------------
insert into public.builds (
    id, user_id, title, slug, description, category, status, specifications
) values (
    '00000000-0000-0000-0000-0000000000a3',
    '00000000-0000-0000-0000-000000000601',
    'Legacy Planning Two Revisions', 'legacy-planning-two-revisions-fixture',
    'A pre-existing published build with two revisions, oldest first.',
    'pc_build', 'planning', '{}'::jsonb
);

insert into public.build_revisions (
    id, build_id, user_id, title, description, version, progress, update_type, created_at
) values (
    '00000000-0000-0000-0000-0000000000e2',
    '00000000-0000-0000-0000-0000000000a3',
    '00000000-0000-0000-0000-000000000601',
    'Initial publish', '', 'v1.0', 0, 'documentation', now() - interval '2 days'
);

insert into public.build_revisions (
    id, build_id, user_id, title, description, version, progress, update_type, created_at
) values (
    '00000000-0000-0000-0000-0000000000e3',
    '00000000-0000-0000-0000-0000000000a3',
    '00000000-0000-0000-0000-000000000601',
    'Documentation update', '', 'v1.1', 58, 'documentation', now() - interval '1 day'
);

-- --- Build B1: the legacy 'building' alias, two revisions (51 then 75
-- latest) -- matches production's real building-build shape exactly
-- (2 revisions, max/latest progress 75). --------------------------------
insert into public.builds (
    id, user_id, title, slug, description, category, status, specifications
) values (
    '00000000-0000-0000-0000-0000000000b1',
    '00000000-0000-0000-0000-000000000601',
    'Legacy Building Build', 'legacy-building-build-fixture',
    'A pre-existing published build stuck at the legacy building value.',
    'pc_build', 'building', '{}'::jsonb
);

insert into public.build_revisions (
    id, build_id, user_id, title, description, version, progress, update_type, created_at
) values (
    '00000000-0000-0000-0000-0000000000e4',
    '00000000-0000-0000-0000-0000000000b1',
    '00000000-0000-0000-0000-000000000601',
    'Initial publish', '', 'v1.0', 51, 'documentation', now() - interval '2 days'
);

insert into public.build_revisions (
    id, build_id, user_id, title, description, version, progress, update_type, created_at
) values (
    '00000000-0000-0000-0000-0000000000e5',
    '00000000-0000-0000-0000-0000000000b1',
    '00000000-0000-0000-0000-000000000601',
    'Documentation update', '', 'v1.1', 75, 'documentation', now() - interval '1 day'
);

-- --- Build C1: 'completed', one revision at 99 (NOT 100) -- matches
-- production's real completed-build shape exactly. This is the row the
-- whole Completed/100 reconciliation exists for. --------------------------
insert into public.builds (
    id, user_id, title, slug, description, category, status, specifications
) values (
    '00000000-0000-0000-0000-0000000000c1',
    '00000000-0000-0000-0000-000000000601',
    'Legacy Completed Build', 'legacy-completed-build-fixture',
    'A pre-existing published build already marked completed.',
    'pc_build', 'completed', '{}'::jsonb
);

insert into public.build_revisions (
    id, build_id, user_id, title, description, version, progress, update_type
) values (
    '00000000-0000-0000-0000-0000000000e6',
    '00000000-0000-0000-0000-0000000000c1',
    '00000000-0000-0000-0000-000000000601',
    'Initial publish', '', 'v1.0', 99, 'documentation'
);

-- --- Linked drafts -- prove project_drafts backfills from its build,
-- not a fabricated default, once builds.progress/status are reconciled. --
insert into public.project_drafts (
    id, user_id, title, description, category, published_build_id
) values (
    '00000000-0000-0000-0000-0000000000d1',
    '00000000-0000-0000-0000-000000000601',
    'Legacy Completed Build', 'A description with real content for readiness checks.',
    'pc_build', '00000000-0000-0000-0000-0000000000c1'
);

insert into public.project_drafts (
    id, user_id, title, description, category, published_build_id
) values (
    '00000000-0000-0000-0000-0000000000d2',
    '00000000-0000-0000-0000-000000000601',
    'Legacy Building Build', 'A description with real content for readiness checks.',
    'pc_build', '00000000-0000-0000-0000-0000000000b1'
);

-- --- Standalone/unpublished draft -- no linked build at all, must
-- default to planning/0, never inventing a value from an unrelated build. --
insert into public.project_drafts (
    id, user_id, title, description, category
) values (
    '00000000-0000-0000-0000-0000000000d3',
    '00000000-0000-0000-0000-000000000601',
    'Legacy Standalone Draft', 'A description with real content for readiness checks.',
    'pc_build'
);

-- Match production's real column type. The reconstructed
-- 0000_baseline_pre_tracked_tables.sql claims `integer`; this fixture
-- deliberately narrows the local disposable database's column to the
-- type actually confirmed live, so 0042's own smallint-vs-integer
-- agnosticism is exercised for real, not just reasoned about.
alter table public.build_revisions alter column progress type smallint;

commit;
