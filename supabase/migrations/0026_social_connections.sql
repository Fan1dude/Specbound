-- Migration: 0026_social_connections
-- Milestone: 22 (Community Foundation)
-- Status: PROPOSED — not yet applied. Depends on 0000-0025 being applied
-- first.
--
-- Full design: docs/milestones/MILESTONE_22_COMMUNITY_FOUNDATION_SPECIFICATION.md
-- §4, §0.1.
--
-- Purpose: mirrors a builder's connected Discord identity so it can be
-- displayed (optionally, owner-controlled) and re-synced, without this
-- application ever storing an OAuth token. Discord OAuth itself is
-- handled entirely by Supabase Auth's native identity-linking
-- (supabase.auth.linkIdentity()) — this app has no server/edge-function
-- layer anywhere to safely hold a client secret, and Supabase Auth
-- already does this token exchange as a built-in feature. Tokens live
-- only in Supabase's own auth schema, never in a table this app
-- controls.
--
--   provider is CHECK-constrained to a single value ('discord') today —
--   per spec §0.1, this is a shape ready for a second OAuth provider
--   (LinkedIn, Twitch, etc.), not a system that supports one yet.
--   Widening the CHECK later is a one-line migration that moves no data,
--   the same pattern already used for notifications.type's 'reply'
--   reservation (0011_notifications.sql). Column names are
--   provider-neutral (provider_user_id/provider_username/
--   provider_avatar_url) for the same reason. The sync RPC below stays
--   Discord-specific by name and is not parameterized by provider — the
--   generalization is in the storage shape only, not in a multi-provider
--   OAuth handling system nobody has asked to build yet.
--
--   Two unique constraints: (user_id, provider) — one connection per
--   provider per builder; (provider, provider_user_id) — one external
--   identity can't back two Specbound accounts on the same provider,
--   enforced at the database level, not just assumed.
--
--   is_public defaults false — connecting Discord (for future
--   verification/role-sync purposes) never implies public display;
--   those are two independently-controlled decisions. Two SELECT
--   policies express that split: the owner can always see their own
--   row, and everyone else can only see it when is_public = true.
--
--   sync_discord_identity() is the only way a row is ever created or
--   updated. auth.identities is not exposed to PostgREST/RLS for direct
--   client reads — SECURITY DEFINER is what lets this function read it
--   at all, scoped to the caller's own identities only (the WHERE
--   clause is auth.uid() itself, never a parameter, so no caller can
--   ever read anyone else's linked identity through this function).
--   Deleting a connection is a plain owner-scoped RLS DELETE policy, not
--   a function — no auth.identities read is needed to remove a row, so
--   there's no reason to route it through SECURITY DEFINER the way
--   creation must be.
--
-- Touches: none (one new table, one new function).
--
-- Rollback: see 0026_social_connections_rollback.sql in supabase/rollbacks/.

begin;

create table public.social_connections (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    provider text not null check (provider in ('discord')),
    provider_user_id text not null check (char_length(trim(provider_user_id)) > 0),
    provider_username text not null check (char_length(trim(provider_username)) > 0),
    provider_avatar_url text,
    is_public boolean not null default false,
    connected_at timestamptz not null default now(),
    last_synced_at timestamptz not null default now(),

    unique (user_id, provider),
    unique (provider, provider_user_id)
);

create index social_connections_public_idx
    on public.social_connections (user_id)
    where is_public = true;

alter table public.social_connections enable row level security;

create policy "Users can view their own connected accounts" on public.social_connections
    for select
    to authenticated
    using (auth.uid() = user_id);

-- Public profile pages need to read is_public connections for anyone —
-- a separate policy, not "using (true)" on the row generally, so a
-- connection is only ever readable by a stranger when the owner has
-- explicitly opted into display.
create policy "Anyone can view a publicly-shown connected account" on public.social_connections
    for select
    using (is_public = true);

create policy "Users can disconnect their own connected account" on public.social_connections
    for delete
    to authenticated
    using (auth.uid() = user_id);

create policy "Users can change their own display visibility" on public.social_connections
    for update
    to authenticated
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

create or replace function public.sync_discord_identity()
returns public.social_connections
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_identity jsonb;
    v_result public.social_connections;
begin
    if auth.uid() is null then
        raise exception 'You must be signed in.';
    end if;

    select identity_data into v_identity
    from auth.identities
    where user_id = auth.uid() and provider = 'discord'
    order by last_sign_in_at desc
    limit 1;

    if v_identity is null then
        raise exception 'No linked Discord account found. Connect Discord first.';
    end if;

    insert into public.social_connections (user_id, provider, provider_user_id, provider_username, provider_avatar_url, last_synced_at)
    values (
        auth.uid(),
        'discord',
        v_identity->>'provider_id',
        coalesce(v_identity->>'global_name', v_identity->>'user_name', v_identity->>'full_name'),
        v_identity->>'avatar_url',
        now()
    )
    on conflict (user_id, provider) do update set
        provider_user_id = excluded.provider_user_id,
        provider_username = excluded.provider_username,
        provider_avatar_url = excluded.provider_avatar_url,
        last_synced_at = now()
    returning * into v_result;

    return v_result;
end;
$$;

revoke all on function public.sync_discord_identity() from public;
grant execute on function public.sync_discord_identity() to authenticated;

commit;
