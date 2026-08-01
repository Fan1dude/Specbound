-- Migration: 0006_unpublish
-- Milestone: 5D (Unpublish)
-- Status: PROPOSED — not yet applied. Depends on 0001-0005 being applied
-- first.
--
-- Purpose:
--   1. set_build_visibility(p_build_id, p_visibility): a SECURITY DEFINER
--      function that is the only way to change builds.visibility going
--      forward (builds has no direct-client write policies at all, same
--      as build_revisions/revision_media — see 0002). Ownership-checked,
--      validates the value, a single UPDATE. Deliberately touches nothing
--      else: no build_revisions insert (visibility changes are not
--      content changes and must not create a revision), no
--      project_drafts, no revision_media. Does not bump builds.updated_at
--      — that column tracks content changes, and getNewestBuilds()/
--      getMyBuilds() sort by it; bumping it on a visibility flip would
--      make an untouched project jump to the top of "Latest Builds" on
--      republish for no content reason.
--
--   2. publish_draft() updated (CREATE OR REPLACE, not a new function) so
--      that publishing is what makes a project live: republishing an
--      unpublished (visibility='private') build now sets it back to
--      'public' as part of the same UPDATE that refreshes its content.
--      This is a deliberate behavioral decision — "Public → Unpublish →
--      Edit draft → Publish → Public again" with a single Publish action,
--      not a separate publish-then-republish-visibility step. First
--      publish is unaffected (builds.visibility already defaults to
--      'public' on insert).
--
-- The application-level query filters this milestone also adds
-- (getNewestBuilds/getFeaturedBuilds/getProfileBuilds now filter to
-- visibility = 'public') are pure JS repository changes — no schema
-- involved, not part of this migration.
--
-- Touches: publish_draft() (replaced). Adds set_build_visibility().
--
-- Rollback: see 0006_unpublish_rollback.sql in supabase/rollbacks/.

begin;

-- 1. publish_draft(): republishing now also restores visibility='public' --
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

revoke all on function public.publish_draft(uuid, text, text) from public;
grant execute on function public.publish_draft(uuid, text, text) to authenticated;

-- 2. set_build_visibility(): the only direct way to change visibility ----
-- (publish_draft() also sets it to 'public' as a side effect of
-- publishing, per above — this function is what the editor's Unpublish
-- action calls, and is written generically enough to support either
-- direction even though the current UI only ever calls it with
-- 'private').
create or replace function public.set_build_visibility(
    p_build_id uuid,
    p_visibility text
)
returns public.builds
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_build public.builds;
begin
    if p_visibility not in ('public', 'private') then
        raise exception 'Invalid visibility value.';
    end if;

    select * into v_build from public.builds where id = p_build_id;

    if v_build is null then
        raise exception 'Build not found.';
    end if;

    if v_build.user_id <> auth.uid() then
        raise exception 'Only the build owner can change its visibility.';
    end if;

    update public.builds
        set visibility = p_visibility
        where id = p_build_id
        returning * into v_build;

    return v_build;
end;
$$;

revoke all on function public.set_build_visibility(uuid, text) from public;
grant execute on function public.set_build_visibility(uuid, text) to authenticated;

commit;
