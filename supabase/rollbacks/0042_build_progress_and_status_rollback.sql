-- Rollback for 0042_build_progress_and_status.
--
-- Restores publish_draft() and restore_revision_to_draft() to their exact
-- pre-0042 bodies (0035_setup_inventory_and_builder_dates.sql's
-- definitions — never leaves either function without a definition), then
-- drops every constraint and column 0042 added. Unrelated schema/data
-- (setup_inventory, saved_setup_categories, building_since_year, and
-- everything from earlier migrations) is untouched. This rollback never
-- writes to build_revisions.progress — 0042's forward migration never did
-- either (only ever adding/removing a CHECK constraint on it); no
-- historical progress value is ever at risk from either direction.
--
-- IMPORTANT — data-value irreversibility, confirmed against real
-- production data during this migration's own preflight (not a
-- theoretical concern):
--
--   1. 'building' -> 'in_progress' normalization. 0042's forward
--      migration normalizes any `builds.status = 'building'` row to
--      'in_progress' before adding the canonical CHECK constraint. That
--      literal 'building' value is not retained anywhere (no shadow
--      column, no audit table) — running this rollback does NOT restore
--      any row that was normalized back to 'building'. It will read as
--      'in_progress' after rollback, exactly as it did immediately after
--      the forward migration ran. 'building' was already a dead,
--      never-selectable value before 0042, so this is not a loss of any
--      real distinction the application ever exposed.
--
--   2. Completed/100 current-progress reconciliation. 0042's forward
--      migration backfills builds.progress from each build's latest
--      revision, then overrides that value to exactly 100 for any build
--      currently 'completed' — a real production build's backfilled
--      value (99, from its actual latest revision) was overridden this
--      way. That intermediate 99 is never persisted anywhere outside the
--      single forward-migration transaction — this rollback cannot
--      restore builds.progress to "what it would have backfilled to
--      before reconciliation," because that value never existed as a
--      standalone, addressable piece of data. This is fine: the DROP
--      COLUMN below removes builds.progress entirely regardless, and the
--      real historical number (99) was never touched in the first place
--      — it lives in build_revisions.progress, completely untouched by
--      either the forward migration or this rollback.
--
-- Also note: dropping the progress/status columns discards any real
-- progress/status values builders have set through the editor since 0042
-- was applied — a real, intentional data-loss rollback for those two
-- columns specifically, not a no-op. Only run this with a specific,
-- reviewed reason.

begin;

-- 1. publish_draft() — back to 0035's body, verbatim ----------------------
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
    select * into v_draft from public.project_drafts where id = p_draft_id;

    if v_draft is null then
        raise exception 'Draft not found.';
    end if;

    if v_draft.user_id <> auth.uid() then
        raise exception 'Only the draft owner can publish it.';
    end if;

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

    select count(*), max(storage_path) into v_matching_media_count, v_cover_path
    from public.project_media
    where draft_id = p_draft_id and id = v_draft.cover_media_id;

    if v_matching_media_count <> 1 then
        raise exception 'The selected cover image no longer belongs to this draft.';
    end if;

    v_is_first_publish := v_draft.published_build_id is null;

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

        insert into public.builds (
            user_id, title, slug, description, category,
            status, image_url, specifications, setup_inventory
        )
        values (
            v_draft.user_id, v_draft.title, v_slug, v_draft.description, v_draft.category,
            'planning', v_cover_path, v_draft.specifications, v_draft.setup_inventory
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

        update public.builds
            set title = v_draft.title,
                description = v_draft.description,
                category = v_draft.category,
                image_url = v_cover_path,
                specifications = v_draft.specifications,
                setup_inventory = v_draft.setup_inventory,
                visibility = 'public',
                updated_at = now()
            where id = v_build.id
            returning * into v_build;

        v_revision_title := coalesce(nullif(trim(p_publish_notes), ''), 'Documentation update');
    end if;

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
        v_draft.setup_inventory
    )
    returning * into v_revision;

    insert into public.revision_media (revision_id, storage_path, display_order, alt_text, is_cover)
    select v_revision.id, pm.storage_path, pm.display_order, pm.alt_text, pm.id = v_draft.cover_media_id
    from public.project_media pm
    where pm.draft_id = p_draft_id;

    return v_build;
end;
$$;

-- 2. restore_revision_to_draft() — back to 0035's body, verbatim ---------
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

    select * into v_draft
    from public.project_drafts
    where published_build_id = v_build.id
    for update;

    if v_draft is null then
        insert into public.project_drafts (
            user_id, title, description, category, specifications, resources,
            setup_inventory, published_build_id
        )
        values (
            v_build.user_id, v_revision.snapshot_title, v_revision.snapshot_description,
            v_revision.category, v_revision.specifications, v_revision.resources,
            v_revision.setup_inventory, v_build.id
        )
        returning * into v_draft;
    else
        if p_expected_draft_updated_at is null or v_draft.updated_at <> p_expected_draft_updated_at then
            raise exception 'This draft has changed since you loaded it — refresh and try restoring again.';
        end if;

        update public.project_drafts
            set title = v_revision.snapshot_title,
                description = v_revision.snapshot_description,
                category = v_revision.category,
                specifications = v_revision.specifications,
                resources = v_revision.resources,
                setup_inventory = v_revision.setup_inventory
            where id = v_draft.id
            returning * into v_draft;
    end if;

    delete from public.project_media where draft_id = v_draft.id;

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

-- 3. Drop only the constraints and columns 0042 added ---------------------
alter table public.project_drafts drop constraint if exists project_drafts_status_progress_check;
alter table public.project_drafts drop constraint if exists project_drafts_status_check;
alter table public.project_drafts drop constraint if exists project_drafts_progress_check;
alter table public.project_drafts drop column if exists status;
alter table public.project_drafts drop column if exists progress;

alter table public.builds drop constraint if exists builds_status_progress_check;
alter table public.builds drop constraint if exists builds_status_check;
alter table public.builds drop constraint if exists builds_progress_check;
alter table public.builds drop column if exists progress;
-- builds.status itself is NOT dropped — it predates 0042 (0000_baseline).
-- Only the CHECK constraint 0042 added is removed above; the column and
-- its data (including any 'building' rows already normalized to
-- 'in_progress' — see the header note above) are left exactly as they
-- stood after the forward migration.

alter table public.build_revisions drop constraint if exists build_revisions_status_progress_check;
alter table public.build_revisions drop constraint if exists build_revisions_status_check;
alter table public.build_revisions drop constraint if exists build_revisions_progress_check;
alter table public.build_revisions drop column if exists status;
-- build_revisions.progress itself is NOT dropped — it predates 0042
-- (0000_baseline). Only the CHECK constraint 0042 added is removed above.

commit;
