-- Migration: 0021_component_aliases
-- Milestone: 19 — Structured Parts Catalog & Import Architecture
-- Status: PROPOSED — not yet applied. Depends on 0020 (public.components).
--
-- Full design: docs/milestones/MILESTONE_19_PARTS_CATALOG_ARCHITECTURE.md §4.2.
--
--   components.normalized_name (0020) already collapses punctuation/
--   spacing variants of the same literal name ("RTX 4080" / "RTX-4080").
--   This table covers what normalization alone can't: abbreviations,
--   shorthand, and common misspellings ("4080" for the full canonical
--   name) — a curated, moderator-maintained mapping, not an algorithm.
--
--   Ships ahead of 0022 (component_submissions) even though aliases are
--   conceptually a moderation *output* (one of the two ways a submission
--   can be resolved) — the approval RPC in 0022 needs this table to
--   already exist to write to it, and a migration can't forward-reference
--   an object a later file defines.
--
--   technology_id/field_key are denormalized onto this table (copied from
--   the parent components row by the trigger below) purely so the unique
--   index can enforce "within one technology+field slot, an alias string
--   resolves to exactly one canonical component" — Postgres can't put a
--   unique index across a join, and querying through component_id alone
--   wouldn't catch the same alias text being attached to two different
--   components in the same slot.
--
--   Write access: readable by everyone (needed for import/search lookups
--   to resolve an alias to a componentId); no insert/update/delete policy
--   for anyone — same as components, curated only, via future moderator
--   tooling, not a client-facing write path this milestone.
--
--   SQL/security audit pass (2026-07-31): added non-empty checks; revoked
--   PUBLIC execute on the trigger function (defensive — see inline
--   comment). The alias-vs-existing-canonical-name collision guard (an
--   alias's normalized text colliding with a *different* component's
--   normalized_name in the same slot — not caught by either table's own
--   unique index alone) lives in 0022's approve_component_submission(),
--   the only path that writes to this table. See
--   docs/milestones/MILESTONE_19_SQL_SECURITY_AUDIT.md for the full audit.
--
-- Touches: none (one new table, one new trigger function). Depends on
-- public.components (0020).
--
-- Rollback: see 0021_component_aliases_rollback.sql in supabase/rollbacks/.

begin;

create table public.component_aliases (
    id uuid primary key default gen_random_uuid(),
    component_id uuid not null references public.components(id) on delete cascade,
    alias text not null
        check (char_length(trim(alias)) > 0),
    normalized_alias text generated always as (
        regexp_replace(lower(alias), '[^a-z0-9]', '', 'g')
    ) stored,
    -- Populated by the trigger below from the parent component — never
    -- set directly by a caller. Constrained not-empty anyway (rather than
    -- trusting the trigger alone) for the same reason components'
    -- technology_id/field_key are — cheap insurance against a future bug
    -- in the trigger silently producing an empty value.
    technology_id text not null
        check (char_length(trim(technology_id)) > 0),
    field_key text not null
        check (char_length(trim(field_key)) > 0),
    created_at timestamptz not null default now()
);

create unique index component_aliases_technology_field_normalized_idx
    on public.component_aliases (technology_id, field_key, normalized_alias);

create index component_aliases_component_id_idx
    on public.component_aliases (component_id);

create function public.set_component_alias_technology_and_field()
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

    return new;
end;
$$;

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

create policy "Component aliases are readable by everyone" on public.component_aliases
    for select using (true);

-- No insert/update/delete policy for anyone — curated only, see header
-- comment. With RLS enabled and no matching policy, all direct client
-- writes are denied outright.

commit;
