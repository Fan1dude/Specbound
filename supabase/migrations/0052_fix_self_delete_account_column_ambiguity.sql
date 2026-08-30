-- Migration: 0052_fix_self_delete_account_column_ambiguity
-- Milestone: none — Launch Readiness self-service account deletion,
-- fourth security-review fix (the first ACTUAL RUNTIME FAILURE this PR
-- has hit — every prior fix in this PR was found by static/structural
-- review; this one was only found by real execution against a local
-- Supabase/Docker stack). Status: PROPOSED — not yet applied. Depends
-- on 0000-0051 being applied first.
--
-- Purpose: fixes a real, confirmed runtime bug in `self_delete_account(uuid)`
-- (0049) — its RETRY branch is currently completely broken:
--
--   ERROR: column reference "storage_paths" is ambiguous
--   DETAIL: It could refer to either a PL/pgSQL variable or a table
--     column.
--   CONTEXT: PL/pgSQL function self_delete_account(uuid) line 110
--
-- Root cause: `self_delete_account(uuid)`'s own signature is
-- `returns table(job_id uuid, storage_paths text[])` — in PL/pgSQL,
-- every column named in a `RETURNS TABLE(...)` clause becomes an
-- implicitly-declared OUT variable, in scope for the ENTIRE function
-- body, with EXACTLY the name given. `storage_paths` is therefore both
-- (a) a PL/pgSQL variable (the function's own second OUT parameter) and
-- (b) `public.account_deletion_jobs.storage_paths`, a real table
-- column of the identical name. The retry branch's own query --
--   select storage_paths into v_paths from public.account_deletion_jobs
--       where id = v_existing_job_id;
-- -- has a bare, unqualified `storage_paths` in its SELECT list, which
-- Postgres cannot resolve between those two candidates, and raises
-- rather than silently guessing. This is a genuine function bug, not a
-- test-harness artifact: real local execution of
-- `migration_0049_account_deletion_challenge.test.sql` hit this exact
-- error at its own retry test (7e/7f), which had been written and
-- reviewed correctly, but had never actually been RUN until this pass
-- (this PR's own repeated, honest disclosure that no SQL had been
-- executed applies here too — this class of bug is exactly what static
-- review alone cannot catch).
--
-- Full audit of `self_delete_account(uuid)` for the SAME collision
-- class, as required by this review — every `SELECT ... INTO`,
-- `RETURNING ... INTO`, and bare table-column reference in the function
-- body, checked against BOTH its own OUT parameters (`job_id`,
-- `storage_paths`) and its declared local variables (`v_user_id`,
-- `v_job_id`, `v_paths`, `v_existing_job_id`, `v_consumed_user_id`):
--
--   - `storage_paths` (the retry branch's `SELECT ... INTO v_paths`) —
--     THE bug above. Fixed.
--   - `job_id` — checked explicitly, since the review asked for it by
--     name. Does NOT collide with anything: `account_deletion_jobs`'s
--     own primary key column is named `id`, not `job_id` — no table
--     column anywhere in this function's body is literally named
--     `job_id`, so this OUT parameter was never actually at risk. (The
--     function's own `RETURNING id INTO v_job_id` maps the `id` column
--     into the *local variable* `v_job_id`, a different name again —
--     never ambiguous.)
--   - `state` — checked explicitly. Not a PL/pgSQL variable anywhere in
--     this function (no `declare` entry named `state`, and it is not an
--     OUT parameter) — every bare `state` reference (the `UPDATE ...
--     SET state = 'db_prepared'` in the retry branch, and the same
--     column name used identically inside the INSERT's own target
--     column list on the first-call branch) refers unambiguously to the
--     table column; an UPDATE's `SET` target list is always resolved
--     against the target table's own columns, never against PL/pgSQL
--     variables, regardless of naming. Not affected, not changed here.
--   - Every other bare table-column reference in the function (the
--     Storage-path capture UNION ALL's `avatar_path`/`storage_path`
--     columns, `former_user_id`, `user_id`, `released_at`, `token`,
--     `expires_at`) was checked against both OUT parameters and all
--     five local variables — none collide (all five local variables use
--     the `v_` prefix convention this codebase already follows
--     throughout, which is exactly why none of THEM ever collided with
--     a real column; `job_id`/`storage_paths` are the two OUT
--     parameters, unprefixed by that convention because their names are
--     fixed by the function's public signature/return shape, which is
--     what let this one slip through).
--
-- THE FIX applied here goes beyond patching the one broken line: EVERY
-- table reference in the recreated function body below now carries an
-- explicit alias (`adc` for account_deletion_challenges, `lh` for
-- legal_holds, `adj` for account_deletion_jobs, `pr` for profiles, `b`
-- for builds, `br` for build_revisions, `rm` for revision_media, `pd`
-- for project_drafts, `pm` for project_media), and every SELECT-list/
-- WHERE/RETURNING column reference is qualified by it. This is
-- deliberately more than the minimum fix for the one broken line: it
-- means any FUTURE change to this function's OUT parameter names, or to
-- `account_deletion_jobs`'s own column names, cannot silently
-- reintroduce this exact class of bug undetected — an unqualified bare
-- reference would now stand out as inconsistent with the rest of the
-- function, not blend in the way the original, mostly-unqualified style
-- let this one hide until real execution.
--
-- `UPDATE`'s own `SET` target-column list is Postgres grammar-level
-- always a bare, unqualified column name (`SET state = 'db_prepared'`,
-- never `SET adj.state = 'db_prepared'` — the latter is a syntax
-- error) — those are left bare throughout, correctly, not an
-- inconsistency with the qualification elsewhere.
--
-- `INSERT INTO public.account_deletion_jobs (...)`'s own target column
-- list is likewise always bare table-column names by grammar, not
-- expressions needing qualification — unaffected. Its `RETURNING`
-- clause, however, DOES reference a real query output and is qualified
-- here (`RETURNING adj.id INTO v_job_id`, via `INSERT INTO ... AS adj`,
-- valid Postgres syntax since 9.5).
--
-- Audit of the 0050 recovery functions for the SAME ambiguity class, as
-- required by this review:
--
--   - `claim_account_deletion_jobs()` — `LANGUAGE sql`, not `plpgsql`;
--     SQL-language functions have no `DECLARE`d variables to collide
--     with at all. Its own parameters (`p_worker_id`, `p_limit`,
--     `p_lease_seconds`, `p_max_attempts`) share no name with any
--     `account_deletion_jobs` column. `RETURNS SETOF public.account_deletion_jobs`
--     returns whole rows of the table's own type directly — it does
--     NOT declare a custom `RETURNS TABLE(name type, ...)` shape the
--     way `self_delete_account()` does, so this specific bug class
--     (an OUT-parameter name colliding with a same-named column) cannot
--     arise here structurally. Not affected.
--   - `record_account_deletion_auth_result(p_job_id, p_success,
--     p_error_code, p_max_attempts)` — `RETURNS boolean` (not
--     `TABLE(...)`), so it has no named OUT parameters at all; its two
--     declared locals (`v_rows`, `v_new_attempts`) collide with nothing.
--     Its own bare column references (`state`, `recovery_attempts`,
--     `claimed_at`, `claimed_by`, `last_error_code`) match neither its
--     parameters (all `p_`-prefixed) nor its locals (both `v_`-prefixed).
--     Not affected.
--   - `record_account_deletion_storage_result(p_job_id,
--     p_remaining_paths, p_error_code, p_max_attempts)` — same shape,
--     `RETURNS boolean`. Its parameter is `p_remaining_paths`, NOT
--     `storage_paths` — the one detail that would have mattered here,
--     and it does not match. Its bare column references
--     (`storage_paths`, `state`, `storage_cleanup_attempts`,
--     `claimed_at`, `claimed_by`, `last_error_code`, `completed_at`)
--     collide with neither its `p_`-prefixed parameters nor its
--     `v_`-prefixed locals. Not affected.
--
--   None of the three 0050 functions are modified by this migration —
--   the audit above found nothing to fix in them. `0050`'s own file is
--   not touched either way, consistent with this repository's
--   "additive only, never rewrite an already-committed migration"
--   convention applying just as much to a migration with no bug found
--   in it as to one that does.
--
-- Touches: `public.self_delete_account(uuid)` only — same signature,
-- same `RETURNS TABLE(job_id uuid, storage_paths text[])` shape, same
-- grants; only the function BODY changes (full column-reference
-- qualification, and therefore the actual bug fix). Does not modify
-- `0049`'s own file, and does not touch `account_deletion_jobs`'s
-- schema, `request_account_deletion_challenge()`, or any `0050`
-- function.
--
-- Rollback: see 0052_fix_self_delete_account_column_ambiguity_rollback.sql
-- in supabase/rollbacks/. Restores `0049`'s ORIGINAL, broken function
-- body verbatim — explicitly disclosed in that file's own header as
-- reintroducing this exact "column reference storage_paths is
-- ambiguous" runtime error, making the retry path unusable again. No
-- data-loss guard is needed (this migration never drops or alters any
-- column, row, or table — only a function body), unlike the guards on
-- `0046`/`0047`/`0050`'s own rollbacks.

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

    -- Atomic single-use consumption — the row's absence afterward IS
    -- the guarantee; no separate flag, no check-then-update window. A
    -- missing/expired/foreign/already-consumed token all fail
    -- identically, checked before the legal-hold query below so this
    -- rejection never implies anything about hold status either way.
    delete from public.account_deletion_challenges as adc
        where adc.user_id = v_user_id
          and adc.token = p_challenge_token
          and adc.expires_at > now()
        returning adc.user_id into v_consumed_user_id;

    if v_consumed_user_id is null then
        raise exception 'Deletion authorization is invalid or has expired. Request a new one and try again.';
    end if;

    -- Legal hold — checked first among the account-state checks, before
    -- any other read or write. Never distinguishes this failure from
    -- any other in the message text.
    if exists (
        select 1 from public.legal_holds as lh
        where lh.user_id = v_user_id and lh.released_at is null
    ) then
        raise exception 'Your request could not be completed. Contact support@specboundapp.com.';
    end if;

    -- Security-review fix over 0048's original ordering: which branch
    -- runs is decided BEFORE any capture/delete happens, and on a
    -- retry, the storage-path capture query is never re-run at all —
    -- see the retry branch's own comment below for why re-running it
    -- would silently lose the originally-captured paths.
    select adj.id into v_existing_job_id
    from public.account_deletion_jobs as adj
    where adj.former_user_id = v_user_id;

    if v_existing_job_id is null then
        -- First call for this account: capture Storage paths BEFORE
        -- any delete below, in the same transaction, so the answer can
        -- never observe a state the deletes have already changed —
        -- same ordering rule 0043_delete_build.sql's own header already
        -- establishes for the identical reason. Legacy avatar_url-only
        -- rows are deliberately excluded (see 0049's own header).
        select coalesce(array_agg(distinct all_paths.p) filter (where all_paths.p is not null), '{}')
        into v_paths
        from (
            select pr.avatar_path as p from public.profiles as pr where pr.id = v_user_id and pr.avatar_path is not null

            union all

            select rm.storage_path as p
            from public.revision_media as rm
            join public.build_revisions as br on br.id = rm.revision_id
            join public.builds as b on b.id = br.build_id
            where b.user_id = v_user_id

            union all

            select pm.storage_path as p
            from public.project_media as pm
            join public.project_drafts as pd on pd.id = pm.draft_id
            where pd.user_id = v_user_id
        ) as all_paths;

        -- builds -> cascades to build_revisions/revision_media/
        -- comments/likes/saved_builds/build_view_cooldowns/
        -- notifications for those builds specifically (pre-existing
        -- FKs, unrelated to 0044).
        delete from public.builds as b
            where b.user_id = v_user_id;

        -- Any build_revisions row this account authored on a build it
        -- does NOT own — clear, never delete (see 0049's own header).
        -- SET's own target column list is always bare per Postgres
        -- grammar (`set user_id = null`, not `set br.user_id = null`)
        -- — not an inconsistency with the qualification elsewhere.
        update public.build_revisions as br
            set user_id = null
            where br.user_id = v_user_id;

        -- No automatic FK does this on production (0044) — explicit,
        -- prevents recreating the known orphan-profile condition
        -- (docs/OPERATIONS.md §10.12).
        delete from public.profiles as pr
            where pr.id = v_user_id;

        insert into public.account_deletion_jobs as adj (former_user_id, state, storage_paths)
            values (v_user_id, 'db_prepared', v_paths)
            returning adj.id into v_job_id;

        insert into public.moderation_actions (actor_id, action_type, target_type, target_id, note)
            values (v_user_id, 'account_deleted', 'profile', v_user_id, 'Self-service account deletion.');
    else
        -- Retry (an earlier successful call already committed builds/
        -- profiles being gone, per the job row's existence): the
        -- capture query above would now find nothing — those source
        -- rows no longer exist — and re-running it would silently
        -- REPLACE the correctly-captured paths from the first call with
        -- an empty array, causing Storage cleanup to skip every file
        -- this account ever used. Reuse the job's already-captured
        -- paths instead; the destructive statements above are also
        -- skipped entirely (they would be harmless no-ops against
        -- already-gone rows, but there is no reason to re-run them).
        --
        -- THE FIX: `adj.storage_paths`, not bare `storage_paths` — the
        -- unqualified form is what this migration exists to fix (see
        -- this migration's own header for the exact runtime error real
        -- local testing hit here).
        select adj.storage_paths into v_paths
        from public.account_deletion_jobs as adj
        where adj.id = v_existing_job_id;

        update public.account_deletion_jobs as adj
            set state = 'db_prepared'
            where adj.id = v_existing_job_id;

        v_job_id := v_existing_job_id;
    end if;

    return query select v_job_id, v_paths;
end;
$$;

revoke all on function public.self_delete_account(uuid) from public;
grant execute on function public.self_delete_account(uuid) to authenticated;

commit;
