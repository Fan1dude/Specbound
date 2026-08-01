-- Rollback for: 0004_fix_publish_draft_builds_columns
--
-- Restores publish_draft() to its exact pre-0004 definition (the version
-- originally shipped in 0002_publish_draft_and_visibility.sql). That
-- version references builds.version and builds.progress, which do not
-- exist on the real builds table — restoring it un-does the fix, not the
-- bug. Only run this if you're intentionally reverting past the point
-- where the bug was found.

begin;

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
    v_version_match text[];
    v_progress integer;
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

        v_progress := 0;

        insert into public.builds (
            user_id, title, slug, description, category,
            status, image_url, version, progress, specifications
        )
        values (
            v_draft.user_id, v_draft.title, v_slug, v_draft.description, v_draft.category,
            'planning', v_cover_path, v_version, v_progress, v_draft.specifications
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

        v_progress := coalesce(v_build.progress, 0);

        if p_version_label is not null and trim(p_version_label) <> '' then
            v_version := trim(p_version_label);
        else
            v_version_match := regexp_match(coalesce(v_build.version, ''), '^v?(\d+)\.(\d+)$');

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
                version = v_version,
                specifications = v_draft.specifications,
                updated_at = now()
            where id = v_build.id
            returning * into v_build;

        v_revision_title := coalesce(nullif(trim(p_publish_notes), ''), 'Documentation update');
    end if;

    insert into public.build_revisions (
        build_id, user_id, title, description, version,
        progress, image_url, update_type, hours_worked, milestone, attachments
    )
    values (
        v_build.id, v_draft.user_id, v_revision_title,
        coalesce(nullif(trim(p_publish_notes), ''), ''),
        v_version, v_progress, v_cover_path,
        case when v_is_first_publish then 'initial_publish' else 'update' end,
        null, false, '{}'::jsonb
    )
    returning * into v_revision;

    insert into public.revision_media (revision_id, storage_path, display_order, alt_text, is_cover)
    select v_revision.id, pm.storage_path, pm.display_order, pm.alt_text, pm.id = v_draft.cover_media_id
    from public.project_media pm
    where pm.draft_id = p_draft_id;

    return v_build;
end;
$$;

revoke all on function public.publish_draft(uuid, text, text) from public;
grant execute on function public.publish_draft(uuid, text, text) to authenticated;

commit;
