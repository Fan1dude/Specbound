-- Migration: 0002_publish_draft_and_visibility
-- Milestone: 5A (Publishing) — schema + publish_draft() SECURITY DEFINER function
-- Status: PROPOSED — not yet applied. Depends on 0001_project_drafts_and_media
-- having already been applied (this migration alters project_drafts and
-- replaces one storage.objects policy created there by exact name).
--
-- Purpose: transactional draft -> build publishing.
--
--   - project_drafts.published_build_id links a draft to the build it
--     publishes to. Null = never published. Set once on first publish,
--     then reused on every republish.
--   - builds.visibility gates public listing. NOT NULL + DEFAULT 'public'
--     backfills every already-live build to 'public' as part of adding the
--     column, so nothing currently visible changes as a side effect.
--   - revision_media snapshots project_media into each build_revision at
--     publish time. is_cover is a boolean on the row itself (not a FK from
--     build_revisions) — the cover is metadata belonging to the gallery
--     snapshot, which avoids a circular reference and lets publish_draft()
--     write revision_media without build_revisions needing to already know
--     which media row is the cover.
--   - build_revisions and revision_media become effectively immutable:
--     RLS is locked down so no direct authenticated/anon write is possible
--     on builds, build_revisions, or revision_media. Every write goes
--     through publish_draft(), a SECURITY DEFINER function (owned by a
--     BYPASSRLS role, per standard Supabase setup) that also re-validates
--     draft readiness server-side — mirroring js/services/draftValidation.js
--     — and verifies the referenced cover media row actually belongs to the
--     draft being published.
--   - Storage: the owner-delete policy from 0001 is replaced with one that
--     additionally blocks deleting a project-images file that a published
--     revision still references, and two new read policies are added
--     (avatars/*, and any path referenced by revision_media) so that
--     createSignedUrl() — which evaluates RLS SELECT the same way a normal
--     fetch does, independent of the bucket's public/private flag — can
--     succeed for anonymous visitors browsing public pages.
--
--   Deliberately NOT included: flipping the project-images bucket to
--   private. profiles.avatar_url, builds.image_url, and
--   build_revisions.image_url already hold live public URLs from prior
--   milestones; flipping the bucket now would break every one of them
--   immediately. That flip is a separate, later migration, once every read
--   path (avatars, gallery, cards, build pages) is confirmed working
--   against signed URLs and existing stored URLs have been dealt with.
--
-- Touches: project_drafts (new column), builds (new column + RLS rewrite),
-- build_revisions (RLS rewrite), storage.objects (one replaced policy, two
-- new policies). Adds: revision_media, publish_draft().
--
-- Rollback: see 0002_publish_draft_and_visibility_rollback.sql in supabase/rollbacks/.

begin;

-- 1. project_drafts: link to the build it publishes -----------------------
alter table public.project_drafts
    add column published_build_id uuid references public.builds(id) on delete set null;

-- 2. builds: visibility ----------------------------------------------------
alter table public.builds
    add column visibility text not null default 'public'
        check (visibility in ('public', 'private'));

-- 3. revision_media: immutable gallery snapshot ----------------------------
create table public.revision_media (
    id uuid primary key default gen_random_uuid(),
    revision_id uuid not null references public.build_revisions(id) on delete cascade,
    storage_path text not null,
    display_order integer not null default 0,
    alt_text text not null default '',
    is_cover boolean not null default false,
    created_at timestamptz not null default now()
);

create index revision_media_revision_id_display_order_idx
    on public.revision_media (revision_id, display_order);

-- At most one cover per revision.
create unique index revision_media_one_cover_per_revision_idx
    on public.revision_media (revision_id)
    where is_cover;

alter table public.revision_media enable row level security;

-- 4. RLS lockdown: builds, build_revisions ---------------------------------
-- publish_draft() is SECURITY DEFINER (see section 6) and runs with the
-- privileges of its owning role, which bypasses RLS under standard Supabase
-- setup — so it writes to these tables regardless of the policies below.
-- These policies only govern direct client access (anon/authenticated),
-- which becomes read-only here: every write must go through publish_draft().
--
-- Drop-all-then-recreate rather than targeted DROP POLICY: there is no DB
-- introspection access from the implementation environment, so the exact
-- names of whatever policies currently exist on these two tables aren't
-- known here. This finds and drops every existing policy on both tables,
-- whatever they're named, before the fresh policies below are added, so the
-- end state is deterministic regardless of history. Review the NOTICEs this
-- prints when running it in the SQL editor to confirm what was dropped.
do $$
declare
    pol record;
begin
    for pol in
        select schemaname, tablename, policyname
        from pg_policies
        where schemaname = 'public'
          and tablename in ('builds', 'build_revisions')
    loop
        execute format('drop policy %I on %I.%I', pol.policyname, pol.schemaname, pol.tablename);
        raise notice 'Dropped policy % on %.%', pol.policyname, pol.schemaname, pol.tablename;
    end loop;
end $$;

alter table public.builds enable row level security;
alter table public.build_revisions enable row level security;

create policy "Public builds are readable by everyone, private builds by their owner" on public.builds
    for select using (visibility = 'public' or user_id = auth.uid());

create policy "Revisions are readable when their build is readable" on public.build_revisions
    for select using (exists (
        select 1 from public.builds b
        where b.id = build_revisions.build_id
        and (b.visibility = 'public' or b.user_id = auth.uid())
    ));

create policy "Revision media is readable when its revision is readable" on public.revision_media
    for select using (exists (
        select 1 from public.build_revisions r
        join public.builds b on b.id = r.build_id
        where r.id = revision_media.revision_id
        and (b.visibility = 'public' or b.user_id = auth.uid())
    ));

-- No insert/update/delete policies on any of the three: with RLS enabled
-- and no matching policy, direct client writes are denied outright.

-- 5. Storage: delete protection + signed-URL read support ------------------
-- 5a. Replace the owner-delete policy from 0001 with one that also blocks
--     deleting a file a published revision still references. A draft owner
--     can still freely delete their own draft's project_media rows/files —
--     just not once that same physical file is part of an immutable
--     published snapshot.
drop policy "Owners can delete their draft media files" on storage.objects;

create policy "Owners can delete their draft media files" on storage.objects
    for delete using (
        bucket_id = 'project-images'
        and (storage.foldername(name))[1] = 'projects'
        and exists (
            select 1 from public.project_drafts d
            where d.id::text = (storage.foldername(name))[2]
            and d.user_id = auth.uid()
        )
        and not exists (
            select 1 from public.revision_media rm
            where rm.storage_path = storage.objects.name
        )
    );

-- 5b. Anon/authenticated read access for avatars and published gallery
--     files. Needed for createSignedUrl() to succeed for visitors browsing
--     public pages: signing a URL evaluates RLS SELECT the same as a normal
--     authenticated fetch, regardless of the bucket's public/private flag
--     (only the /object/public/... fast-path endpoint ignores RLS, and that
--     endpoint stops working the moment the bucket is flipped private).
create policy "Anyone can read avatar files" on storage.objects
    for select using (
        bucket_id = 'project-images'
        and (storage.foldername(name))[1] = 'avatars'
    );

create policy "Anyone can read files referenced by a published revision" on storage.objects
    for select using (
        bucket_id = 'project-images'
        and exists (
            select 1 from public.revision_media rm
            where rm.storage_path = storage.objects.name
        )
    );

-- 6. publish_draft(): the only path that writes builds/build_revisions/
--    revision_media --------------------------------------------------------
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

        v_progress := 0;

        -- image_url is stored as a storage path, not a ready URL — reading
        -- it as a display URL requires resolving a signed URL first. Card
        -- rendering (BlueprintCard, Explore, Workshop) is updated for this
        -- separately in Milestone 5B.
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

        -- No version input exists in the editor UI (yet) — an explicit
        -- p_version_label always wins, otherwise republishing auto-bumps
        -- the minor version (v1.0 -> v1.1 -> v1.2, ...) so successive
        -- publishes are distinguishable without requiring one.
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

    -- Immutable revision log entry ----------------------------------------
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
