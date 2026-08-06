-- Rollback for 0020_components_catalog.
--
-- REWRITTEN for production compatibility, same pass that rewrote 0020
-- itself. The original version of this rollback did `drop table if
-- exists public.components` unconditionally — safe when 0020 could only
-- ever have created that table from scratch, but 0020 no longer does
-- that unconditionally either. On production, public.components
-- predates 0020 entirely (9 real rows); this rollback has no reliable
-- way to tell "0020 created this table" apart from "0020 only ever
-- added columns to a table that was already there" — so it never drops
-- the table on either path. It only reverses what 0020 is guaranteed to
-- have added itself: the sync trigger, the columns 0020 introduces that
-- never existed before it (field_key, normalized_name, created_by), and
-- the new indexes/constraints built on them.
--
-- Deliberately NOT reversed, on purpose, not by oversight:
--   - component_type, canonical_key: never touched here. On a legacy
--     database these are production's own pre-existing columns with
--     real data 0020 never created; on a fresh database they're the
--     columns 0020 keeps in sync with field_key/normalized_name for
--     schema-parity with production (see 0020's own header) — either
--     way, dropping them risks destroying something this rollback
--     cannot prove is safe to remove.
--   - technology_id, canonical_name, manufacturer, metadata, created_at,
--     updated_at: never touched — these are either production's own
--     pre-existing columns, or ordinary baseline columns a fresh
--     install's table needs to function at all.
--   - The table itself, and the "Components catalog is readable by
--     everyone"/"Catalog moderators can add catalog components"
--     policies: left in place. Dropping the policies would leave a
--     legacy table with RLS enabled and (depending on what production's
--     own differently-named policy actually covers) potentially no
--     working read path at all — safer to leave a possibly-redundant
--     extra policy than to risk removing the only one that works.
--
-- Only use this if 0020 itself needs to be undone, and only after
-- confirming (by hand, against the actual target database) that
-- reversing field_key/normalized_name/created_by and the sync trigger
-- won't break something else that came to depend on them after 0020
-- was applied (e.g. 0022's approve_component_submission(), which
-- writes field_key directly and relies on the trigger to populate
-- component_type/canonical_key from it — reversing 0020 without also
-- reversing 0021-0032 first leaves those objects referencing columns
-- this rollback just removed).

begin;

drop trigger if exists sync_component_legacy_fields on public.components;
drop function if exists public.sync_component_legacy_fields();

drop index if exists public.components_technology_field_normalized_idx;
drop index if exists public.components_technology_field_idx;

alter table public.components drop constraint if exists components_technology_id_not_blank;
alter table public.components drop constraint if exists components_field_key_not_blank;
alter table public.components drop constraint if exists components_canonical_name_not_blank;

alter table public.components drop column if exists field_key;
alter table public.components drop column if exists normalized_name;
alter table public.components drop column if exists created_by;

drop policy if exists "Catalog moderators can add catalog components" on public.components;
drop policy if exists "Components catalog is readable by everyone" on public.components;

drop function if exists public.is_catalog_moderator(uuid);
drop table if exists public.catalog_moderators;

commit;
