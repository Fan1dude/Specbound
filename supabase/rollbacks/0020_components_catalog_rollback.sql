-- Rollback for 0020_components_catalog.
-- Drops components (and its indexes/policies/trigger along with it),
-- is_catalog_moderator(), and catalog_moderators, in dependency order.
-- Only use this if 0020 itself needs to be undone — note that dropping
-- components also breaks any specifications value that references a
-- components.id via componentId, since those references live in
-- project_drafts/builds/build_revisions.specifications jsonb (not a
-- foreign key — see 0020's header comment) and would silently become
-- dangling ids rather than erroring. Also note: if 0021 (component
-- submissions) has been applied, roll that back first — it references
-- components and is_catalog_moderator().

begin;

drop table if exists public.components;
drop function if exists public.is_catalog_moderator(uuid);
drop table if exists public.catalog_moderators;

commit;
