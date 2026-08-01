-- Migration: 0020_components_catalog
-- Milestone: 19 — Structured Parts Catalog & Import Architecture
-- Status: PROPOSED — not yet applied. Depends on 0001-0019 being applied
-- first.
--
-- Full design: docs/milestones/MILESTONE_19_PARTS_CATALOG_ARCHITECTURE.md.
-- This file ships the catalog's moderator-role infrastructure and the
-- components table itself together, in that order, because the table's
-- insert policy references is_catalog_moderator() below — a forward
-- reference across files isn't possible, so catalog_moderators can't be
-- deferred to a later migration the way an earlier draft of this plan
-- assumed.
--
--   catalog_moderators / is_catalog_moderator(): the first admin-role
--   concept in this app, deliberately scoped to this one subsystem (not
--   a general "is_admin" flag). is_catalog_moderator() is SECURITY
--   DEFINER so other tables' RLS policies can call it without needing
--   their own SELECT policy on catalog_moderators — a normal
--   authenticated client never reads that table directly.
--
--   components: deliberately NOT built on top of the search_components()
--   RPC that js/repositories/componentRepository.js used to call (used
--   by ComponentAutocomplete.js, wired only to PC-build CPU/GPU fields)
--   — a full repo-wide grep of supabase/migrations/ found no migration
--   file defining that RPC or any backing table. Its live schema can't
--   be verified or safely assumed from this environment (anon-key only,
--   no DB/CLI access), so this migration creates a fresh, tracked table
--   instead.
--
--   technology_id and field_key are free text, not foreign keys or an
--   enum — the source of truth for valid values is
--   js/config/technologies/*.js, which has no database representation.
--   See docs/milestones/MILESTONE_19_PARTS_CATALOG_ARCHITECTURE.md §4.5
--   for the governance mechanism that keeps a future config rename from
--   silently orphaning rows here.
--
--   normalized_name is a generated, stored column — lowercase with
--   everything except letters/digits stripped, the same conservative
--   alphanumeric-only normalization already established client-side in
--   js/utils/fuzzySearch.js's normalizeCompact, reused here rather than
--   reinvented. The unique index is on normalized_name (not
--   lower(canonical_name), as an earlier draft of this migration had
--   it), so "RTX 4080" / "RTX-4080" / "rtx4080" collapse to one row
--   while "RTX 4080 Ti" stays distinct — punctuation/whitespace are
--   stripped, real tokens are not.
--
--   Write access: unlike an earlier draft of this migration, authenticated
--   users may NOT insert directly into components. Only a
--   catalog_moderators-flagged user may. Ordinary users still contribute
--   new catalog entries — via component_submissions, added in
--   0022_component_submissions.sql — but a submission only ever becomes a
--   real components row through catalog_moderators-gated review. This
--   closes the moderation gap the first draft of this plan flagged as an
--   accepted risk ("any signed-in user can insert junk/spam rows with no
--   review step"). There is still no UPDATE/DELETE policy for anyone —
--   correcting a bad catalog entry remains a manual, curated operation.
--
--   SQL/security audit pass (2026-07-31): added non-empty checks on
--   technology_id/field_key/canonical_name (an all-whitespace or empty
--   value would otherwise pass the not-null constraint and normalize to
--   an empty string, silently colliding with any other empty entry in
--   the same slot), and explicit revoke-from-public/grant-to-authenticated
--   on is_catalog_moderator() rather than relying on Postgres's default
--   PUBLIC execute grant. See
--   docs/milestones/MILESTONE_19_SQL_SECURITY_AUDIT.md for the full audit.
--
-- Touches: none (three new objects only: catalog_moderators,
-- is_catalog_moderator(), components). Reuses the existing
-- public.set_updated_at() trigger function from 0001 — no new trigger
-- function beyond is_catalog_moderator().
--
-- Rollback: see 0020_components_catalog_rollback.sql in supabase/rollbacks/.

begin;

create table public.catalog_moderators (
    user_id uuid primary key references auth.users(id) on delete cascade,
    granted_by uuid references auth.users(id) on delete set null,
    granted_at timestamptz not null default now()
);

alter table public.catalog_moderators enable row level security;

-- No SELECT/INSERT/UPDATE/DELETE policy for anyone — this table is read
-- only through is_catalog_moderator() below (SECURITY DEFINER bypasses
-- RLS for its own query), and granting/revoking moderator status is a
-- manual operation for now (see the architecture doc's Risks section).
-- With RLS enabled and no policy, all direct client access is denied.

create function public.is_catalog_moderator(uid uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
    select exists (
        select 1 from public.catalog_moderators where user_id = uid
    );
$$;

-- Explicit grants, not left to ambient defaults — SQL/audit review flagged
-- that a newly created function's EXECUTE privilege is granted to PUBLIC
-- (including the anon role) unless revoked, which would let an
-- unauthenticated caller probe arbitrary user ids for moderator status.
-- Only authenticated needs this: it's called from RLS policies evaluated
-- as that role (components' insert policy, component_submissions' select
-- policy in 0022), and from within the SECURITY DEFINER functions in
-- 0022, which execute as the function owner regardless of grants.
revoke execute on function public.is_catalog_moderator(uuid) from public;
grant execute on function public.is_catalog_moderator(uuid) to authenticated;

create table public.components (
    id uuid primary key default gen_random_uuid(),
    technology_id text not null
        check (char_length(trim(technology_id)) > 0),
    field_key text not null
        check (char_length(trim(field_key)) > 0),
    canonical_name text not null
        check (char_length(trim(canonical_name)) > 0),
    normalized_name text generated always as (
        regexp_replace(lower(canonical_name), '[^a-z0-9]', '', 'g')
    ) stored,
    manufacturer text,
    metadata jsonb not null default '{}'::jsonb,
    created_by uuid references auth.users(id) on delete set null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create unique index components_technology_field_normalized_idx
    on public.components (technology_id, field_key, normalized_name);

create index components_technology_field_idx
    on public.components (technology_id, field_key);

create trigger set_components_updated_at
    before update on public.components
    for each row
    execute function public.set_updated_at();

alter table public.components enable row level security;

-- Catalog data isn't sensitive or user-scoped — readable by anyone,
-- signed in or not, same as public build data.
create policy "Components catalog is readable by everyone" on public.components
    for select using (true);

-- Only a catalog moderator may create a canonical row directly. Ordinary
-- authenticated users contribute via component_submissions instead (see
-- 0022_component_submissions.sql) — this policy replaces the earlier
-- draft's "any authenticated user may insert" policy.
create policy "Catalog moderators can add catalog components" on public.components
    for insert
    to authenticated
    with check (public.is_catalog_moderator(auth.uid()));

commit;
