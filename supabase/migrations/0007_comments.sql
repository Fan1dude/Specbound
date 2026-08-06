-- Migration: 0007_comments
-- Milestone: 6A (Project Comments)
-- Status: PROPOSED — not yet applied. Depends on 0001-0006 being applied
-- first.
--
-- Purpose: comments on published projects.
--
--   - comments.build_id (not revision_id) — comments belong to the build
--     as a whole, independent of which revision is currently live.
--   - SELECT stays a direct RLS policy (read-only, same shape as
--     builds/build_revisions/revision_media): visible when the parent
--     build is visible (public, or the viewer owns it) AND the comment
--     itself isn't soft-deleted. This is the only comments policy —
--     there are no insert/update/delete policies, matching the existing
--     "no direct writes" posture for every other table in this schema.
--   - Writes go through two SECURITY DEFINER functions instead of RLS
--     write policies, per explicit direction (breaking from the initial
--     proposal, which suggested RLS was sufficient for this table):
--       - create_comment(p_build_id, p_body): auth.uid() is read
--         directly inside the function (never accepted as a parameter,
--         so it can't be spoofed), re-validates the build is actually
--         visible to the caller, and validates body length with a
--         friendly error before the CHECK constraint would catch it
--         anyway.
--       - delete_comment(p_comment_id): authorizes the comment's own
--         author OR the build's owner, and soft-deletes — sets
--         deleted_at rather than removing the row. Nothing in this
--         schema ever hard-deletes a comment through the app; the SELECT
--         policy's `deleted_at is null` clause is what makes a
--         soft-deleted comment actually disappear from normal reads.
--   - parent_comment_id: added now, per explicit direction, for a future
--     replies feature that is completely out of scope for this
--     milestone — no UI, no query, no code anywhere references it yet.
--     Nullable, references comments(id), on delete set null (a parent
--     comment's later removal — which in practice only ever means
--     soft-delete, since nothing hard-deletes — shouldn't cascade-delete
--     its children once replies exist; this can be revisited when
--     replies are actually designed).
--
-- Touches: none (new table only). Adds comments, create_comment(),
-- delete_comment().
--
-- Rollback: see 0007_comments_rollback.sql in supabase/rollbacks/.

begin;

create table public.comments (
    id uuid primary key default gen_random_uuid(),
    build_id uuid not null references public.builds(id) on delete cascade,
    user_id uuid not null references auth.users(id) on delete cascade,
    parent_comment_id uuid references public.comments(id) on delete set null,
    body text not null check (char_length(trim(body)) between 1 and 2000),
    created_at timestamptz not null default now(),
    deleted_at timestamptz
);

create index comments_build_id_created_at_idx
    on public.comments (build_id, created_at);

alter table public.comments enable row level security;

create policy "Comments are readable when their build is readable" on public.comments
    for select using (
        deleted_at is null
        and exists (
            select 1 from public.builds b
            where b.id = comments.build_id
            and (b.visibility = 'public' or b.user_id = auth.uid())
        )
    );

-- No insert/update/delete policies — with RLS enabled and no matching
-- policy, direct client writes are denied outright. Only the two
-- functions below can write to this table.

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

revoke all on function public.create_comment(uuid, text) from public;
grant execute on function public.create_comment(uuid, text) to authenticated;

create or replace function public.delete_comment(
    p_comment_id uuid
)
returns public.comments
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_comment public.comments;
    v_build public.builds;
begin
    select * into v_comment from public.comments where id = p_comment_id;

    if v_comment is null or v_comment.deleted_at is not null then
        raise exception 'Comment not found.';
    end if;

    select * into v_build from public.builds where id = v_comment.build_id;

    if v_comment.user_id <> auth.uid() and (v_build is null or v_build.user_id <> auth.uid()) then
        raise exception 'Only the comment author or the project owner can delete this comment.';
    end if;

    update public.comments
        set deleted_at = now()
        where id = p_comment_id
        returning * into v_comment;

    return v_comment;
end;
$$;

revoke all on function public.delete_comment(uuid) from public;
grant execute on function public.delete_comment(uuid) to authenticated;

commit;
