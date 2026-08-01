-- Migration: 0011_notifications
-- Milestone: 7B (Notifications)
-- Status: PROPOSED — not yet applied. Depends on 0001-0010 being applied
-- first.
--
-- Purpose: a private in-app notification system for comments, likes, and
-- saves on a user's own projects.
--
--   - notifications.type includes 'reply' in its CHECK constraint for
--     future schema compatibility, per explicit direction — no code path
--     in this migration ever inserts type = 'reply'. Threaded replies
--     don't exist yet (comments.parent_comment_id has been reserved,
--     unused, since 0007_comments.sql); this only avoids a future
--     migration just to widen the constraint once they do.
--   - comment_id is nullable — populated for 'comment' (and, later,
--     'reply'), null for 'like'/'save'.
--   - No message text is stored. Notifications are rendered client-side
--     from type + the joined actor's current username + the joined
--     build's current title, at read time — not frozen at creation time.
--     Same reasoning as everywhere else in this app that a title/name can
--     change after the fact (only revision history snapshots content on
--     purpose).
--   - SELECT is a direct RLS policy scoped to the caller's own row only
--     (recipient_id = auth.uid()) — this is what makes notifications
--     private to the recipient. Not even the actor (the person who
--     commented/liked/saved) can see that it generated a notification.
--     No insert/update/delete policies — every write goes through a
--     function.
--   - create_notification(...) is the only way a notification row is
--     ever created, and it is NOT granted to any client role at all (not
--     even authenticated) — it only exists to be called from inside
--     other already-privileged SECURITY DEFINER functions
--     (create_comment, set_build_like, set_build_saved, all modified
--     below). A client cannot create a notification directly under any
--     circumstances. It only guards against self-notification
--     (recipient_id = actor_id) — per explicit direction, it does NOT
--     attempt to collapse/suppress duplicate notifications for the same
--     (recipient, actor, build, type); every real event creates a new
--     row. The calling RPCs' own idempotency (unique constraints,
--     on-conflict-do-nothing) is what already prevents a *retried*
--     request from double-notifying — a genuine repeat action (unlike
--     then like again) is a genuine second event and gets a second
--     notification.
--   - mark_notification_read(p_notification_id) /
--     mark_all_notifications_read() are SECURITY DEFINER, ownership-
--     checked, granted to authenticated only. Per explicit direction,
--     nothing anywhere auto-marks notifications read — only these two
--     functions ever set read_at, both requiring an explicit client
--     call (an individual click, or "Mark all read").
--   - create_comment()/set_build_like()/set_build_saved() are modified
--     (CREATE OR REPLACE, not edits to 0007/0008/0009 themselves, per
--     this project's migration convention for already-applied
--     functions) to call create_notification() at the point a real
--     event occurs:
--       - create_comment(): after the insert always succeeds (a comment
--         insert is never a no-op), notifies the build's owner.
--       - set_build_like()/set_build_saved(): only on the branch where a
--         row was ACTUALLY newly inserted — detected via
--         "on conflict do nothing returning id into v_inserted_id" and
--         checking it's not null — never on unlike/unsave, never on a
--         no-op re-like/re-save of an already-liked/saved project.
--     In all three, create_notification() itself is what skips
--     self-notification (the build owner liking/commenting/saving their
--     own project) — the calling function doesn't need its own check.
--
-- Touches: create_comment(uuid, text), set_build_like(uuid, boolean),
-- set_build_saved(uuid, boolean) — all replaced, no signature change.
-- Adds notifications, create_notification(), mark_notification_read(),
-- mark_all_notifications_read().
--
-- Rollback: see 0011_notifications_rollback.sql in supabase/rollbacks/. Note:
-- the rollback restores create_comment()/set_build_like()/
-- set_build_saved() to their pre-7B bodies (copied from 0007/0008/0009)
-- so a rollback doesn't leave dangling calls to a dropped function.

begin;

create table public.notifications (
    id uuid primary key default gen_random_uuid(),
    recipient_id uuid not null references auth.users(id) on delete cascade,
    actor_id uuid not null references auth.users(id) on delete cascade,
    type text not null check (type in ('comment', 'like', 'save', 'reply')),
    build_id uuid not null references public.builds(id) on delete cascade,
    comment_id uuid references public.comments(id) on delete cascade,
    read_at timestamptz,
    created_at timestamptz not null default now()
);

create index notifications_recipient_created_idx
    on public.notifications (recipient_id, created_at desc);

create index notifications_recipient_unread_idx
    on public.notifications (recipient_id) where read_at is null;

alter table public.notifications enable row level security;

create policy "Users can see their own notifications" on public.notifications
    for select using (recipient_id = auth.uid());

-- No insert/update/delete policies — with RLS enabled and no matching
-- policy, direct client writes are denied outright.

create or replace function public.create_notification(
    p_recipient_id uuid,
    p_actor_id uuid,
    p_type text,
    p_build_id uuid,
    p_comment_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    if p_recipient_id = p_actor_id then
        return; -- never notify users about their own actions
    end if;

    insert into public.notifications (recipient_id, actor_id, type, build_id, comment_id)
    values (p_recipient_id, p_actor_id, p_type, p_build_id, p_comment_id);
end;
$$;

-- Deliberately no GRANT to anon or authenticated — only ever called from
-- inside other SECURITY DEFINER functions, which already run with
-- elevated privilege. A direct client RPC call is rejected outright.
revoke all on function public.create_notification(uuid, uuid, text, uuid, uuid) from public;

create or replace function public.mark_notification_read(
    p_notification_id uuid
)
returns public.notifications
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_notification public.notifications;
begin
    if auth.uid() is null then
        raise exception 'You must be signed in.';
    end if;

    update public.notifications
        set read_at = coalesce(read_at, now())
        where id = p_notification_id and recipient_id = auth.uid()
        returning * into v_notification;

    if v_notification is null then
        raise exception 'Notification not found.';
    end if;

    return v_notification;
end;
$$;

revoke all on function public.mark_notification_read(uuid) from public;
grant execute on function public.mark_notification_read(uuid) to authenticated;

create or replace function public.mark_all_notifications_read()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_count integer;
begin
    if auth.uid() is null then
        raise exception 'You must be signed in.';
    end if;

    update public.notifications
        set read_at = now()
        where recipient_id = auth.uid() and read_at is null;

    get diagnostics v_count = row_count;

    return v_count;
end;
$$;

revoke all on function public.mark_all_notifications_read() from public;
grant execute on function public.mark_all_notifications_read() to authenticated;

-- --- Modified write RPCs: notify the build's owner on a real event -----

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

    perform public.create_notification(v_build.user_id, auth.uid(), 'comment', p_build_id, v_comment.id);

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
    v_inserted_id uuid;
begin
    if auth.uid() is null then
        raise exception 'You must be signed in to like a project.';
    end if;

    select * into v_build from public.builds where id = p_build_id;

    if v_build is null then
        raise exception 'Project not found.';
    end if;

    -- Deliberately strict: 'public' only, not "public or owner". An
    -- owner previewing their own unpublished project must not be able to
    -- change its like state either way.
    if v_build.visibility <> 'public' then
        raise exception 'This project is not available for likes.';
    end if;

    if p_liked then
        insert into public.likes (build_id, user_id)
        values (p_build_id, auth.uid())
        on conflict (build_id, user_id) do nothing
        returning id into v_inserted_id;

        -- Only a genuinely new like (not a no-op re-like of an
        -- already-liked project) generates a notification.
        if v_inserted_id is not null then
            perform public.create_notification(v_build.user_id, auth.uid(), 'like', p_build_id);
        end if;
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
    v_inserted_id uuid;
begin
    if auth.uid() is null then
        raise exception 'You must be signed in to save a project.';
    end if;

    select * into v_build from public.builds where id = p_build_id;

    if v_build is null then
        raise exception 'Project not found.';
    end if;

    if p_saved then
        -- Strict 'public' only, not "public or owner" — same reasoning
        -- as set_build_like(): a stranger can't save what they can't
        -- see, and an owner previewing their own unpublished project has
        -- no reason to "save" it either.
        if v_build.visibility <> 'public' then
            raise exception 'This project is not available to save.';
        end if;

        insert into public.saved_builds (build_id, user_id)
        values (p_build_id, auth.uid())
        on conflict (build_id, user_id) do nothing
        returning id into v_inserted_id;

        -- Only a genuinely new save (not a no-op re-save) generates a
        -- notification.
        if v_inserted_id is not null then
            perform public.create_notification(v_build.user_id, auth.uid(), 'save', p_build_id);
        end if;
    else
        -- Deliberately no visibility check here — see
        -- 0009_saved_builds.sql header comment. Removing your own
        -- private bookmark is always allowed, regardless of the build's
        -- current visibility. Unsaving never generates a notification.
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

commit;
