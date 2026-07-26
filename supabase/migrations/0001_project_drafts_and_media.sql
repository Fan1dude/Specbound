-- Migration: 0001_project_drafts_and_media
-- Milestone: 4 (Project Editor) — Option A draft architecture
-- Status: PROPOSED — not yet applied. Written into the repo for a durable
-- record; run manually via the Supabase SQL editor after review.
--
-- Purpose: private draft editing state (project_drafts) and its media
-- ownership/metadata (project_media), fully separate from the public
-- `builds` table. Nothing here touches `builds`, `build_revisions`,
-- `profiles`, or any existing table, column, or policy.
--
-- Includes a reusable public.set_updated_at() trigger function so
-- `updated_at` is maintained by the database on every UPDATE, not by
-- application code remembering to set it. Attached to project_drafts here;
-- reusable by any future table with the same column.
--
-- Rollback: see 0001_project_drafts_and_media_rollback.sql in this folder.

begin;

create extension if not exists pgcrypto;

-- 1. project_drafts ----------------------------------------------------
create table public.project_drafts (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    title text not null default '',
    description text not null default '',
    category text not null,
    specifications jsonb not null default '{}'::jsonb,
    resources jsonb not null default '[]'::jsonb,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create index project_drafts_user_id_updated_at_idx
    on public.project_drafts (user_id, updated_at desc);

-- 1a. Reusable updated_at trigger -----------------------------------------
-- Generic on purpose: any table with an `updated_at` column can attach this
-- via its own `create trigger ... execute function public.set_updated_at()`,
-- rather than each new table inventing its own version. Runs with the
-- invoking user's own privileges (no reason to elevate — it only touches
-- the row already being written by that same statement) and pins
-- search_path defensively per standard function-security practice.
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

create trigger set_project_drafts_updated_at
    before update on public.project_drafts
    for each row
    execute function public.set_updated_at();

-- 2. project_media -------------------------------------------------------
create table public.project_media (
    id uuid primary key default gen_random_uuid(),
    draft_id uuid not null references public.project_drafts(id) on delete cascade,
    storage_path text not null,
    display_order integer not null default 0,
    alt_text text not null default '',
    created_at timestamptz not null default now()
);

create index project_media_draft_id_display_order_idx
    on public.project_media (draft_id, display_order);

-- 3. Resolve the circular reference (draft -> cover media -> draft) ------
alter table public.project_drafts
    add column cover_media_id uuid references public.project_media(id) on delete set null;

-- 4. Row Level Security ---------------------------------------------------
alter table public.project_drafts enable row level security;
alter table public.project_media enable row level security;

-- 5. project_drafts policies: owner-only, full stop -----------------------
create policy "Owners can select their drafts" on public.project_drafts
    for select using (auth.uid() = user_id);

create policy "Owners can insert their drafts" on public.project_drafts
    for insert with check (auth.uid() = user_id);

create policy "Owners can update their drafts" on public.project_drafts
    for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "Owners can delete their drafts" on public.project_drafts
    for delete using (auth.uid() = user_id);

-- 6. project_media policies: ownership via parent draft --------------------
create policy "Owners can select their draft media" on public.project_media
    for select using (exists (
        select 1 from public.project_drafts d
        where d.id = project_media.draft_id and d.user_id = auth.uid()
    ));

create policy "Owners can insert their draft media" on public.project_media
    for insert with check (exists (
        select 1 from public.project_drafts d
        where d.id = project_media.draft_id and d.user_id = auth.uid()
    ));

create policy "Owners can update their draft media" on public.project_media
    for update using (exists (
        select 1 from public.project_drafts d
        where d.id = project_media.draft_id and d.user_id = auth.uid()
    ));

create policy "Owners can delete their draft media" on public.project_media
    for delete using (exists (
        select 1 from public.project_drafts d
        where d.id = project_media.draft_id and d.user_id = auth.uid()
    ));

-- 7. Storage policies: projects/{draftId}/... under the existing
--    project-images bucket. Split per-operation (not FOR ALL) so each is
--    individually auditable and droppable.
--    IMPORTANT: read section 3 of the accompanying checklist before running
--    this — confirm it doesn't duplicate or conflict with whatever policy
--    already governs uploads to this bucket (avatars, build cover images).
create policy "Owners can select their draft media files" on storage.objects
    for select using (
        bucket_id = 'project-images'
        and (storage.foldername(name))[1] = 'projects'
        and exists (
            select 1 from public.project_drafts d
            where d.id::text = (storage.foldername(name))[2]
            and d.user_id = auth.uid()
        )
    );

create policy "Owners can insert their draft media files" on storage.objects
    for insert with check (
        bucket_id = 'project-images'
        and (storage.foldername(name))[1] = 'projects'
        and exists (
            select 1 from public.project_drafts d
            where d.id::text = (storage.foldername(name))[2]
            and d.user_id = auth.uid()
        )
    );

create policy "Owners can update their draft media files" on storage.objects
    for update using (
        bucket_id = 'project-images'
        and (storage.foldername(name))[1] = 'projects'
        and exists (
            select 1 from public.project_drafts d
            where d.id::text = (storage.foldername(name))[2]
            and d.user_id = auth.uid()
        )
    );

create policy "Owners can delete their draft media files" on storage.objects
    for delete using (
        bucket_id = 'project-images'
        and (storage.foldername(name))[1] = 'projects'
        and exists (
            select 1 from public.project_drafts d
            where d.id::text = (storage.foldername(name))[2]
            and d.user_id = auth.uid()
        )
    );

commit;
