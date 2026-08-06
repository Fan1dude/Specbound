-- Rollback for 0021_component_aliases.
--
-- REWRITTEN for production compatibility, same pass that rewrote 0021
-- itself, same reasoning as 0020's rollback: production's
-- public.component_aliases predates this migration (6 real rows), and
-- this file has no reliable way to tell that apart from a table 0021
-- created from scratch on a fresh install — so it never drops the table
-- on either path. It removes the trigger and its function (0021 owns
-- both, on every install path, unconditionally), and the columns/
-- constraints/index 0021 introduces that never existed before it
-- (technology_id, field_key, normalized_alias, and the constraints/
-- index built on them).
--
-- Deliberately NOT reversed: alias, alias_key, id, component_id,
-- created_at — never touched, for the same "can't prove these are safe
-- to remove" reason 0020's rollback leaves component_type/canonical_key
-- alone. The SELECT policy is also left in place, not dropped — see
-- 0020's rollback for why (an RLS-enabled table with its only known
-- read policy removed is worse than one extra redundant policy left
-- behind).
--
-- Only use this if 0021 itself needs to be undone — note that 0022
-- (component_submissions) depends on this table for its alias-approval
-- path; roll that back first if it's been applied, and confirm nothing
-- else came to depend on technology_id/field_key/normalized_alias after
-- 0021 was applied before removing them here.

begin;

drop trigger if exists set_component_alias_technology_and_field on public.component_aliases;
drop function if exists public.set_component_alias_technology_and_field();

drop index if exists public.component_aliases_technology_field_normalized_idx;
drop index if exists public.component_aliases_component_id_idx;

alter table public.component_aliases drop constraint if exists component_aliases_alias_not_blank;
alter table public.component_aliases drop constraint if exists component_aliases_technology_id_not_blank;
alter table public.component_aliases drop constraint if exists component_aliases_field_key_not_blank;

alter table public.component_aliases drop column if exists technology_id;
alter table public.component_aliases drop column if exists field_key;
alter table public.component_aliases drop column if exists normalized_alias;

drop policy if exists "Component aliases are readable by everyone" on public.component_aliases;

commit;
