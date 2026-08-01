-- Rollback for 0021_component_aliases.
-- Drops the trigger, its function, and the table, in dependency order.
-- Only use this if 0021 itself needs to be undone — note that 0022
-- (component_submissions) depends on this table for its alias-approval
-- path; roll that back first if it's been applied.

begin;

drop trigger if exists set_component_alias_technology_and_field on public.component_aliases;
drop function if exists public.set_component_alias_technology_and_field();
drop table if exists public.component_aliases;

commit;
