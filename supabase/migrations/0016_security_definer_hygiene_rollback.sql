-- Rollback for: 0016_security_definer_hygiene
--
-- Restores PUBLIC's default execute privilege on set_updated_at(),
-- reinstating Postgres's implicit default (every newly created function
-- is executable by PUBLIC unless explicitly revoked). Since a RETURNS
-- TRIGGER function cannot actually be invoked outside trigger context
-- regardless, this has no practical effect either way.

begin;

grant execute on function public.set_updated_at() to public;

commit;
