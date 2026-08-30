-- Migration: 0048_self_delete_account
-- Milestone: none — Launch Readiness self-service account deletion.
-- Status: PROPOSED — not yet applied. Depends on 0000-0047 being
-- applied first (0044 for the FK-normalization this function relies on
-- being explicit about, 0045 for moderation_actions surviving its own
-- deletion event, 0046 for the legal-hold check, 0047 for the durable
-- job record).
--
-- Purpose: self_delete_account() is the transactional, database-only
-- half of full account deletion. It never touches auth.users itself
-- (Postgres cannot correctly delete a Supabase Auth user — same
-- limitation docs/OPERATIONS.md §10.7 already documents for the manual
-- procedure; that requires the Auth Admin API, called separately by the
-- delete-account Edge Function with a service-role client after this
-- function commits successfully).
--
--   Caller derivation: exclusively auth.uid() — this function takes NO
--   parameters and accepts no user id from anywhere. There is no code
--   path through which a caller can name a different account.
--
--   Legal hold: checked first, before any other read or write. A held
--   account gets the same generic failure text an ordinary error would
--   produce ('Your request could not be completed. Contact
--   support@specboundapp.com.') — never a message distinguishing "you
--   are under legal hold" from any other failure, matching the same
--   "don't leak information via a specific error message" principle
--   js/pages/settings/app.js's own password-change flow already
--   documents for a different flow. public.legal_holds has zero client
--   policies (0046) — this SECURITY DEFINER function is the only thing
--   that can ever read it, and it never returns the row's contents to
--   the caller, only a boolean-shaped abort.
--
--   Job creation/resumption: public.account_deletion_jobs (0047) has a
--   unique index on former_user_id, not a primary key relationship to
--   this call. A second call for the same account (a retried request
--   after an earlier Edge Function crash before admin.deleteUser() ran)
--   is safe and idempotent for the deletes/captures themselves — they
--   re-run against already-gone rows harmlessly — but the AUDIT ROW
--   below must not be inserted twice for one deletion event. This
--   function therefore checks whether a job row already exists for this
--   caller BEFORE deciding whether to insert a fresh audit row: a first
--   call creates both; a retry updates the existing job row's
--   storage_paths/state and skips the audit insert entirely, since the
--   original one already exists and survives (0045).
--
--   Storage-path capture happens BEFORE any delete below, in the same
--   transaction, so the answer can never observe a state the deletes
--   below have already changed — same ordering rule
--   0043_delete_build.sql's own header already establishes for the
--   identical reason. Three sources, unioned: this account's own avatar
--   (avatar_path only — a legacy avatar_url-only row is deliberately
--   SKIPPED here, never resolved or deleted by this function; per
--   product decision, an unverifiable legacy avatar must never block
--   deletion, and its own multi-step host/path/ownership verification
--   — docs/OPERATIONS.md §10.8 — is not something safely done in raw
--   SQL); every project-images path referenced by this account's own
--   published-build history (via build_revisions -> revision_media);
--   every project-images path referenced by this account's own drafts
--   (via project_drafts -> project_media, published or never-published).
--   Unlike delete_build()'s narrower per-build return, no
--   still-referenced-elsewhere dedup is needed here — every draft this
--   account owns is also being removed in this same transaction, so
--   there is no surviving draft whose gallery a path must be protected
--   for. Paths are namespaced by owning userId/draftId, so there is no
--   cross-user path-sharing risk to account for either.
--
--   builds/build_revisions/profiles cleanup — explicit, not left to a
--   FK cascade, because production is confirmed (0044's header) to have
--   NO cascading FK from auth.users to any of these three:
--     1. Delete this account's own builds outright. Cascades (pre-existing
--        ON DELETE CASCADE FKs, unrelated to 0044) through build_revisions
--        -> revision_media, comments, likes, saved_builds,
--        build_view_cooldowns, notifications for those builds — the
--        exact same chain 0043_delete_build.sql already relies on, just
--        applied to every build this account owns instead of one.
--     2. For any build_revisions row still naming this account as
--        user_id afterward (a revision AUTHORED by this account on a
--        build it does NOT own — build_revisions.user_id carries no
--        required relationship to the owning build's own user_id,
--        per docs/OPERATIONS.md §10.3's own query-6 note), clear
--        user_id to null rather than deleting the row — deleting it
--        would corrupt another account's own build history, which this
--        account has no ownership claim over. This also resolves
--        build_revisions.user_id's NO ACTION foreign key (0044) ahead
--        of the later Auth deletion, matching docs/OPERATIONS.md
--        §10.6's own identical reasoning for its manual UPDATE step.
--     3. Delete the profiles row outright — production has no FK to do
--        this automatically (0044's header); skipping this step would
--        recreate the exact orphan-profile condition
--        docs/OPERATIONS.md §10.12 already documents as a known,
--        undesirable historical artifact.
--
--   Every other table (project_drafts -> project_media, comments,
--   likes, saved_builds, follows, social_connections, profile_roles,
--   content_reports.reporter_id, catalog_moderators,
--   component_submissions.submitted_by, saved_setup_categories,
--   notifications, and — once this account's own auth.users row is
--   actually deleted by the Edge Function's later Auth Admin call —
--   moderation_actions.actor_id (0045) — is left to that later,
--   already-correct FK cascade/anonymization. This function does not
--   duplicate any of that.
--
--   Audit row: inserted last, inside this same transaction, attributed
--   to the account's own id (self-service, not a staff-operator action)
--   — survives its own subject's later Auth deletion specifically
--   because of 0045's fix; without that fix this row would destroy
--   itself the instant auth.users is actually removed.
--
-- Returns exactly what the Edge Function needs and nothing else: the
-- job id (so the Edge Function can update job state by primary key
-- without a second lookup) and the captured Storage paths. Never
-- returns legal-hold detail, database error text, or anything about
-- other users.
--
-- Touches: none (one new function only).
--
-- Rollback: see 0048_self_delete_account_rollback.sql in
-- supabase/rollbacks/. Cannot restore any account already deleted
-- through this function — that data loss is real, permanent, and the
-- entire point, same posture 0043's own rollback already documents.

begin;

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

    -- Legal hold — checked first, before any other read or write.
    -- Never distinguishes this failure from any other in the message
    -- text (see this migration's header).
    if exists (
        select 1 from public.legal_holds
        where user_id = v_user_id and released_at is null
    ) then
        raise exception 'Your request could not be completed. Contact support@specboundapp.com.';
    end if;

    -- Resolved once, before any write below, so the audit-insert
    -- decision at the end of this function reflects the state as it
    -- was BEFORE this call's own writes (see this migration's header).
    select id into v_existing_job_id
    from public.account_deletion_jobs
    where former_user_id = v_user_id;

    -- Storage-path capture — before any delete below, in the same
    -- transaction. Legacy avatar_url-only rows are deliberately
    -- excluded (see this migration's header).
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

    -- builds -> cascades to build_revisions/revision_media/comments/
    -- likes/saved_builds/build_view_cooldowns/notifications for those
    -- builds specifically (pre-existing FKs, unrelated to 0044).
    delete from public.builds where user_id = v_user_id;

    -- Any build_revisions row this account authored on a build it does
    -- NOT own — clear, never delete (see this migration's header).
    update public.build_revisions set user_id = null where user_id = v_user_id;

    -- No automatic FK does this on production (0044) — explicit,
    -- prevents recreating the known orphan-profile condition
    -- (docs/OPERATIONS.md §10.12).
    delete from public.profiles where id = v_user_id;

    if v_existing_job_id is null then
        -- First call for this account: create the job row and the
        -- audit row together.
        insert into public.account_deletion_jobs (former_user_id, state, storage_paths)
        values (v_user_id, 'db_prepared', v_paths)
        returning id into v_job_id;

        -- Self-attributed audit row — survives this account's own later
        -- Auth deletion because of 0045's fix; see this migration's
        -- header. Only ever inserted once per deletion event (this
        -- branch), never on a retry.
        insert into public.moderation_actions (actor_id, action_type, target_type, target_id, note)
        values (v_user_id, 'account_deleted', 'profile', v_user_id, 'Self-service account deletion.');
    else
        -- Retry: resume the existing job row, refresh its captured
        -- paths (harmless if unchanged), do NOT insert a second audit
        -- row for the same deletion event.
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
