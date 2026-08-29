-- Rollback for: 0046_legal_holds
--
-- Drops place_legal_hold()/release_legal_hold() and the legal_holds
-- table itself. Destroys any recorded hold state -- if a real hold is
-- active at rollback time, resolve or deliberately accept losing that
-- record before running this; there is no way to preserve it outside
-- this table by design (see 0046's own header on why the table exists
-- at all).

begin;

drop function if exists public.release_legal_hold(uuid);
drop function if exists public.place_legal_hold(uuid, text);
drop table if exists public.legal_holds;

commit;
