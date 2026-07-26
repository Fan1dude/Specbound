-- Migration: 0004_fix_publish_draft_builds_columns
-- Milestone: 5A (Publishing) — correction
-- Status: PROPOSED — not yet applied.
--
-- 0002_publish_draft_and_visibility.sql was run against the real database
-- and its DDL succeeded (builds.visibility, revision_media, the RLS
-- policies, and publish_draft() itself were all created fine — CREATE
-- FUNCTION doesn't validate column references inside the function body).
-- The bug only surfaced at call time: publish_draft() referenced
-- builds.version and builds.progress, neither of which exists on the real
-- builds table. Confirmed against the actual schema via
-- information_schema.columns — see project chat history for the query and
-- output. Real columns: builds has no version/progress at all (only
-- build_revisions does); builds.specifications and builds.metadata exist
-- and were correctly referenced already.
--
-- Per this project's migration convention, 0002 already applied is left
-- as-is (accurate history of what actually ran, bug included) rather than
-- edited in place. This migration is the correction: a CREATE OR REPLACE
-- of publish_draft() only. No schema objects change.
--
-- Fixes:
--   - builds insert/update no longer reference version or progress.
--   - Republish's version auto-increment now reads the most recent
--     existing build_revisions.version for this build (the only place
--     version actually lives), instead of builds.version.
--   - build_revisions.progress is always inserted as 0 — there is no
--     "current progress" source now that builds doesn't carry it, and
--     progress-tracking is out of scope for the doc-first publish flow
--     (see continue.js's retirement in the prior round).
--   - update_type now uses 'documentation', a value already used
--     elsewhere in this app's UI (continue.html's update-type dropdown),
--     instead of the invented 'initial_publish'/'update' strings, which
--     were unverified against whatever constraint (if any) exists on that
--     column.
--   - attachments now defaults its literal to '[]'::jsonb, matching the
--     column's own declared default shape, instead of '{}'::jsonb.
--
-- Touches: public.publish_draft() only — no table/column changes.
--
-- Rollback: see 0004_fix_publish_draft_builds_columns_rollback.sql in this
-- folder (restores 0002's original, buggy function body — rollback undoes
-- the fix, it does not undo the underlying bug).

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
        -- signed URL first. Card rendering (BlueprintCard, Explore,
        -- Workshop) is updated for this separately in Milestone 5B.
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

        update public.builds
            set title = v_draft.title,
                description = v_draft.description,
                category = v_draft.category,
                image_url = v_cover_path,
                specifications = v_draft.specifications,
                updated_at = now()
            where id = v_build.id
            returning * into v_build;

        v_revision_title := coalesce(nullif(trim(p_publish_notes), ''), 'Documentation update');
    end if;

    -- Immutable revision log entry ----------------------------------------
    -- progress is always 0: there is no "current progress" source now that
    -- builds doesn't carry it, and progress-tracking is out of scope for
    -- this doc-first publish flow.
    insert into public.build_revisions (
        build_id, user_id, title, description, version,
        progress, image_url, update_type, hours_worked, milestone, attachments
    )
    values (
        v_build.id, v_draft.user_id, v_revision_title,
        coalesce(nullif(trim(p_publish_notes), ''), ''),
        v_version, 0, v_cover_path,
        'documentation',
        null, false, '[]'::jsonb
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

commit;
