-- Rollback for: 0049_account_deletion_challenge
--
-- WARNING: this restores 0048's original zero-argument
-- self_delete_account() verbatim — i.e., it REINTRODUCES BOTH bugs
-- 0049 exists to fix: (1) the iat-only reauthentication gap (no
-- challenge/amr check at all in the restored function — reauthentication
-- would need to be re-verified some other way before this is safe to
-- use again), and (2) the retry storage-path-loss bug (the restored
-- function unconditionally re-runs its Storage-path capture query
-- before checking whether a job already exists, so a retried call after
-- a first successful one would silently overwrite the correctly-
-- captured paths with an empty array). Do not run this rollback and
-- leave the delete-account Edge Function pointed at the restored
-- function without addressing both first.
--
-- Drops request_account_deletion_challenge() and
-- account_deletion_challenges (destroying any outstanding, unconsumed
-- challenge — harmless; a caller simply requests a new one), drops the
-- one-argument self_delete_account(uuid), and recreates the exact
-- zero-argument version 0048 defined.

begin;

drop function if exists public.self_delete_account(uuid);
drop function if exists public.request_account_deletion_challenge();
drop table if exists public.account_deletion_challenges;

-- Verbatim restoration of 0048_self_delete_account.sql's function body.
create or replace function public.self_delete_account()
returns table(job_id uuid, storage_paths text[])
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_user_id uuid;
    v_job_id uuid;
    v_paths text[];
    v_existing_job_id uuid;
begin
    v_user_id := auth.uid();

    if v_user_id is null then
        raise exception 'You must be signed in.';
    end if;

    if exists (
        select 1 from public.legal_holds
        where user_id = v_user_id and released_at is null
    ) then
        raise exception 'Your request could not be completed. Contact support@specboundapp.com.';
    end if;

    select id into v_existing_job_id
    from public.account_deletion_jobs
    where former_user_id = v_user_id;

    select coalesce(array_agg(distinct p) filter (where p is not null), '{}')
    into v_paths
    from (
        select avatar_path as p from public.profiles where id = v_user_id and avatar_path is not null

        union all

        select rm.storage_path as p
        from public.revision_media rm
        join public.build_revisions br on br.id = rm.revision_id
        join public.builds b on b.id = br.build_id
        where b.user_id = v_user_id

        union all

        select pm.storage_path as p
        from public.project_media pm
        join public.project_drafts pd on pd.id = pm.draft_id
        where pd.user_id = v_user_id
    ) as all_paths;

    delete from public.builds where user_id = v_user_id;

    update public.build_revisions set user_id = null where user_id = v_user_id;

    delete from public.profiles where id = v_user_id;

    if v_existing_job_id is null then
        insert into public.account_deletion_jobs (former_user_id, state, storage_paths)
        values (v_user_id, 'db_prepared', v_paths)
        returning id into v_job_id;

        insert into public.moderation_actions (actor_id, action_type, target_type, target_id, note)
        values (v_user_id, 'account_deleted', 'profile', v_user_id, 'Self-service account deletion.');
    else
        update public.account_deletion_jobs
            set state = 'db_prepared', storage_paths = v_paths
            where id = v_existing_job_id;

        v_job_id := v_existing_job_id;
    end if;

    return query select v_job_id, v_paths;
end;
$$;

revoke all on function public.self_delete_account() from public;
grant execute on function public.self_delete_account() to authenticated;

commit;
