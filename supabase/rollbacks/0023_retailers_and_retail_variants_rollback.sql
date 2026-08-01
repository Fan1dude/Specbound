-- Rollback for 0023_retailers_and_retail_variants.
-- Drops component_retailer_links first (references both variants and
-- retailers), then component_retail_variants (references components),
-- then retailers. Only use this if 0023 itself needs to be undone. Safe
-- with respect to 0020/0021/0022: components, component_aliases, and
-- component_submissions are all untouched.

begin;

drop table if exists public.component_retailer_links;
drop table if exists public.component_retail_variants;
drop table if exists public.retailers;

commit;
