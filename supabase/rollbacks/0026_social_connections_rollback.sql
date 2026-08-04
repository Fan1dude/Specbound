-- Rollback for 0026_social_connections.

begin;

drop function if exists public.sync_discord_identity();
drop table if exists public.social_connections;

commit;
