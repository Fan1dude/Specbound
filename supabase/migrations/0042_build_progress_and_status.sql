-- Migration: 0042_build_progress_and_status
-- Milestone: Launch Readiness Audit — Findings 03 (progress tracking
-- disconnected) & 04 (build status disconnected). Not part of the 27A
-- (engineering) or 27B (legal/policy) tracks — a separate, product-facing
-- restoration.
-- Status: PROPOSED — not yet applied to production. Depends on 0000-0041
-- being applied first (specifically 0035, which last redefined
-- publish_draft() and restore_revision_to_draft()).
--
-- REVISED after a real, read-only production preflight (run against the
-- linked project via `supabase db query --linked`, SELECT-only, before
-- any write was attempted) found this migration's original assumptions
-- were wrong on two counts. Documented here in full because both change
-- what "safe to apply" means:
--
--   1. `builds.status` is not exclusively 'planning' in production. The
--      real distribution: 7 rows 'planning', 1 row the legacy 'building'
--      alias, 1 row already 'completed'. The 'completed' row would have
--      received builds.progress = 0 from a plain column DEFAULT, which
--      immediately violates the Completed/100 CHECK constraint this
--      migration adds — the original version would have failed at that
--      ALTER TABLE ... ADD CONSTRAINT step (or, worse, silently produced
--      a "Completed" build showing 0% if constraints were added in a
--      different order).
--   2. `build_revisions.progress` is not exclusively 0 in production.
--      Real values found: eleven 0s, four 50s, one each of 51/58/75/99.
--      The existing 'completed' build's own most recent revision is 99,
--      not 100 — so even a naive "backfill from latest revision" would
--      still violate Completed/100 for that one row. This is real,
--      historical project data (predating the tracked-migration history,
--      or written by some path never captured in it) — it is NEVER
--      rewritten by this migration; see §"Historical progress" below.
--
-- This migration is NOT a zero-backfill migration. It performs an
-- explicit, evidence-based CURRENT-STATE backfill (builds.progress /
-- project_drafts.progress+status), while leaving every historical
-- build_revisions.progress value completely untouched and adding
-- build_revisions.status as nullable (no fabricated default for rows
-- that predate this column). See "Backfill algorithm" below for the
-- exact, ordered steps.
--
-- Also discovered by the same preflight: production's
-- `build_revisions.progress` is `smallint`, not `integer` as
-- 0000_baseline_pre_tracked_tables.sql's reconstruction claims (a real,
-- pre-existing drift between that reconstruction and live production —
-- tracked as a gap in docs/DATABASE.md already). This migration never
-- alters that column's type; every constraint/backfill statement that
-- touches it is written to work identically whether the real type is
-- smallint or integer (a CHECK constraint and an implicit
-- smallint<->integer assignment cast are both type-width-agnostic for
-- values that are always within 0-100).
--
-- Touches:
--   1. project_drafts — two new columns: progress (integer), status
--      (text). Backfilled from each draft's linked (published) build
--      where one exists; default 0/'planning' for standalone/unpublished
--      drafts. NOT NULL + DEFAULT set only after backfill completes.
--   2. builds — one new column (progress); status already exists
--      (0000_baseline) and has never had a CHECK constraint — one is
--      added here for the first time, following the exact precedent
--      0002_publish_draft_and_visibility.sql set for `builds.visibility
--      check (visibility in ('public', 'private'))`. progress is
--      backfilled from each build's latest revision (deterministic
--      order, see below), then reconciled to exactly 100 for any build
--      currently 'completed'.
--   3. build_revisions — one new, NULLABLE column (status), no backfill
--      for existing rows (they stay NULL — "not recorded," not
--      "planning"); progress already exists (0000_baseline) and has
--      never had a CHECK constraint — added here too, without touching
--      a single existing value.
--   4. publish_draft() and restore_revision_to_draft() — replaced in
--      place (identical signatures — see the ACL note below). Based on
--      their CURRENT bodies (0035's). restore_revision_to_draft() gets
--      real new logic (not a mechanical copy-through) for resolving a
--      legacy NULL revision status on restore — see its own header
--      comment below.
--
-- Canonical status vocabulary (four values, matching the product
-- decision): 'planning', 'in_progress', 'paused', 'completed'.
-- 'building' is NOT a canonical value — it was a dead, never-selectable
-- literal the read-side UI (BlueprintCard.js's getStage(), renderBuild.
-- js's formatStatus(), explore/app.js's matchesLifecycle()) has always
-- defensively treated as a synonym for 'in_progress'. Confirmed live:
-- exactly one production build holds it. Before the new CHECK constraint
-- is added, any `builds.status = 'building'` row is normalized to
-- 'in_progress' — and if any *other* unexpected value exists (anything
-- outside planning/in_progress/paused/completed/building), this
-- migration RAISEs and aborts rather than guessing at what to rewrite
-- it to. Existing 'planning'/'completed' rows are untouched by the
-- normalization step (only an exact 'building' match is rewritten).
--
-- Consistency rule (matches the editor's own enforced behavior):
-- status = 'completed' requires progress = 100, enforced as
-- `check (status <> 'completed' or progress = 100)` on project_drafts
-- and builds unconditionally, and on build_revisions with an added
-- `status is null or` clause (a legacy revision with no recorded status
-- is exempt — there's nothing to be consistent or inconsistent *with*).
-- This is one-directional — progress = 100 does NOT require
-- status = 'completed' (In Progress at 100% is explicitly allowed).
--
-- Backfill algorithm (in the exact order this file executes them):
--   1. Add project_drafts.progress/status, builds.progress,
--      build_revisions.status — all NULLABLE, no default yet. Adding
--      them nullable first (rather than NOT NULL DEFAULT immediately)
--      is what makes an evidence-based backfill possible at all: a
--      forced default would already have written the wrong value (0)
--      before this file got a chance to compute the real one.
--   2. Normalize builds.status 'building' -> 'in_progress' (exact match
--      only), then verify no other unexpected value remains — abort
--      clearly, transactionally, before any further step, if one does.
--   3. Verify every existing build_revisions.progress value already
--      falls within 0-100 (defensive; expected to already hold given
--      the real values found).
--   4. Backfill builds.progress from each build's own latest revision:
--        update builds b set progress = coalesce(
--            (select br.progress from build_revisions br
--             where br.build_id = b.id
--             order by br.created_at desc, br.id desc limit 1),
--            0
--        );
--      Ordered by created_at desc (matching every existing app-side
--      "latest revision" query — see publish_draft()'s own version-bump
--      lookup and renderTimeline.js's sort) with `id desc` as an
--      explicit, deterministic tie-breaker for the theoretical case of
--      two revisions sharing a created_at timestamp — build_revisions
--      has no sequence/serial column to break ties with more
--      meaningfully, so a stable-but-arbitrary secondary key is the
--      correct choice here, not a semantically-meaningful one. A build
--      with zero revisions gets 0 (there is no "latest" to read).
--   5. Reconcile: `update builds set progress = 100 where status =
--      'completed';` — runs strictly AFTER step 4, so it overrides that
--      build's backfilled value (which may be less than 100, exactly as
--      found live: 99) rather than the other way around. This is the
--      one and only place this migration treats "Completed" as
--      authoritative over a historical progress number for the CURRENT
--      value — it never touches build_revisions itself.
--   6. Lock in builds.progress as NOT NULL DEFAULT 0 (for future rows).
--   7. Backfill project_drafts.progress/status from each draft's linked
--      build (via published_build_id) — copying the ALREADY-reconciled
--      builds row, so the completed build's own linked draft correctly
--      becomes completed/100, not completed/99. Drafts with no linked
--      build (standalone/never-published, or a build that no longer
--      exists) default to 0/'planning'.
--   8. Lock in project_drafts.progress/status as NOT NULL with their
--      real defaults.
--   9. Add every CHECK constraint (range, canonical vocabulary, and
--      Completed/100 consistency) on all three tables, last — so every
--      constraint validates against already-correct, already-backfilled
--      data, never a placeholder.
--
-- Historical progress: build_revisions.progress is never written by any
-- statement in this migration — not backfilled, not normalized, not
-- clamped. The real 99% revision for the existing Completed build stays
-- exactly 99 forever; only the separate, denormalized builds.progress
-- "current" value becomes 100. The revision timeline (renderTimeline.js)
-- and the individual revision-detail page (renderBuild.js's
-- renderRevisionView()) both read revision.progress, not builds.progress
-- — so the historical record and the current summary can legitimately
-- disagree, by design, without either one being wrong.
--
-- publish_draft()/restore_revision_to_draft() signatures are UNCHANGED:
-- publish_draft(uuid, text, text), restore_revision_to_draft(uuid,
-- timestamptz). This matters specifically because
-- 0038_restrict_pre_0020_function_execute_permissions.sql revoked EXECUTE
-- from `anon` keyed to those exact literal signatures — `create or
-- replace function` on an unchanged signature preserves the function's
-- existing OID and therefore its existing ACL (0038's own header
-- confirms this is exactly why 0035/0037's identical in-place
-- redefinitions were safe). A new parameter would instead create a
-- distinct overload that does NOT inherit that restricted grant.
--
-- publish_draft() needs no new validation logic for progress/status:
-- both are read from `v_draft`, whose own new CHECK constraints already
-- guarantee a draft can never hold invalid progress/status by the time
-- this function reads them — it does not clamp or re-validate them, by
-- design. Every future revision it inserts gets a real, non-null status
-- from the draft (draft.status is itself NOT NULL) — the NULL case only
-- ever exists for revisions that predate this migration.
--
-- restore_revision_to_draft() gets real new logic, not a mechanical
-- copy-through, because a restored revision's status can be NULL
-- (legacy) and its historical progress can independently be below 100
-- while the resolved status ends up 'completed':
--   - The restored draft's progress is ALWAYS the revision's own
--     historical value, verbatim — never altered, never re-derived.
--   - The restored draft's status is the revision's own recorded status
--     if non-null; otherwise (a legacy, pre-0042 revision) it falls back
--     to the CURRENT draft's status when restoring into an existing,
--     already-linked draft (nothing to re-derive — the draft already
--     has a real, current status), or to the current build's own
--     canonical status when creating a brand-new draft (the build's
--     status is the closest known-good source when no draft exists to
--     fall back on).
--   - After resolving both, if the resolved status is 'completed' and
--     the resolved (historical) progress is below 100, the resolved
--     status is downgraded to 'in_progress' for the draft being
--     written — never by rewriting the historical progress number,
--     which stays exactly what that revision actually recorded. This is
--     the same Hard Model C reconciliation the editor performs, applied
--     once, at restore time, to the draft only.
--   - v_revision itself (the historical build_revisions row) is never
--     written to by this function, before or after this change.
--
-- No grant statements are added — no new function is created, no
-- existing function's signature changes, so there is nothing for 0033's
-- default-privilege hardening or 0038's anon-revoke to re-cover.
--
-- Rollback: see 0042_build_progress_and_status_rollback.sql in
-- supabase/rollbacks/. Restores publish_draft()/restore_revision_to_draft()
-- to their exact pre-0042 (0035) bodies, drops every constraint and
-- column this migration adds. Never touches build_revisions.progress
-- (only ever adds/removes a CHECK constraint on it, never rewrites a
-- value). Cannot un-normalize a 'building' value that was rewritten to
-- 'in_progress' during the forward migration, and cannot un-reconcile a
-- 'completed' build's progress back to whatever its pre-migration
-- backfilled-but-not-yet-100 value would have been (that intermediate
-- value is never persisted anywhere — it exists only inside the single
-- forward-migration transaction) — both are documented as intentionally
-- irreversible in the rollback file itself.

begin;

-- 1. New columns — NULLABLE, no default yet. Forcing NOT NULL DEFAULT
--    here would already have written the wrong value (a placeholder)
--    before the real, evidence-based backfill below ever runs. --------
alter table public.project_drafts
    add column progress integer;

alter table public.project_drafts
    add column status text;

alter table public.builds
    add column progress integer;

-- Deliberately nullable forever, not just "nullable until backfilled" —
-- existing rows have no recorded status and none is fabricated for them.
-- See the migration header's "Historical progress" section.
alter table public.build_revisions
    add column status text;

-- 2. Validate existing status vocabulary BEFORE any irreversible
--    backfill/reconciliation step runs -- exactly the "abort clearly,
--    transactionally, before partial application" requirement. Scoped
--    to builds.status only: build_revisions.status is a brand-new,
--    always-null-for-existing-rows column (nothing to normalize), and
--    project_drafts.progress/status are likewise brand new. -----------
do $$
declare
    v_unexpected_count integer;
    v_unexpected_values text;
begin
    update public.builds set status = 'in_progress' where status = 'building';

    select count(*), string_agg(distinct status, ', ' order by status)
        into v_unexpected_count, v_unexpected_values
    from public.builds
    where status not in ('planning', 'in_progress', 'paused', 'completed');

    if v_unexpected_count > 0 then
        raise exception
            'Migration 0042 aborted: % builds.status row(s) hold unexpected value(s) [%] outside planning/in_progress/paused/completed after normalizing the known ''building'' legacy alias. Resolve these manually (this migration will not guess a rewrite) before re-running.',
            v_unexpected_count, v_unexpected_values;
    end if;
end $$;

-- Defensive range check for build_revisions.progress -- confirmed live
-- to hold real, varied, in-range values (0/50/51/58/75/99); this is the
-- same "verify before constraining, don't assume" standard applied
-- everywhere else in this migration, not an assumption that it's always
-- exactly 0 anymore. -----------------------------------------------------
do $$
declare
    v_unexpected_count integer;
begin
    select count(*) into v_unexpected_count
    from public.build_revisions
    where progress < 0 or progress > 100;

    if v_unexpected_count > 0 then
        raise exception
            'Migration 0042 aborted: % build_revisions.progress row(s) fall outside 0-100. Resolve these manually before re-running.',
            v_unexpected_count;
    end if;
end $$;

-- 3. Backfill builds.progress from each build's own latest revision
--    (deterministic order: created_at desc, id desc as an explicit
--    stable tie-breaker -- build_revisions has no sequence column to
--    break ties more meaningfully). A build with zero revisions gets 0,
--    since there is no "latest" to read. Never touches
--    build_revisions.progress itself. -------------------------------------
update public.builds b
set progress = coalesce(
    (
        select br.progress::integer
        from public.build_revisions br
        where br.build_id = b.id
        order by br.created_at desc, br.id desc
        limit 1
    ),
    0
);

-- 4. Reconcile: a build currently 'completed' becomes progress = 100,
--    overriding whatever its latest-revision backfill produced (which
--    may be below 100, exactly as found live). This is the ONLY
--    statement in this migration that treats current status as
--    authoritative over a historical progress number, and it only ever
--    writes to builds.progress -- never to build_revisions. -------------
update public.builds set progress = 100 where status = 'completed';

-- 5. Lock in builds.progress for future rows now that every existing row
--    has a real, backfilled value. -----------------------------------
alter table public.builds
    alter column progress set not null;

alter table public.builds
    alter column progress set default 0;

-- 6. Backfill project_drafts.progress/status from each draft's linked
--    (published) build -- reading the ALREADY-reconciled builds row, so
--    a draft linked to the Completed build correctly becomes
--    completed/100, not completed/99. Drafts with no linked build
--    (standalone, never published, or pointing at a build that no
--    longer exists) get the safe default below instead. -----------------
update public.project_drafts pd
set progress = b.progress,
    status = b.status
from public.builds b
where pd.published_build_id = b.id;

update public.project_drafts set progress = 0 where progress is null;
update public.project_drafts set status = 'planning' where status is null;

alter table public.project_drafts
    alter column progress set not null;

alter table public.project_drafts
    alter column progress set default 0;

alter table public.project_drafts
    alter column status set not null;

alter table public.project_drafts
    alter column status set default 'planning';

-- 7. Constraints — added last, after every column holds real,
--    already-correct data; stable, explicit names so the rollback can
--    drop them reliably by name. ---------------------------------------

-- project_drafts
alter table public.project_drafts
    add constraint project_drafts_progress_check
    check (progress between 0 and 100);

alter table public.project_drafts
    add constraint project_drafts_status_check
    check (status in ('planning', 'in_progress', 'paused', 'completed'));

alter table public.project_drafts
    add constraint project_drafts_status_progress_check
    check (status <> 'completed' or progress = 100);

-- builds — same shape of precedent as 0002's
-- `builds.visibility check (visibility in ('public', 'private'))`.
alter table public.builds
    add constraint builds_progress_check
    check (progress between 0 and 100);

alter table public.builds
    add constraint builds_status_check
    check (status in ('planning', 'in_progress', 'paused', 'completed'));

alter table public.builds
    add constraint builds_status_progress_check
    check (status <> 'completed' or progress = 100);

-- build_revisions — status is nullable, so both the vocabulary and the
-- Completed/100 checks explicitly permit null (a legacy, not-recorded
-- revision is valid by definition, not merely "not yet checked").
alter table public.build_revisions
    add constraint build_revisions_progress_check
    check (progress between 0 and 100);

alter table public.build_revisions
    add constraint build_revisions_status_check
    check (status is null or status in ('planning', 'in_progress', 'paused', 'completed'));

alter table public.build_revisions
    add constraint build_revisions_status_progress_check
    check (status is null or status <> 'completed' or progress = 100);

-- 8. publish_draft() — replaced in place, progress/status added ----------
-- Body is 0035_setup_inventory_and_builder_dates.sql's current
-- definition verbatim, with additions marked -- 0042: v_draft.progress/
-- v_draft.status copied into the first-publish INSERT, the republish
-- UPDATE, and the new-revision INSERT (replacing the old hardcoded
-- 'planning'/0 literals). No other line of this function's logic is
-- changed.
create or replace function public.publish_draft(
    p_draft_id uuid,
    p_version_label text default null,
    p_publish_notes text default null
)
returns public.builds
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_draft public.project_drafts;
    v_build public.builds;
    v_revision public.build_revisions;
    v_cover_path text;
    v_matching_media_count integer;
    v_base_slug text;
    v_slug text;
    v_suffix integer;
    v_version text;
    v_previous_version text;
    v_version_match text[];
    v_is_first_publish boolean;
    v_revision_title text;
begin
    -- Ownership -------------------------------------------------------
    select * into v_draft from public.project_drafts where id = p_draft_id;

    if v_draft is null then
        raise exception 'Draft not found.';
    end if;

    if v_draft.user_id <> auth.uid() then
        raise exception 'Only the draft owner can publish it.';
    end if;

    -- Server-side readiness re-validation, mirroring the rules in
    -- js/services/draftValidation.js — the client-side checklist is a UX
    -- convenience, this is the actual gate. progress/status need no
    -- equivalent check here: project_drafts' own CHECK constraints
    -- (added by 0042) already guarantee v_draft.progress/status can
    -- never be invalid by the time this function reads them.
    if length(trim(v_draft.title)) < 3 or length(trim(v_draft.title)) > 100 then
        raise exception 'Title must be between 3 and 100 characters.';
    end if;

    if length(trim(v_draft.description)) < 20 then
        raise exception 'Description must be at least 20 characters.';
    end if;

    if v_draft.category is null or trim(v_draft.category) = '' then
        raise exception 'A category is required.';
    end if;

    if v_draft.cover_media_id is null then
        raise exception 'A cover image is required.';
    end if;

    -- The cover must actually belong to this draft's own gallery — a
    -- stale/forged cover_media_id (deleted since, or never valid) must
    -- never be publishable.
    select count(*), max(storage_path) into v_matching_media_count, v_cover_path
    from public.project_media
    where draft_id = p_draft_id and id = v_draft.cover_media_id;

    if v_matching_media_count <> 1 then
        raise exception 'The selected cover image no longer belongs to this draft.';
    end if;

    v_is_first_publish := v_draft.published_build_id is null;

    -- First publish vs. republish ---------------------------------------
    if v_is_first_publish then
        v_version := coalesce(nullif(trim(p_version_label), ''), 'v1.0');

        v_base_slug := lower(trim(both '-' from regexp_replace(v_draft.title, '[^a-zA-Z0-9]+', '-', 'g')));

        if v_base_slug = '' then
            v_base_slug := 'project';
        end if;

        v_slug := v_base_slug;
        v_suffix := 1;

        while exists (select 1 from public.builds where slug = v_slug) loop
            v_suffix := v_suffix + 1;
            v_slug := v_base_slug || '-' || v_suffix;
        end loop;

        -- image_url is stored as a storage path, not a ready URL —
        -- reading it as a display URL requires resolving a signed URL
        -- first. visibility isn't set explicitly here — the column
        -- already defaults to 'public' on insert. status/progress now
        -- come from the draft itself, not a hardcoded literal -- 0042.
        insert into public.builds (
            user_id, title, slug, description, category,
            status, image_url, specifications, setup_inventory, progress
        )
        values (
            v_draft.user_id, v_draft.title, v_slug, v_draft.description, v_draft.category,
            v_draft.status, v_cover_path, v_draft.specifications, v_draft.setup_inventory, v_draft.progress -- 0042
        )
        returning * into v_build;

        update public.project_drafts
            set published_build_id = v_build.id
            where id = p_draft_id;

        v_revision_title := 'Initial publish';
    else
        select * into v_build from public.builds where id = v_draft.published_build_id;

        if v_build is null then
            raise exception 'The build this draft was published to no longer exists.';
        end if;

        -- No version input exists in the editor UI (yet), and builds has
        -- no version column to read a "current" value from — version only
        -- lives on build_revisions. An explicit p_version_label always
        -- wins; otherwise republishing auto-bumps the minor version off
        -- the most recent existing revision for this build
        -- (v1.0 -> v1.1 -> v1.2, ...).
        if p_version_label is not null and trim(p_version_label) <> '' then
            v_version := trim(p_version_label);
        else
            select version into v_previous_version
            from public.build_revisions
            where build_id = v_build.id
            order by created_at desc
            limit 1;

            v_version_match := regexp_match(coalesce(v_previous_version, ''), '^v?(\d+)\.(\d+)$');

            if v_version_match is null then
                v_version := 'v1.1';
            else
                v_version := 'v' || v_version_match[1] || '.' || (v_version_match[2]::integer + 1);
            end if;
        end if;

        -- Publishing is the action that makes a project live: if it was
        -- unpublished (visibility='private'), republishing restores
        -- visibility='public' as part of this same update — the owner
        -- never has to publish and then separately re-publish visibility.
        -- status/progress are now actually updated here -- 0042 — this
        -- is the literal Finding 04 fix: previously this UPDATE never
        -- touched status at all, freezing it at whatever first publish
        -- set.
        update public.builds
            set title = v_draft.title,
                description = v_draft.description,
                category = v_draft.category,
                image_url = v_cover_path,
                specifications = v_draft.specifications,
                setup_inventory = v_draft.setup_inventory,
                status = v_draft.status, -- 0042
                progress = v_draft.progress, -- 0042
                visibility = 'public',
                updated_at = now()
            where id = v_build.id
            returning * into v_build;

        v_revision_title := coalesce(nullif(trim(p_publish_notes), ''), 'Documentation update');
    end if;

    -- Immutable revision log entry + content snapshot ----------------------
    -- progress/status now carry the draft's real, current values at the
    -- moment of publish -- 0042 — always non-null (v_draft.status/
    -- progress are themselves NOT NULL). The NULL build_revisions.status
    -- case only ever exists for revisions published before this
    -- migration; every future insert here is canonical. title/description
    -- here remain the changelog entry (see comment above) —
    -- snapshot_title/snapshot_description carry the actual project
    -- content.
    insert into public.build_revisions (
        build_id, user_id, title, description, version,
        progress, image_url, update_type, hours_worked, milestone, attachments,
        snapshot_title, snapshot_description, category, specifications, resources,
        setup_inventory, status
    )
    values (
        v_build.id, v_draft.user_id, v_revision_title,
        coalesce(nullif(trim(p_publish_notes), ''), ''),
        v_version, v_draft.progress, v_cover_path, -- 0042
        'documentation',
        null, false, '[]'::jsonb,
        v_draft.title, v_draft.description, v_draft.category, v_draft.specifications, v_draft.resources,
        v_draft.setup_inventory, v_draft.status -- 0042
    )
    returning * into v_revision;

    -- Snapshot the draft's current gallery into this revision. Scoped to
    -- this draft's own project_media rows, so it can never pull in media
    -- belonging to a different draft.
    insert into public.revision_media (revision_id, storage_path, display_order, alt_text, is_cover)
    select v_revision.id, pm.storage_path, pm.display_order, pm.alt_text, pm.id = v_draft.cover_media_id
    from public.project_media pm
    where pm.draft_id = p_draft_id;

    return v_build;
end;
$$;

-- 9. restore_revision_to_draft() — replaced in place, with real new
--    logic for resolving progress/status on restore (not a mechanical
--    copy-through like every other snapshot field). See the migration
--    header's own "restore_revision_to_draft() gets real new logic..."
--    section for the full rule set. Historical progress is always
--    restored verbatim; status resolves from the revision's own recorded
--    value when present, else falls back to the draft's current status
--    (existing draft) or the build's current status (new draft); the
--    Completed/100 rule is then applied to the resolved draft values
--    only — v_revision itself is never written to, before or after this
--    change. -----------------------------------------------------------
create or replace function public.restore_revision_to_draft(
    p_revision_id uuid,
    p_expected_draft_updated_at timestamptz default null
)
returns public.project_drafts
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_revision public.build_revisions;
    v_build public.builds;
    v_draft public.project_drafts;
    v_new_cover_id uuid;
    v_resolved_progress integer;
    v_resolved_status text;
begin
    select * into v_revision from public.build_revisions where id = p_revision_id;

    if v_revision is null then
        raise exception 'Revision not found.';
    end if;

    select * into v_build from public.builds where id = v_revision.build_id;

    if v_build is null then
        raise exception 'The build this revision belongs to no longer exists.';
    end if;

    if v_build.user_id <> auth.uid() then
        raise exception 'Only the build owner can restore a revision.';
    end if;

    -- Lock the draft linked to this build (if one exists) before
    -- comparing/overwriting it, so a concurrent save from the owner's own
    -- editor tab can't slip in between the concurrency check and the
    -- write below.
    select * into v_draft
    from public.project_drafts
    where published_build_id = v_build.id
    for update;

    -- Progress is ALWAYS the revision's own historical value, verbatim —
    -- 0042. Never re-derived, never clamped beyond what its own CHECK
    -- constraint already guarantees.
    v_resolved_progress := v_revision.progress;

    -- Status: the revision's own recorded value if present; a legacy
    -- (pre-0042) revision has none, so it falls back to whatever's the
    -- best already-known-good current status -- the existing draft's own
    -- current status when restoring into one that already exists (it's
    -- already real and current), or the build's own current status when
    -- there's no draft yet to fall back on -- 0042.
    if v_draft is null then
        v_resolved_status := coalesce(v_revision.status, v_build.status);
    else
        v_resolved_status := coalesce(v_revision.status, v_draft.status);
    end if;

    -- Hard Model C, applied once to the resolved draft values only: a
    -- resolved 'completed' status paired with historical progress below
    -- 100 downgrades to 'in_progress' for the draft being written --
    -- the historical progress number itself is never rewritten -- 0042.
    if v_resolved_status = 'completed' and v_resolved_progress < 100 then
        v_resolved_status := 'in_progress';
    end if;

    if v_draft is null then
        -- No draft currently linked to this build (edge case — e.g. it
        -- was deleted after publishing). Nothing to race against, so no
        -- concurrency check applies; create one seeded from the snapshot.
        insert into public.project_drafts (
            user_id, title, description, category, specifications, resources,
            setup_inventory, published_build_id, progress, status
        )
        values (
            v_build.user_id, v_revision.snapshot_title, v_revision.snapshot_description,
            v_revision.category, v_revision.specifications, v_revision.resources,
            v_revision.setup_inventory, v_build.id, v_resolved_progress, v_resolved_status -- 0042
        )
        returning * into v_draft;
    else
        -- Optimistic concurrency: the client must supply the draft's
        -- updated_at as it last saw it. A mismatch (or no value supplied)
        -- means the draft has changed since — reject rather than silently
        -- overwrite newer unsaved/autosaved work.
        if p_expected_draft_updated_at is null or v_draft.updated_at <> p_expected_draft_updated_at then
            raise exception 'This draft has changed since you loaded it — refresh and try restoring again.';
        end if;

        update public.project_drafts
            set title = v_revision.snapshot_title,
                description = v_revision.snapshot_description,
                category = v_revision.category,
                specifications = v_revision.specifications,
                resources = v_revision.resources,
                setup_inventory = v_revision.setup_inventory,
                progress = v_resolved_progress, -- 0042
                status = v_resolved_status -- 0042
            where id = v_draft.id
            returning * into v_draft;
    end if;

    -- Replace the draft's gallery with a fresh copy of this revision's
    -- media snapshot. This only deletes project_media ROWS, not the
    -- underlying Storage objects (SQL can't call the Storage API) — if
    -- the draft's prior images aren't referenced by any revision_media,
    -- their files become orphaned in Storage. Disclosed, accepted
    -- limitation for this milestone. The historical revision_media rows
    -- themselves are only ever read here, never written.
    delete from public.project_media where draft_id = v_draft.id;

    -- The new cover id is decided up front (not matched back after the
    -- fact by storage_path/display_order, and not carried through an
    -- unreferenced INSERT...RETURNING CTE — Postgres only guarantees a
    -- data-modifying CTE runs if the primary query actually references
    -- it, which a "select ... from source" final query here would not
    -- have done for a same-statement "inserted" CTE) so the single
    -- INSERT below is unambiguous and definitely executes.
    if exists (
        select 1 from public.revision_media
        where revision_id = v_revision.id and is_cover
    ) then
        v_new_cover_id := gen_random_uuid();
    else
        v_new_cover_id := null;
    end if;

    insert into public.project_media (id, draft_id, storage_path, display_order, alt_text)
    select
        case when rm.is_cover then v_new_cover_id else gen_random_uuid() end,
        v_draft.id, rm.storage_path, rm.display_order, rm.alt_text
    from public.revision_media rm
    where rm.revision_id = v_revision.id;

    update public.project_drafts
        set cover_media_id = v_new_cover_id
        where id = v_draft.id
        returning * into v_draft;

    return v_draft;
end;
$$;

commit;
