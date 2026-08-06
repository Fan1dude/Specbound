-- Migration: 0021_component_aliases
-- Milestone: 19 — Structured Parts Catalog & Import Architecture
-- Status: PROPOSED — never successfully applied anywhere. Depends on
-- 0020 (public.components).
--
-- Full design: docs/milestones/MILESTONE_19_PARTS_CATALOG_ARCHITECTURE.md §4.2.
--
-- REWRITTEN (production-compatibility pass, same reasoning as 0020's
-- own header): production already has a `public.component_aliases`
-- table, populated with 6 real rows, that predates this migration
-- (columns: id, component_id, alias, created_at, alias_key). Same
-- unconditional-CREATE-TABLE problem 0020 had, same fix — every
-- statement below is additive/idempotent so this file produces the same
-- final schema whether component_aliases already exists or not.
--
-- Compatibility strategy:
--   - id, component_id, alias, created_at, alias_key are never dropped,
--     renamed, or redefined. alias_key in particular stays an ordinary
--     column (not converted to generated — same reasoning as 0020's
--     canonical_key: Postgres can't convert an existing populated plain
--     column into a generated one, and making the new column generated
--     while the legacy one stays plain would just reintroduce the same
--     fresh-vs-legacy schema drift this pass exists to remove).
--   - technology_id, field_key, normalized_alias are the columns this
--     app's code and the unique index both need. technology_id/
--     field_key are backfilled from the parent components row (they're
--     denormalized here specifically so the unique index below can
--     enforce "one alias string resolves to one component per
--     technology+field slot" — Postgres can't put a unique index across
--     a join). normalized_alias is backfilled by recomputing the same
--     normalization alias_key was always meant to hold — the
--     compatibility audit confirmed all 6 existing alias_key values
--     already match it, so this reproduces alias_key's own values.
--   - Constraints (NOT NULL, non-empty CHECKs, the
--     technology_id+field_key+normalized_alias unique index) are added
--     only after the backfill, once every row is known-populated — the
--     audit confirmed "no blank alias normalized values," "no orphan
--     aliases," and "no duplicate aliases under the proposed new scope"
--     for the existing 6 rows before this migration was written, so
--     none of these can fail against real data.
--
-- The parent-lookup trigger (set_component_alias_technology_and_field,
-- below) now also keeps alias_key in sync with normalized_alias on
-- every future insert — one mechanism, one column kind, on both
-- install paths, the same principle 0020 applies to component_type/
-- canonical_key via sync_component_legacy_fields(). It does NOT fire on
-- UPDATE (aliases are never updated in place anywhere in this schema —
-- only inserted, by approve_component_submission() in 0022, or deleted
-- by a future moderator tool — so BEFORE INSERT only, unchanged from
-- the original version of this file, is still correct).
--
--   Write access: readable by everyone (needed for import/search lookups
--   to resolve an alias to a componentId); no insert/update/delete policy
--   for anyone — same as components, curated only, via future moderator
--   tooling, not a client-facing write path this milestone.
--
-- Touches: none beyond public.component_aliases itself (additive only —
-- see above). Depends on public.components (0020).
--
-- Rollback: see 0021_component_aliases_rollback.sql in
-- supabase/rollbacks/. Rewritten the same way this file was — never
-- drops public.component_aliases on either install path, for the same
-- reason 0020's rollback never drops public.components.

begin;

-- Step 1: ensure the table exists at all — a no-op on production (the
-- legacy table already exists), only actually creates anything on a
-- fresh database.
create table if not exists public.component_aliases (
    id uuid primary key default gen_random_uuid(),
    component_id uuid not null references public.components(id) on delete cascade,
    created_at timestamptz not null default now()
);

-- Step 2: ensure every column this app (and legacy production) needs
-- exists, added unconstrained. alias/alias_key are already on the
-- legacy table and skip silently; technology_id/field_key/
-- normalized_alias are new on both paths.
alter table public.component_aliases add column if not exists alias text;
alter table public.component_aliases add column if not exists alias_key text;
alter table public.component_aliases add column if not exists normalized_alias text;
alter table public.component_aliases add column if not exists technology_id text;
alter table public.component_aliases add column if not exists field_key text;

-- Step 3: backfill. technology_id/field_key come from the parent
-- component (this table has no technology/field concept of its own —
-- it's purely denormalized from components, same as the trigger below
-- populates it for every future row). normalized_alias/alias_key are
-- recomputed from alias directly. Every statement is `where <target> is
-- null` — never overwrites an existing legacy value.
update public.component_aliases ca
    set technology_id = c.technology_id,
        field_key = c.field_key
    from public.components c
    where c.id = ca.component_id
      and (ca.technology_id is null or ca.field_key is null);

update public.component_aliases set normalized_alias = regexp_replace(lower(alias), '[^a-z0-9]', '', 'g')
    where normalized_alias is null and alias is not null;

update public.component_aliases set alias_key = regexp_replace(lower(alias), '[^a-z0-9]', '', 'g')
    where alias_key is null and alias is not null;

-- Step 4: constraints, only now that every row is known-populated.
alter table public.component_aliases alter column alias set not null;
alter table public.component_aliases alter column technology_id set not null;
alter table public.component_aliases alter column field_key set not null;

do $$
begin
    if not exists (
        select 1 from pg_constraint
        where conrelid = 'public.component_aliases'::regclass
          and conname = 'component_aliases_alias_not_blank'
    ) then
        alter table public.component_aliases
            add constraint component_aliases_alias_not_blank
            check (char_length(trim(alias)) > 0);
    end if;

    if not exists (
        select 1 from pg_constraint
        where conrelid = 'public.component_aliases'::regclass
          and conname = 'component_aliases_technology_id_not_blank'
    ) then
        alter table public.component_aliases
            add constraint component_aliases_technology_id_not_blank
            check (char_length(trim(technology_id)) > 0);
    end if;

    if not exists (
        select 1 from pg_constraint
        where conrelid = 'public.component_aliases'::regclass
          and conname = 'component_aliases_field_key_not_blank'
    ) then
        alter table public.component_aliases
            add constraint component_aliases_field_key_not_blank
            check (char_length(trim(field_key)) > 0);
    end if;
end $$;

create unique index if not exists component_aliases_technology_field_normalized_idx
    on public.component_aliases (technology_id, field_key, normalized_alias);

create index if not exists component_aliases_component_id_idx
    on public.component_aliases (component_id);

-- Populates technology_id/field_key/alias_key/normalized_alias from the
-- parent component on every future insert — the only write path today
-- is approve_component_submission()'s alias branch (0022), which never
-- sets any of these four columns itself, relying entirely on this
-- trigger, on both install paths alike.
create or replace function public.set_component_alias_technology_and_field()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    select technology_id, field_key
        into new.technology_id, new.field_key
        from public.components
        where id = new.component_id;

    new.normalized_alias := regexp_replace(lower(new.alias), '[^a-z0-9]', '', 'g');
    new.alias_key := new.normalized_alias;

    return new;
end;
$$;

drop trigger if exists set_component_alias_technology_and_field on public.component_aliases;
create trigger set_component_alias_technology_and_field
    before insert on public.component_aliases
    for each row
    execute function public.set_component_alias_technology_and_field();

-- Trigger firing doesn't require the triggering statement's role to hold
-- EXECUTE on the trigger function (Postgres invokes it as part of the
-- table-level DML, not as a direct function call) — revoking from PUBLIC
-- is purely defensive, so this can't additionally be called directly as
-- an ordinary function (it would error anyway outside trigger context,
-- since NEW isn't defined there, but explicit is better than implicit).
revoke execute on function public.set_component_alias_technology_and_field() from public;

alter table public.component_aliases enable row level security;

-- Production's legacy table wasn't confirmed to already have an
-- equivalent policy the way components' was — enabling RLS here is
-- idempotent (a no-op if it's already on) and, if RLS genuinely was off
-- before, this is a pure hardening, not a behavior change any real
-- reader would notice (reads stay just as open; writes, which had no
-- confirmed client path either way, stay closed).
drop policy if exists "Component aliases are readable by everyone" on public.component_aliases;
create policy "Component aliases are readable by everyone" on public.component_aliases
    for select using (true);

-- No insert/update/delete policy for anyone — curated only, see header
-- comment. With RLS enabled and no matching policy, all direct client
-- writes are denied outright.

commit;
