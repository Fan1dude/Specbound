-- Migration: 0020_components_catalog
-- Milestone: 19 — Structured Parts Catalog & Import Architecture
-- Status: PROPOSED — never successfully applied anywhere. Depends on
-- 0001-0019 being applied first.
--
-- Full design: docs/milestones/MILESTONE_19_PARTS_CATALOG_ARCHITECTURE.md.
--
-- REWRITTEN (production-compatibility pass): the original version of
-- this file did an unconditional `create table public.components`. A
-- real `db push` against the actual production project stopped safely
-- at this exact migration — production already has a `public.components`
-- table, populated with 9 real rows, that predates this migration
-- entirely (columns: id, technology_id, component_type, canonical_name,
-- manufacturer, metadata, created_at, updated_at, canonical_key; RLS
-- enabled with a public SELECT policy; its own indexes/unique
-- constraints; and a live `search_components(text,text,text,integer)`
-- RPC with no migration file anywhere in this repo — same "can't verify
-- from here" situation this file's own original header already noted
-- for that RPC). An unconditional CREATE TABLE can never coexist with
-- that — Postgres just refuses ("relation already exists"), which is
-- exactly the safe failure `db push` hit.
--
-- This version makes 0020 additive and idempotent instead, so the SAME
-- file produces the SAME final schema on both:
--   (a) a completely fresh database (nothing exists yet), and
--   (b) production's legacy database (components/component_aliases
--       already exist, populated).
--
-- Compatibility strategy for public.components:
--   - technology_id, component_type, canonical_name, manufacturer,
--     metadata, created_at, updated_at, canonical_key are NEVER
--     dropped, renamed, or redefined. Every statement touching them is
--     additive-only (ADD COLUMN IF NOT EXISTS, which is a no-op if the
--     column is already there) or purely read-only (backfill queries
--     guarded with `where ... is null`, so an already-populated legacy
--     cell is never overwritten).
--   - field_key and normalized_name are the columns this app's current
--     code (js/repositories/componentRepository.js) actually queries.
--     field_key is backfilled from component_type — the same concept,
--     the app's own name for it (confirmed: the production
--     compatibility audit found technology_id/component_type/
--     canonical_key already free of blanks and normalization
--     collisions, so a straight copy is safe). normalized_name is
--     backfilled by recomputing the exact same normalization
--     canonical_key was always meant to hold — the audit confirms all 9
--     existing canonical_key values already match it, so this
--     recomputation reproduces canonical_key's own values, not new
--     ones.
--   - Deliberately NOT a generated column this time (the original
--     version made normalized_name `generated always as (...)
--     stored`). canonical_key already exists on the legacy table as an
--     ordinary column with real data — Postgres cannot convert an
--     existing plain column into a generated one via ALTER, only the
--     reverse. Making normalized_name a NEW generated column while
--     canonical_key stays plain would leave the two columns different
--     *kinds* depending on which install path created them, which is
--     exactly the kind of fresh-vs-legacy schema drift this migration
--     exists to eliminate. Both normalized_name and canonical_key are
--     therefore ordinary columns on every install, kept equal by one
--     trigger (sync_component_legacy_fields, below) that runs on every
--     future insert/update — the same mechanism, the same column kind,
--     on both paths.
--   - created_by is new and always nullable — a legacy row genuinely
--     has no recorded creator, and that's a legitimate value, not a
--     gap to force-fill.
--   - Constraints (NOT NULL on field_key, non-empty CHECKs, the
--     technology_id+field_key+normalized_name unique index) are added
--     only after the backfill above runs, per the compatibility audit:
--     "no blank component normalized names" and "no component
--     normalization collisions" were confirmed for the existing 9 rows
--     before this migration was written, so adding these constraints
--     now cannot fail against real data. component_type and
--     canonical_key themselves get no NEW constraints here — they keep
--     whatever nullability/uniqueness production already gave them;
--     this migration only ever adds to that, never re-validates or
--     tightens it.
--
-- catalog_moderators / is_catalog_moderator(): unchanged from the
-- original version of this file — genuinely new on every install path,
-- nothing production-legacy to preserve here. The first admin-role
-- concept in this app, deliberately scoped to this one subsystem (not a
-- general "is_admin" flag). is_catalog_moderator() is SECURITY DEFINER
-- so other tables' RLS policies can call it without needing their own
-- SELECT policy on catalog_moderators.
--
-- search_components(text,text,text,integer): the pre-existing legacy
-- RPC is not touched by this migration at all — not redefined, not
-- dropped. Every column it could plausibly read (technology_id,
-- component_type, canonical_name, manufacturer, metadata,
-- canonical_key, id) is preserved exactly as production already has
-- it, so its behavior is unaffected. This repo has no record of its
-- actual body (confirmed: no migration file anywhere defines it), so
-- redefining it here would mean guessing at behavior this file cannot
-- see — safer to leave it alone entirely, which full column
-- preservation makes possible.
--
-- Touches: public.components (additive columns/constraints/indexes/
-- trigger only — see above), plus the always-new catalog_moderators /
-- is_catalog_moderator().
--
-- Rollback: see 0020_components_catalog_rollback.sql in
-- supabase/rollbacks/. Rewritten the same way this file was — it never
-- drops public.components, on either install path, since on a legacy
-- database that table holds real, pre-existing production data this
-- migration did not create and has no way to distinguish from a
-- freshly-created one.

begin;

create table if not exists public.catalog_moderators (
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

-- Explicit grants, not left to ambient defaults — a newly created
-- function's EXECUTE privilege is granted to PUBLIC (including the
-- anon role) unless revoked, which would let an unauthenticated caller
-- probe arbitrary user ids for moderator status. Only authenticated
-- needs this: it's called from RLS policies evaluated as that role
-- (components' insert policy, component_submissions' select policy in
-- 0022), and from within the SECURITY DEFINER functions in 0022, which
-- execute as the function owner regardless of grants.
revoke execute on function public.is_catalog_moderator(uuid) from public;
grant execute on function public.is_catalog_moderator(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- public.components — additive, compatible with both a fresh database
-- and production's existing, populated legacy table.
-- ---------------------------------------------------------------------

-- Step 1: ensure the table exists at all. A complete no-op on
-- production (the legacy table already exists, so this whole statement
-- does nothing) — this branch only ever actually creates anything on a
-- genuinely fresh database.
create table if not exists public.components (
    id uuid primary key default gen_random_uuid(),
    created_at timestamptz not null default now()
);

-- Step 2: ensure every column this app (and legacy production) needs
-- exists, added unconstrained — constraints come after backfill, below.
-- Each is a no-op for a column that's already there, on either path:
-- technology_id/canonical_name/manufacturer/metadata/updated_at are
-- already on the legacy table and skip silently; field_key/
-- component_type/normalized_name/canonical_key/created_by are new on
-- both paths (legacy never had them, and a fresh install only just
-- created the table above with none of them yet).
alter table public.components add column if not exists technology_id text;
alter table public.components add column if not exists field_key text;
alter table public.components add column if not exists component_type text;
alter table public.components add column if not exists canonical_name text;
alter table public.components add column if not exists normalized_name text;
alter table public.components add column if not exists canonical_key text;
alter table public.components add column if not exists manufacturer text;
alter table public.components add column if not exists metadata jsonb not null default '{}'::jsonb;
alter table public.components add column if not exists created_by uuid references auth.users(id) on delete set null;
alter table public.components add column if not exists updated_at timestamptz not null default now();

-- Step 3: backfill. `where <new column> is null` on every statement —
-- this only ever fills in a genuinely empty cell, never overwrites an
-- existing legacy value (there is nothing to backfill on a fresh
-- install; there are 9 real rows to backfill on production, per the
-- compatibility audit that green-lit this exact approach).
update public.components set field_key = component_type
    where field_key is null and component_type is not null;

-- Mirror direction — covers a hypothetical row written before this
-- migration ever ran (shouldn't exist on either path in practice, but
-- costs nothing to also guard against: a components row this app
-- itself creates always sets field_key, never component_type
-- directly).
update public.components set component_type = field_key
    where component_type is null and field_key is not null;

update public.components set normalized_name = regexp_replace(lower(canonical_name), '[^a-z0-9]', '', 'g')
    where normalized_name is null and canonical_name is not null;

update public.components set canonical_key = regexp_replace(lower(canonical_name), '[^a-z0-9]', '', 'g')
    where canonical_key is null and canonical_name is not null;

-- Step 4: constraints, only now that every row is known-populated.
-- canonical_name/technology_id: production is expected to already
-- satisfy these (a populated catalog implies both), but the check runs
-- for real either way — if some row genuinely violates it, this fails
-- loudly here rather than silently shipping a broken constraint.
alter table public.components alter column technology_id set not null;
alter table public.components alter column field_key set not null;
alter table public.components alter column canonical_name set not null;

do $$
begin
    if not exists (
        select 1 from pg_constraint
        where conrelid = 'public.components'::regclass
          and conname = 'components_technology_id_not_blank'
    ) then
        alter table public.components
            add constraint components_technology_id_not_blank
            check (char_length(trim(technology_id)) > 0);
    end if;

    if not exists (
        select 1 from pg_constraint
        where conrelid = 'public.components'::regclass
          and conname = 'components_field_key_not_blank'
    ) then
        alter table public.components
            add constraint components_field_key_not_blank
            check (char_length(trim(field_key)) > 0);
    end if;

    if not exists (
        select 1 from pg_constraint
        where conrelid = 'public.components'::regclass
          and conname = 'components_canonical_name_not_blank'
    ) then
        alter table public.components
            add constraint components_canonical_name_not_blank
            check (char_length(trim(canonical_name)) > 0);
    end if;
end $$;

-- New unique index this app's findExactComponentMatch() relies on
-- (assumes at most one row per technology+field+normalized-name slot).
-- Safe to add now: the compatibility audit confirmed zero normalization
-- collisions across the existing 9 rows before this migration was
-- written. Does not replace or touch whatever unique constraint
-- production's legacy table already has on component_type/
-- canonical_key — that stays exactly as it is, untouched.
create unique index if not exists components_technology_field_normalized_idx
    on public.components (technology_id, field_key, normalized_name);

create index if not exists components_technology_field_idx
    on public.components (technology_id, field_key);

-- Step 5: keep component_type/canonical_key in sync with field_key/
-- normalized_name for every future write, on both install paths — the
-- same mechanism (not "generated on fresh, plain on legacy") so the
-- two columns can never drift apart no matter which path created them.
-- SECURITY DEFINER only in the sense that it needs no elevated
-- privilege at all (plain trigger, runs with the invoking statement's
-- own already-sufficient privileges) — no "security definer" keyword,
-- matching public.set_updated_at()'s own convention for a trigger that
-- only ever touches the row already being written.
create or replace function public.sync_component_legacy_fields()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
    new.component_type := new.field_key;
    new.canonical_key := regexp_replace(lower(new.canonical_name), '[^a-z0-9]', '', 'g');
    new.normalized_name := new.canonical_key;
    return new;
end;
$$;

drop trigger if exists sync_component_legacy_fields on public.components;
create trigger sync_component_legacy_fields
    before insert or update of field_key, canonical_name on public.components
    for each row
    execute function public.sync_component_legacy_fields();

drop trigger if exists set_components_updated_at on public.components;
create trigger set_components_updated_at
    before update on public.components
    for each row
    execute function public.set_updated_at();

alter table public.components enable row level security;

-- Catalog data isn't sensitive or user-scoped — readable by anyone,
-- signed in or not, same as public build data. Production's legacy
-- table is described as already having "a public SELECT policy" under
-- some other name from before this repo's migration tracking began —
-- that policy is left completely alone (this only ever drops/recreates
-- a policy under this exact name), so on production this is a second,
-- redundant, equally-permissive policy alongside the original; RLS
-- policies are OR-combined, so having two that both allow
-- `using (true)` changes nothing observable. On a fresh install this is
-- the only SELECT policy that exists.
drop policy if exists "Components catalog is readable by everyone" on public.components;
create policy "Components catalog is readable by everyone" on public.components
    for select using (true);

-- Only a catalog moderator may create a canonical row directly.
-- catalog_moderators is new on every install path (see above), so this
-- policy is unambiguously additive on production too — there was no
-- prior insert path for any client role to begin with.
drop policy if exists "Catalog moderators can add catalog components" on public.components;
create policy "Catalog moderators can add catalog components" on public.components
    for insert
    to authenticated
    with check (public.is_catalog_moderator(auth.uid()));

commit;
