-- Migration: 0035_setup_inventory_and_builder_dates
-- Milestone: 23 (Setup Inventory, Search & Builder History)
-- Status: PROPOSED — not yet applied. Depends on 0000-0034 being applied
-- first (specifically 0006, which last redefined publish_draft(), and
-- 0005, which defines restore_revision_to_draft() and the
-- build_revisions snapshot columns this migration extends).
--
-- Purpose: adds the Setup-technology product-inventory feature (separate
-- from the existing `specifications` jsonb every technology already
-- has — see docs/milestones/MILESTONE_23_SETUP_INVENTORY_SEARCH_SPECIFICATION.md
-- §3 for the full normalized shape) and an optional creator-set
-- "building since" year on profiles.
--
-- Touches:
--   1. project_drafts, builds, build_revisions — one new nullable-free
--      `setup_inventory jsonb` column each, mirroring exactly how
--      `specifications`/`resources` already work on these three tables.
--   2. saved_setup_categories — new owner-scoped table, reusable
--      category-name templates. A blueprint's own setup_inventory
--      always stores its own name snapshot (see spec §3.3) — this table
--      is never read at public-render time, only from the editor.
--   3. profiles — one new nullable `building_since_year integer` column.
--   4. publish_draft() and restore_revision_to_draft() — replaced
--      in place (same signatures) so setup_inventory is copied through
--      project_drafts -> builds -> build_revisions on publish, and
--      restored from build_revisions -> project_drafts on revision
--      restore. Based on their CURRENT bodies — publish_draft()'s latest
--      redefinition is in 0006_unpublish.sql (not 0002/0004, both
--      superseded); restore_revision_to_draft()'s only definition is in
--      0005_revision_history_and_restore.sql (never redefined since).
--      `create or replace function` preserves each function's existing
--      OID and therefore its existing grants (0006's
--      `grant execute ... to authenticated` for publish_draft() and
--      0005's implicit default grant for restore_revision_to_draft()
--      both still apply after this migration — nothing to re-grant).
--
-- No new SECURITY DEFINER function is introduced by this migration, so
-- migration 0033's default-privilege hardening has no new function
-- surface to close here — saved_setup_categories and
-- profiles.building_since_year are both governed entirely by RLS via
-- plain supabase-js .select()/.insert()/.update()/.delete() calls, the
-- same posture already established for onboarding_welcomed_at (0025)
-- and guidelines_accepted_at/_version (0031/0034). No explicit table
-- grant is added for saved_setup_categories either, matching every
-- other owner-scoped table in this schema (e.g. project_drafts in
-- 0001) — Supabase's ambient default table grants to
-- anon/authenticated already cover this; RLS is the real gate.
--
-- Backfill — deliberately NONE for any column here. Existing
-- project_drafts/builds/build_revisions rows get a valid-but-empty
-- setup_inventory (a real, schemaVersion-tagged empty object, not
-- '{}'::jsonb — so application code never has to special-case "no
-- inventory column value at all" vs "genuinely empty inventory").
-- Existing profiles rows get building_since_year = null — no guessed or
-- inferred year, per this milestone's explicit requirement.
--
-- Rollback: see 0035_setup_inventory_and_builder_dates_rollback.sql in
-- supabase/rollbacks/. Drops saved_setup_categories entirely (losing any
-- saved templates), drops the three setup_inventory columns and
-- building_since_year, and reverts publish_draft()/
-- restore_revision_to_draft() to their pre-0035 bodies (copied verbatim
-- from 0006/0005 respectively) — never leaves either function without a
-- definition.

begin;

-- 1. setup_inventory jsonb — project_drafts, builds, build_revisions ------
-- The empty-but-valid default keeps every row queryable/renderable with
-- no null-check special-casing anywhere in application code.
alter table public.project_drafts
    add column setup_inventory jsonb not null
    default '{"schemaVersion":1,"currency":"USD","categories":[]}'::jsonb;

alter table public.builds
    add column setup_inventory jsonb not null
    default '{"schemaVersion":1,"currency":"USD","categories":[]}'::jsonb;

alter table public.build_revisions
    add column setup_inventory jsonb not null
    default '{"schemaVersion":1,"currency":"USD","categories":[]}'::jsonb;

-- 2. saved_setup_categories — owner-scoped reusable category templates ----
create table public.saved_setup_categories (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    name text not null,
    normalized_name text not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint saved_setup_categories_name_length
        check (char_length(trim(name)) between 1 and 60),
    constraint saved_setup_categories_owner_name_unique
        unique (user_id, normalized_name)
);

-- Maintained by trigger, not computed at read time, so the uniqueness
-- constraint above is enforced by Postgres itself (case-insensitive,
-- whitespace-insensitive) rather than trusted to every call site
-- remembering to normalize before insert/update.
create function public.set_saved_setup_category_normalized_name()
returns trigger
language plpgsql
as $$
begin
    new.normalized_name := lower(trim(new.name));
    return new;
end;
$$;

create trigger set_saved_setup_categories_normalized_name
    before insert or update of name on public.saved_setup_categories
    for each row
    execute function public.set_saved_setup_category_normalized_name();

create trigger set_saved_setup_categories_updated_at
    before update on public.saved_setup_categories
    for each row
    execute function public.set_updated_at();

alter table public.saved_setup_categories enable row level security;

-- Owner-only on every operation — explicitly NO public/select-all
-- policy. A saved category is a private authoring tool, never part of
-- any public blueprint read path (see spec §3.3 — published content
-- carries its own name snapshot, never a live reference here).
create policy "Owners can select their saved setup categories"
    on public.saved_setup_categories
    for select
    using (auth.uid() = user_id);

create policy "Owners can insert their saved setup categories"
    on public.saved_setup_categories
    for insert
    with check (auth.uid() = user_id);

create policy "Owners can update their saved setup categories"
    on public.saved_setup_categories
    for update
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

create policy "Owners can delete their saved setup categories"
    on public.saved_setup_categories
    for delete
    using (auth.uid() = user_id);

-- 3. profiles.building_since_year — optional, creator-set --------------
alter table public.profiles
    add column building_since_year integer;

alter table public.profiles
    add constraint profiles_building_since_year_range_check
    check (
        building_since_year is null
        or (building_since_year between 1980 and extract(year from now())::integer)
    );

-- 4. publish_draft() — replaced in place, setup_inventory added ----------
-- Body is 0006_unpublish.sql's current definition verbatim, with three
-- additions (marked -- 0035): v_draft.setup_inventory copied into the
-- first-publish INSERT, the republish UPDATE, and the new-revision
-- INSERT. No other line of this function's logic is changed.
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
    -- convenience, this is the actual gate.
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

        -- builds has no version/progress column — those only exist on
        -- build_revisions. image_url is stored as a storage path, not a
        -- ready URL — reading it as a display URL requires resolving a
        -- signed URL first. visibility isn't set explicitly here — the
        -- column already defaults to 'public' on insert.
        insert into public.builds (
            user_id, title, slug, description, category,
            status, image_url, specifications, setup_inventory
        )
        values (
            v_draft.user_id, v_draft.title, v_slug, v_draft.description, v_draft.category,
            'planning', v_cover_path, v_draft.specifications, v_draft.setup_inventory -- 0035
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
        update public.builds
            set title = v_draft.title,
                description = v_draft.description,
                category = v_draft.category,
                image_url = v_cover_path,
                specifications = v_draft.specifications,
                setup_inventory = v_draft.setup_inventory, -- 0035
                visibility = 'public',
                updated_at = now()
            where id = v_build.id
            returning * into v_build;

        v_revision_title := coalesce(nullif(trim(p_publish_notes), ''), 'Documentation update');
    end if;

    -- Immutable revision log entry + content snapshot ----------------------
    -- progress is always 0: there is no "current progress" source now that
    -- builds doesn't carry it, and progress-tracking is out of scope for
    -- this doc-first publish flow. title/description here remain the
    -- changelog entry (see comment above) — snapshot_title/
    -- snapshot_description carry the actual project content.
    insert into public.build_revisions (
        build_id, user_id, title, description, version,
        progress, image_url, update_type, hours_worked, milestone, attachments,
        snapshot_title, snapshot_description, category, specifications, resources,
        setup_inventory
    )
    values (
        v_build.id, v_draft.user_id, v_revision_title,
        coalesce(nullif(trim(p_publish_notes), ''), ''),
        v_version, 0, v_cover_path,
        'documentation',
        null, false, '[]'::jsonb,
        v_draft.title, v_draft.description, v_draft.category, v_draft.specifications, v_draft.resources,
        v_draft.setup_inventory -- 0035
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

-- 5. restore_revision_to_draft() — replaced in place, setup_inventory
--    restored alongside every other snapshot field ----------------------
-- Body is 0005_revision_history_and_restore.sql's current (only)
-- definition verbatim, with two additions (marked -- 0035): the
-- new-draft INSERT and the existing-draft UPDATE both now also restore
-- v_revision.setup_inventory. No other line of this function's logic is
-- changed.
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

    if v_draft is null then
        -- No draft currently linked to this build (edge case — e.g. it
        -- was deleted after publishing). Nothing to race against, so no
        -- concurrency check applies; create one seeded from the snapshot.
        insert into public.project_drafts (
            user_id, title, description, category, specifications, resources,
            setup_inventory, published_build_id
        )
        values (
            v_build.user_id, v_revision.snapshot_title, v_revision.snapshot_description,
            v_revision.category, v_revision.specifications, v_revision.resources,
            v_revision.setup_inventory, v_build.id -- 0035
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
                setup_inventory = v_revision.setup_inventory -- 0035
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
