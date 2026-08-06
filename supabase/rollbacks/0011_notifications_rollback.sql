-- Rollback for: 0011_notifications
--
-- Restores create_comment()/set_build_like()/set_build_saved() to their
-- exact pre-7B bodies (copied from 0007_comments.sql/0008_project_likes.sql/
-- 0009_saved_builds.sql) BEFORE dropping create_notification(), so no
-- window exists where a live function calls one that's already gone.
-- Drops the two read-state functions and the notifications table entirely,
-- including every notification ever recorded — there's no separate
-- data-preserving option since the table itself is new in this migration.

begin;

create or replace function public.create_comment(
    p_build_id uuid,
    p_body text
)
returns public.comments
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_build public.builds;
    v_comment public.comments;
    v_trimmed text;
begin
    if auth.uid() is null then
        raise exception 'You must be signed in to comment.';
    end if;

    select * into v_build from public.builds where id = p_build_id;

    if v_build is null then
        raise exception 'Project not found.';
    end if;

    if v_build.visibility <> 'public' and v_build.user_id <> auth.uid() then
        raise exception 'This project is not available for comments.';
    end if;

    v_trimmed := trim(coalesce(p_body, ''));

    if length(v_trimmed) = 0 then
        raise exception 'Comment cannot be empty.';
    end if;

    if length(v_trimmed) > 2000 then
        raise exception 'Comment is too long (2000 characters max).';
    end if;

    insert into public.comments (build_id, user_id, body)
    values (p_build_id, auth.uid(), v_trimmed)
    returning * into v_comment;

    return v_comment;
end;
$$;

create or replace function public.set_build_like(
    p_build_id uuid,
    p_liked boolean
)
returns table(liked boolean, likes_count integer)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_build public.builds;
begin
    if auth.uid() is null then
        raise exception 'You must be signed in to like a project.';
    end if;

    select * into v_build from public.builds where id = p_build_id;

    if v_build is null then
        raise exception 'Project not found.';
    end if;

    if v_build.visibility <> 'public' then
        raise exception 'This project is not available for likes.';
    end if;

    if p_liked then
        insert into public.likes (build_id, user_id)
        values (p_build_id, auth.uid())
        on conflict (build_id, user_id) do nothing;
    else
        delete from public.likes
            where build_id = p_build_id and user_id = auth.uid();
    end if;

    return query
        select
            exists(
                select 1 from public.likes l
                where l.build_id = p_build_id and l.user_id = auth.uid()
            ),
            coalesce(
                (select b.likes_count from public.builds b where b.id = p_build_id),
                0
            );
end;
$$;

create or replace function public.set_build_saved(
    p_build_id uuid,
    p_saved boolean
)
returns table(saved boolean)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_build public.builds;
begin
    if auth.uid() is null then
        raise exception 'You must be signed in to save a project.';
    end if;

    select * into v_build from public.builds where id = p_build_id;

    if v_build is null then
        raise exception 'Project not found.';
    end if;

    if p_saved then
        if v_build.visibility <> 'public' then
            raise exception 'This project is not available to save.';
        end if;

        insert into public.saved_builds (build_id, user_id)
        values (p_build_id, auth.uid())
        on conflict (build_id, user_id) do nothing;
    else
        delete from public.saved_builds
            where build_id = p_build_id and user_id = auth.uid();
    end if;

    return query
        select exists(
            select 1 from public.saved_builds s
            where s.build_id = p_build_id and s.user_id = auth.uid()
        );
end;
$$;

drop function if exists public.mark_all_notifications_read();
drop function if exists public.mark_notification_read(uuid);
drop function if exists public.create_notification(uuid, uuid, text, uuid, uuid);
drop table if exists public.notifications;

commit;
