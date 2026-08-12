-- Rollback for 0035_setup_inventory_and_builder_dates.
--
-- Restores publish_draft() and restore_revision_to_draft() to their
-- exact pre-0035 bodies (0006_unpublish.sql's and
-- 0005_revision_history_and_restore.sql's definitions, respectively —
-- never leaves either function without a definition), drops
-- saved_setup_categories entirely (any saved templates are lost — this
-- is a real, intentional data-loss rollback, not a no-op), and drops
-- every column this migration added. guidelines_accepted_at-style
-- "leave data alone" caution does not apply here: setup_inventory and
-- building_since_year are both wholly new columns with no pre-existing
-- data to protect, unlike a column added onto an established feature.

begin;

-- 1. publish_draft() — back to 0006_unpublish.sql's body, verbatim -------
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
            status, image_url, specifications
        )
        values (
            v_draft.user_id, v_draft.title, v_slug, v_draft.description, v_draft.category,
            'planning', v_cover_path, v_draft.specifications
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
                visibility = 'public',
                updated_at = now()
            where id = v_build.id
            returning * into v_build;

        v_revision_title := coalesce(nullif(trim(p_publish_notes), ''), 'Documentation update');
    end if;

    insert into public.build_revisions (
        build_id, user_id, title, description, version,
        progress, image_url, update_type, hours_worked, milestone, attachments,
        snapshot_title, snapshot_description, category, specifications, resources
    )
    values (
        v_build.id, v_draft.user_id, v_revision_title,
        coalesce(nullif(trim(p_publish_notes), ''), ''),
        v_version, 0, v_cover_path,
        'documentation',
        null, false, '[]'::jsonb,
        v_draft.title, v_draft.description, v_draft.category, v_draft.specifications, v_draft.resources
    )
    returning * into v_revision;

    insert into public.revision_media (revision_id, storage_path, display_order, alt_text, is_cover)
    select v_revision.id, pm.storage_path, pm.display_order, pm.alt_text, pm.id = v_draft.cover_media_id
    from public.project_media pm
    where pm.draft_id = p_draft_id;

    return v_build;
end;
$$;

-- 2. restore_revision_to_draft() — back to 0005's body, verbatim ---------
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
            user_id, title, description, category, specifications, resources, published_build_id
        )
        values (
            v_build.user_id, v_revision.snapshot_title, v_revision.snapshot_description,
            v_revision.category, v_revision.specifications, v_revision.resources, v_build.id
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
                resources = v_revision.resources
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

-- 3. Drop everything else 0035 added ------------------------------------
alter table public.profiles
    drop constraint if exists profiles_building_since_year_range_check;

alter table public.profiles
    drop column if exists building_since_year;

drop table if exists public.saved_setup_categories;
drop function if exists public.set_saved_setup_category_normalized_name();

alter table public.build_revisions drop column if exists setup_inventory;
alter table public.builds drop column if exists setup_inventory;
alter table public.project_drafts drop column if exists setup_inventory;

commit;
