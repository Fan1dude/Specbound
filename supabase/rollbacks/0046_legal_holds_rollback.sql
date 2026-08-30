-- Rollback for: 0046_legal_holds
--
-- Security-review requirement: refuses to proceed (raises, does not
-- drop anything) if any row exists in legal_holds — active or already-
-- released, since even a released hold's own history (who placed it,
-- when, why) may itself be a record worth keeping. There is no way to
-- preserve this data outside this table by design (see 0046's own
-- header on why the table exists at all) — if rows genuinely need to
-- be cleared first, do that explicitly and separately, with its own
-- review, before running this rollback.

begin;

do $$
begin
    if exists (select 1 from public.legal_holds limit 1) then
        raise exception 'Cannot roll back 0046: legal_holds contains at least one row (active or released). Resolve or deliberately clear it in its own reviewed step first -- this rollback refuses to silently destroy hold history.';
    end if;
end $$;

drop function if exists public.release_legal_hold(uuid);
drop function if exists public.place_legal_hold(uuid, text);
drop table if exists public.legal_holds;

commit;
