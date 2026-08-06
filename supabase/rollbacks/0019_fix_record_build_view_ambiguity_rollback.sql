-- Rollback: 0019_fix_record_build_view_ambiguity
--
-- Restores record_build_view() to its exact original body from
-- 0010_build_view_tracking.sql — including both issues 0019 fixed: the
-- ambiguous `views` column reference (every real call failed) and the
-- unconditional final return (leaked a private build's view count to
-- any caller, not just its owner). Use only if the fix itself needs to
-- be backed out; this restores known-broken/leaking prior behavior, not
-- a neutral state.

begin;

create or replace function public.record_build_view(
    p_build_id uuid,
    p_anon_id uuid default null
)
returns table(views integer)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_build public.builds;
    v_viewer_key text;
    v_last timestamptz;
begin
    select * into v_build from public.builds where id = p_build_id;

    if v_build is null then
        raise exception 'Project not found.';
    end if;

    if v_build.visibility = 'public' then
        v_viewer_key := case
            when auth.uid() is not null then 'user:' || auth.uid()::text
            when p_anon_id is not null then 'anon:' || p_anon_id::text
            else null
        end;

        -- Skip entirely for the owner's own views, and for a caller we
        -- have no identity for at all (no session, no anon id supplied).
        if v_viewer_key is not null
            and (auth.uid() is null or v_build.user_id <> auth.uid())
        then
            select last_viewed_at into v_last
                from public.build_view_cooldowns
                where build_id = p_build_id and viewer_key = v_viewer_key
                for update;

            if v_last is null or v_last < now() - interval '30 minutes' then
                insert into public.build_view_cooldowns (build_id, viewer_key, last_viewed_at)
                values (p_build_id, v_viewer_key, now())
                on conflict (build_id, viewer_key)
                    do update set last_viewed_at = excluded.last_viewed_at;

                update public.builds
                    set views = coalesce(views, 0) + 1
                    where id = p_build_id;
            end if;
        end if;
    end if;

    return query
        select coalesce(
            (select b.views from public.builds b where b.id = p_build_id),
            0
        );
end;
$$;

commit;
