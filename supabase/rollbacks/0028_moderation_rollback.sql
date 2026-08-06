-- Rollback for 0028_moderation.

begin;

drop function if exists public.revoke_profile_role(uuid, text, text);
drop function if exists public.grant_profile_role(uuid, text, text);
drop function if exists public.resolve_report(uuid, text, text);
drop function if exists public.report_content(text, uuid, text);
drop table if exists public.moderation_actions;
drop table if exists public.content_reports;

commit;
