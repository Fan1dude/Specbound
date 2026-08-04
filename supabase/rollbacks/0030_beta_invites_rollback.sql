-- Rollback for 0030_beta_invites.

begin;

drop function if exists public.redeem_beta_invite(text);
drop table if exists public.beta_invites;

commit;
