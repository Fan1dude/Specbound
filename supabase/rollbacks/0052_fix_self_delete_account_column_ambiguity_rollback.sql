-- Rollback for: 0052_fix_self_delete_account_column_ambiguity
--
-- WARNING — this is not a neutral rollback: it restores
-- `self_delete_account(uuid)`'s ORIGINAL, `0049`-era function body
-- VERBATIM, which is KNOWN, CONFIRMED BROKEN — real local execution
-- found its retry branch raises
--   ERROR: column reference "storage_paths" is ambiguous
-- on every second call for the same account (see
-- 0052_fix_self_delete_account_column_ambiguity.sql's own header for
-- the full root cause). Running this rollback makes the retry path
-- unusable again, on purpose, only because that is what "restore the
-- prior state" honestly means here — there is no safe partial rollback
-- available for a single function body. Do not run this rollback and
-- leave the delete-account Edge Function pointed at the restored
-- function without either re-applying 0052 or fixing this bug some
-- other way first.
--
-- No data-loss guard is needed (unlike 0046/0047/0050's own rollbacks):
-- this migration never dropped or altered any column, row, or table —
-- only a function body — so there is nothing to lose by reverting it,
-- only a known bug to reintroduce, disclosed above.

begin;

create or replace function public.self_delete_account(
    p_challenge_token uuid
)
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
    v_consumed_user_id uuid;
begin
    v_user_id := auth.uid();

    if v_user_id is null then
        raise exception 'You must be signed in.';
    end if;

    delete from public.account_deletion_challenges
        where user_id = v_user_id
          and token = p_challenge_token
          and expires_at > now()
        returning user_id into v_consumed_user_id;

    if v_consumed_user_id is null then
        raise exception 'Deletion authorization is invalid or has expired. Request a new one and try again.';
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

    if v_existing_job_id is null then
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

        insert into public.account_deletion_jobs (former_user_id, state, storage_paths)
        values (v_user_id, 'db_prepared', v_paths)
        returning id into v_job_id;

        insert into public.moderation_actions (actor_id, action_type, target_type, target_id, note)
        values (v_user_id, 'account_deleted', 'profile', v_user_id, 'Self-service account deletion.');
    else
        -- BROKEN, restored verbatim for an honest rollback -- see this
        -- file's own WARNING above. Bare `storage_paths` collides with
        -- this function's own `storage_paths` OUT parameter
        -- (`returns table(job_id uuid, storage_paths text[])` above)
        -- and raises "column reference storage_paths is ambiguous" on
        -- every execution of this branch.
        select storage_paths into v_paths
        from public.account_deletion_jobs
        where id = v_existing_job_id;

        update public.account_deletion_jobs
            set state = 'db_prepared'
            where id = v_existing_job_id;

        v_job_id := v_existing_job_id;
    end if;

    return query select v_job_id, v_paths;
end;
$$;

revoke all on function public.self_delete_account(uuid) from public;
grant execute on function public.self_delete_account(uuid) to authenticated;

commit;
