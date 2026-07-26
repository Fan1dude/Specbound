-- Migration: 0005_revision_history_and_restore
-- Milestone: 5C (Revision History & Restore)
-- Status: PROPOSED — not yet applied. Depends on 0001-0004 being applied
-- first (0004 fixed the builds.version/progress bug in publish_draft();
-- this migration replaces that function again, additively).
--
-- Purpose:
--   1. Give build_revisions an actual immutable content snapshot. Today it
--      only has a changelog-style title/description (the "what changed"
--      note passed to publish_draft()) plus version/progress/image_url —
--      there is no per-revision record of the project's title,
--      description, category, specifications, or resources as they stood
--      at that publish. builds.specifications is the only trace, and it's
--      overwritten on every republish, so v1.0's specifications can't be
--      recovered once v1.1 is published. New columns:
--        - snapshot_title, snapshot_description: the project's actual
--          title/description at publish time. Named "snapshot_" rather
--          than reusing title/description, because those columns already
--          have an established, different meaning (the Project Log
--          changelog entry's own headline/note — see renderTimeline.js)
--          that this migration does not change.
--        - category, specifications, resources: not represented anywhere
--          on build_revisions before this.
--      publish_draft() is updated (CREATE OR REPLACE, not a new function)
--      to populate all five from the draft on every future publish.
--      Revisions published before this migration will have these fields
--      empty — there is nothing to backfill from, since this data was
--      never captured. The revision-detail UI shows an explicit "not
--      recorded for this revision" notice for those rather than silently
--      falling back to the build's current data.
--
--   2. restore_revision_to_draft(p_revision_id, p_expected_draft_updated_at):
--      a SECURITY DEFINER function that seeds the draft linked to a
--      build with an older revision's snapshot, so the owner can edit and
--      republish it through the normal publish_draft() path. Requires
--      project_drafts.published_build_id to be unique per build (added
--      below) so "the draft linked to this build" is unambiguous.
--      Restoring never writes to build_revisions or revision_media.
--
-- Preflight safety check (required before the unique index): if any build
-- already has more than one draft pointing at it via published_build_id,
-- creating the unique index would fail anyway, but with an opaque
-- constraint-violation error. This migration checks explicitly first and
-- raises a clear, actionable exception instead — and deliberately does
-- NOT delete, merge, or auto-pick between duplicates. If it fails here,
-- run this query to see exactly what's duplicated before deciding how to
-- resolve it by hand:
--
--   select published_build_id, array_agg(id) as draft_ids, array_agg(updated_at) as updated_ats
--   from public.project_drafts
--   where published_build_id is not null
--   group by published_build_id
--   having count(*) > 1;
--
-- Touches: build_revisions (5 new columns), project_drafts (new unique
-- index), publish_draft() (replaced), adds restore_revision_to_draft().
--
-- Rollback: see 0005_revision_history_and_restore_rollback.sql in this
-- folder.

begin;

-- 0. Preflight: fail clearly rather than let the unique index creation
--    below fail opaquely, and never resolve duplicates automatically.
do $$
declare
    v_duplicate_count integer;
begin
    select count(*) into v_duplicate_count
    from (
        select published_build_id
        from public.project_drafts
        where published_build_id is not null
        group by published_build_id
        having count(*) > 1
    ) dupes;

    if v_duplicate_count > 0 then
        raise exception
            'Found % build(s) with more than one draft linked via published_build_id. This migration will not delete, merge, or choose between them automatically — resolve by hand first. See the query in this migration''s header comment to list the duplicates.',
            v_duplicate_count;
    end if;
end $$;

-- 1. build_revisions: immutable content snapshot -------------------------
alter table public.build_revisions
    add column snapshot_title text not null default '',
    add column snapshot_description text not null default '',
    add column category text,
    add column specifications jsonb not null default '{}'::jsonb,
    add column resources jsonb not null default '[]'::jsonb;

-- 2. project_drafts: at most one draft per published build ----------------
create unique index project_drafts_published_build_id_unique_idx
    on public.project_drafts (published_build_id)
    where published_build_id is not null;

-- 3. publish_draft(): now also snapshots title/description/category/
--    specifications/resources into every new revision -------------------
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
        -- signed URL first.
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

-- 4. restore_revision_to_draft(): seeds the draft linked to a build with
--    an older revision's snapshot ------------------------------------------
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
            user_id, title, description, category, specifications, resources, published_build_id
        )
        values (
            v_build.user_id, v_revision.snapshot_title, v_revision.snapshot_description,
            v_revision.category, v_revision.specifications, v_revision.resources, v_build.id
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
                resources = v_revision.resources
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

revoke all on function public.restore_revision_to_draft(uuid, timestamptz) from public;
grant execute on function public.restore_revision_to_draft(uuid, timestamptz) to authenticated;

commit;
