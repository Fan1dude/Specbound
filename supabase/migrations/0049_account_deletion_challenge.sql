-- Migration: 0049_account_deletion_challenge
-- Milestone: none — Launch Readiness self-service account deletion,
-- security-review fix. Status: PROPOSED — not yet applied. Depends on
-- 0000-0048 being applied first.
--
-- Purpose: fixes a real gap found in PR review of `0048`. That
-- migration's `self_delete_account()` had no parameters and relied
-- entirely on the delete-account Edge Function checking the caller's
-- JWT `iat` (issued-at) claim to prove "recent password
-- reauthentication." That check was insufficient: Supabase's own
-- refresh-token grant mints a brand-new access token — with a brand-new
-- `iat` — WITHOUT re-verifying the password at all ("refresh tokens...
-- obtain new access tokens without re-authentication," per Supabase's
-- own `auth/sessions` documentation). A normally-refreshed session, or
-- a stolen one that a client silently refreshes, would have passed the
-- old `iat`-only check with no password ever re-entered.
--
--   The correct, GoTrue-native signal is the `amr` (Authentication
--   Methods Reference) claim, NOT `iat`. Confirmed directly against
--   supabase/auth's own source (`internal/models/amr.go`): each
--   `(session_id, authentication_method)` pair is stored as its own row
--   (`mfa_amr_claims`, unique on that pair), inserted/updated only when
--   that SPECIFIC method is actually satisfied. A token refresh records
--   its own `token_refresh`-tagged entry — it never touches the
--   `password` entry's own timestamp for that session. This means the
--   `amr` array's `password` entry timestamp reliably reflects when the
--   password was last genuinely verified for the CURRENT session,
--   immune to routine or malicious token refresh. `auth.jwt()` is
--   Supabase's own supported Postgres helper for reading these verified
--   claims server-side (used the same way in Supabase's own documented
--   MFA/step-up-auth RLS patterns) — this migration reads it directly
--   inside a SECURITY DEFINER function, never trusting anything decoded
--   client-side or by the Edge Function.
--
--   Beyond the `amr` freshness check, this migration adds what the
--   review explicitly required: a short-lived, single-use,
--   server-verifiable authorization artifact, not just a freshness
--   window on an ambient claim (a still-fresh-window JWT could
--   otherwise authorize more than one deletion attempt without a fresh
--   password entry).
--
--   `public.account_deletion_challenges`: one row per user (primary
--   key), RLS enabled, ZERO client policies (same maximally-restrictive
--   pattern as `public.legal_holds`/`public.account_deletion_jobs`) —
--   only `request_account_deletion_challenge()` and
--   `self_delete_account()` below ever read or write it. `ON DELETE
--   CASCADE` to `auth.users` is fine here (unlike
--   `account_deletion_jobs`) — this table is purely a short-lived,
--   pre-deletion artifact; it has no reason to outlive the account.
--
--   `request_account_deletion_challenge()`: `SECURITY DEFINER`, no
--   parameters, derives the caller exclusively from `auth.uid()`.
--   Checks the caller's own `auth.jwt() -> 'amr'` for a `password`
--   entry within the last 5 minutes — fails closed (rejects) if `amr`
--   is absent entirely, matching the coalesce-to-empty-array behavior
--   below. On success, issues a fresh token, replacing (not
--   accumulating) any prior unconsumed challenge for this user —
--   requesting a new one invalidates an old one outright.
--
--   `self_delete_account(p_challenge_token uuid)`: replaces `0048`'s
--   zero-argument version — that version is explicitly DROPPED below,
--   not left behind, since an un-dropped zero-argument overload would
--   remain callable and would completely bypass this fix. The
--   challenge is consumed atomically via a single `DELETE ... WHERE
--   user_id = auth.uid() AND token = p_challenge_token AND expires_at >
--   now() RETURNING ...` — the row's absence after this statement IS
--   the single-use guarantee (no separate "consumed" flag, no
--   check-then-update race window). A caller passing no token, an
--   expired token, someone else's token, or replaying an already-
--   consumed token all fail identically ("Deletion authorization is
--   invalid or has expired.") — this message is distinct from the
--   legal-hold rejection (checked afterward, unchanged from `0048`) on
--   purpose: it's an actionable, safe statement ("go get a new
--   authorization"), not one that reveals anything about the account's
--   state, and it's checked BEFORE the legal-hold query even runs, so a
--   caller without a valid challenge learns nothing about hold status
--   either way.
--
--   Everything else in `self_delete_account()`'s body — Storage-path
--   capture, `builds`/`build_revisions`/`profiles` cleanup, job
--   creation/resumption, the self-attributed audit row exactly once per
--   deletion event — is unchanged from `0048`; only the caller-facing
--   signature and the new leading challenge-consumption step differ.
--
-- Touches: none besides the new table/functions and dropping `0048`'s
-- zero-argument `self_delete_account()`. Does not modify `0044`-`0048`'s
-- own files.
--
-- Rollback: see 0049_account_deletion_challenge_rollback.sql in
-- supabase/rollbacks/. Restores `0048`'s original zero-argument
-- `self_delete_account()` verbatim and drops the new table/RPC —
-- explicitly flagged in the rollback's own header as reintroducing the
-- `iat`-only gap this migration exists to fix, so rolling back requires
-- reintroducing an equivalent protection before this is used again.

begin;

create table public.account_deletion_challenges (
    user_id uuid primary key references auth.users(id) on delete cascade,
    token uuid not null default gen_random_uuid(),
    created_at timestamptz not null default now(),
    expires_at timestamptz not null
);

alter table public.account_deletion_challenges enable row level security;

-- No SELECT/INSERT/UPDATE/DELETE policy for anyone — see this
-- migration's header.

create or replace function public.request_account_deletion_challenge()
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_user_id uuid;
    v_token uuid;
begin
    v_user_id := auth.uid();

    if v_user_id is null then
        raise exception 'You must be signed in.';
    end if;

    -- The GoTrue-native, refresh-immune freshness signal — see this
    -- migration's header for why `amr`, not `iat`, is checked. Fails
    -- closed if the `amr` claim is absent entirely (coalesce to an
    -- empty array, over which `exists` is always false).
    if not exists (
        select 1
        from jsonb_array_elements(coalesce(auth.jwt() -> 'amr', '[]'::jsonb)) as entry
        where entry ->> 'method' = 'password'
          and (entry ->> 'timestamp')::bigint >= extract(epoch from now())::bigint - 300
    ) then
        raise exception 'Recent password verification required. Please re-enter your password and try again.';
    end if;

    v_token := gen_random_uuid();

    insert into public.account_deletion_challenges (user_id, token, created_at, expires_at)
    values (v_user_id, v_token, now(), now() + interval '2 minutes')
    on conflict (user_id) do update
        set token = excluded.token,
            created_at = excluded.created_at,
            expires_at = excluded.expires_at;

    return v_token;
end;
$$;

revoke all on function public.request_account_deletion_challenge() from public;
grant execute on function public.request_account_deletion_challenge() to authenticated;

-- Drops 0048's zero-argument version outright — see this migration's
-- header for why leaving it callable would completely bypass this fix.
drop function if exists public.self_delete_account();

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
    delete from public.account_deletion_challenges
        where user_id = v_user_id
          and token = p_challenge_token
          and expires_at > now()
        returning user_id into v_consumed_user_id;

    if v_consumed_user_id is null then
        raise exception 'Deletion authorization is invalid or has expired. Request a new one and try again.';
    end if;

    -- Legal hold — checked first among the account-state checks, before
    -- any other read or write. Never distinguishes this failure from
    -- any other in the message text.
    if exists (
        select 1 from public.legal_holds
        where user_id = v_user_id and released_at is null
    ) then
        raise exception 'Your request could not be completed. Contact support@specboundapp.com.';
    end if;

    -- Everything below is unchanged from 0048_self_delete_account.sql —
    -- see that migration's own header for the full per-step rationale.
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

revoke all on function public.self_delete_account(uuid) from public;
grant execute on function public.self_delete_account(uuid) to authenticated;

commit;
