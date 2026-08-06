-- Migration: 0022_component_submissions
-- Milestone: 19 — Structured Parts Catalog & Import Architecture
-- Status: PROPOSED — not yet applied. Depends on 0020 (public.components,
-- catalog_moderators, is_catalog_moderator()) and 0021 (public.component_aliases).
--
-- Full design: docs/milestones/MILESTONE_19_PARTS_CATALOG_ARCHITECTURE.md §4.1.
--
--   This is the only path an ordinary authenticated user has toward
--   ever creating a canonical catalog entry — components itself (0020)
--   only accepts inserts from a catalog_moderators-flagged user. A user
--   whose typed value has no catalog match can always save it as free
--   text on their own build (componentId: null — no table here is
--   involved in that at all), and can additionally submit it as a
--   candidate for the shared catalog via this table.
--
--   status stays 'pending' at insert time by construction (the insert
--   policy's with check enforces it) — a submitter cannot set their own
--   submission to 'approved'. The only way status changes is through the
--   two SECURITY DEFINER functions below, both of which verify the
--   caller is a catalog moderator before doing anything.
--
--   approve_component_submission(submission_id, alias_of_component_id)
--   has two dispositions in one function: alias_of_component_id omitted
--   creates a brand-new components row from the submission; provided,
--   it instead attaches the submission's name as a component_aliases
--   entry on that existing component ("this is the same part, just
--   worded differently") and resolves the submission to that existing
--   id. Either way the submission's resolution is atomic with the
--   catalog write — no path where a submission is marked approved
--   without a corresponding components/component_aliases row existing,
--   or vice versa.
--
--   reject_component_submission(submission_id, note) is the third
--   disposition (spam, invalid, out of scope) — no catalog write at all.
--
--   SQL/security audit pass (2026-07-31): added a status-consistency
--   check constraint, non-empty checks, a FOR UPDATE row lock in
--   approve_component_submission() (closes a race where two concurrent
--   approvals of the same submission could both proceed and orphan one
--   insert), two symmetric cross-table collision guards (an alias
--   colliding with a different component's canonical name, and a new
--   component colliding with an existing alias of a different
--   component), explicit execute grants on both RPCs, and a minimal
--   per-user pending-submission cap
--   (enforce_component_submission_pending_cap()) as an anti-spam
--   safeguard ahead of public beta. See
--   docs/milestones/MILESTONE_19_SQL_SECURITY_AUDIT.md for the full audit.
--
-- Production-compatibility review (same pass that rewrote 0020/0021):
-- component_submissions itself is a wholly new table on every install
-- path — nothing in production predates it, so it needed no changes at
-- all. approve_component_submission()/reject_component_submission()
-- were reviewed line by line against the corrected components/
-- component_aliases schema and also need NO functional changes:
--   - Every column both functions read or write (technology_id,
--     field_key, canonical_name, manufacturer, created_by, component_id,
--     alias, normalized_name, normalized_alias) still exists, unchanged
--     in name or meaning, on the compatible schema.
--   - The new-component INSERT (technology_id, field_key,
--     canonical_name, manufacturer, created_by) and the alias INSERT
--     (component_id, alias) both fire 0020's/0021's sync triggers
--     automatically — component_type/canonical_key (components) and
--     alias_key (component_aliases) are populated transparently on
--     every approval, on both a fresh database and production's legacy
--     one, without this file needing to know those legacy columns
--     exist at all. This is what "approval must populate both legacy
--     compatibility fields and any newer fields consistently" means in
--     practice here: the consistency guarantee lives in one place (the
--     triggers), not duplicated into every INSERT statement that could
--     ever write to these tables — including a future one this file
--     doesn't anticipate.
--
-- Touches: none (one new table, three new functions — the two moderation
-- RPCs plus the anti-spam trigger function). Depends on public.components,
-- public.catalog_moderators, public.is_catalog_moderator() (0020) and
-- public.component_aliases (0021).
--
-- Rollback: see 0022_component_submissions_rollback.sql in supabase/rollbacks/.

begin;

create table public.component_submissions (
    id uuid primary key default gen_random_uuid(),
    technology_id text not null
        check (char_length(trim(technology_id)) > 0),
    field_key text not null
        check (char_length(trim(field_key)) > 0),
    submitted_name text not null
        check (char_length(trim(submitted_name)) > 0),
    normalized_name text generated always as (
        regexp_replace(lower(submitted_name), '[^a-z0-9]', '', 'g')
    ) stored,
    manufacturer text,
    submitted_by uuid not null references auth.users(id) on delete cascade,
    status text not null default 'pending'
        check (status in ('pending', 'approved', 'rejected')),
    resolved_component_id uuid references public.components(id) on delete set null,
    moderator_id uuid references auth.users(id) on delete set null,
    moderator_note text,
    created_at timestamptz not null default now(),
    reviewed_at timestamptz,

    -- A pending row carries no resolution metadata yet; an approved row
    -- must carry all three (it always resolves to a real components row,
    -- whether newly created or an existing one via the alias path); a
    -- rejected row must be reviewed but never gets a resolved_component_id
    -- (rejection creates no catalog write). This is what stops the two
    -- moderation RPCs below from ever leaving a row in a state their own
    -- logic wouldn't produce — e.g. an 'approved' row with no
    -- resolved_component_id, which would mean the catalog write silently
    -- didn't happen despite the status saying it did.
    constraint component_submissions_status_consistency check (
        (status = 'pending'
            and resolved_component_id is null
            and moderator_id is null
            and reviewed_at is null)
        or (status = 'approved'
            and resolved_component_id is not null
            and moderator_id is not null
            and reviewed_at is not null)
        or (status = 'rejected'
            and resolved_component_id is null
            and moderator_id is not null
            and reviewed_at is not null)
    )
);

-- Not unique — the same (or a near-duplicate) name can legitimately be
-- submitted by more than one user before a moderator resolves any of
-- them. A moderator reviewing one pending submission can use this index
-- to spot likely-duplicate pending submissions sitting alongside it, but
-- the database doesn't enforce dedup at this stage — that's what the
-- moderator's review judgment (and components/component_aliases'
-- uniqueness constraints, enforced at approval time) are for.
create index component_submissions_technology_field_normalized_idx
    on public.component_submissions (technology_id, field_key, normalized_name);

create index component_submissions_status_idx
    on public.component_submissions (status)
    where status = 'pending';

alter table public.component_submissions enable row level security;

create policy "Users can view their own submissions" on public.component_submissions
    for select
    to authenticated
    using (auth.uid() = submitted_by);

create policy "Moderators can view all submissions" on public.component_submissions
    for select
    to authenticated
    using (public.is_catalog_moderator(auth.uid()));

create policy "Authenticated users can submit components" on public.component_submissions
    for insert
    to authenticated
    with check (auth.uid() = submitted_by and status = 'pending');

-- A submitter may withdraw their own submission only while it's still
-- unreviewed — once a moderator has resolved it, the record stays as
-- the audit trail for that decision.
create policy "Users can withdraw their own pending submissions" on public.component_submissions
    for delete
    to authenticated
    using (auth.uid() = submitted_by and status = 'pending');

-- No update policy for anyone — status transitions only ever happen
-- inside the two SECURITY DEFINER functions below, which run with the
-- function owner's privileges and so aren't subject to this table's RLS
-- policies at all.

-- Minimal anti-spam safeguard ahead of public beta: caps how many PENDING
-- submissions one user can have open at once. Deliberately minimal — it
-- stops a single account from flooding the moderation queue with bulk
-- junk, but does nothing against multi-account abuse or slow-drip
-- low-quality submissions staying under the cap. That remaining gap is
-- tracked, not overlooked — see docs/ROADMAP.md's Backlog and
-- docs/milestones/MILESTONE_19_SQL_SECURITY_AUDIT.md §5.
--
-- Intentionally SECURITY INVOKER (the default — no "security definer"
-- here, unlike this file's other two functions): the count only ever
-- reads new.submitted_by's own rows, which they already have legitimate
-- SELECT access to via the "Users can view their own submissions" policy
-- above, so running as the caller's own privileges is sufficient and
-- avoids granting more than this function needs.
create function public.enforce_component_submission_pending_cap()
returns trigger
language plpgsql
set search_path = public
as $$
declare
    v_pending_count integer;
begin
    select count(*) into v_pending_count
        from public.component_submissions
        where submitted_by = new.submitted_by and status = 'pending';

    if v_pending_count >= 20 then
        raise exception 'You have too many pending component submissions (limit 20) — wait for some to be reviewed before submitting more';
    end if;

    return new;
end;
$$;

revoke execute on function public.enforce_component_submission_pending_cap() from public;

create trigger enforce_component_submission_pending_cap
    before insert on public.component_submissions
    for each row
    execute function public.enforce_component_submission_pending_cap();

create function public.approve_component_submission(
    p_submission_id uuid,
    p_alias_of_component_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    v_submission public.component_submissions;
    v_component_id uuid;
begin
    if not public.is_catalog_moderator(auth.uid()) then
        raise exception 'Only a catalog moderator may approve a submission';
    end if;

    -- FOR UPDATE locks this row for the rest of the transaction — without
    -- it, two concurrent approve calls on the same submission (two
    -- moderators, or one double-click) could both pass this check before
    -- either commits its UPDATE below, both insert a components/
    -- component_aliases row, and the second UPDATE would silently
    -- overwrite the first's resolution — leaving the first call's insert
    -- orphaned (never referenced by resolved_component_id) with no error
    -- raised anywhere. With the lock, the second call blocks here until
    -- the first transaction commits, then re-reads status as no longer
    -- 'pending' and correctly falls into the "not found" branch below.
    select * into v_submission
        from public.component_submissions
        where id = p_submission_id and status = 'pending'
        for update;

    if not found then
        raise exception 'Submission % not found or already resolved', p_submission_id;
    end if;

    if p_alias_of_component_id is null then
        -- Mirror image of the alias-branch guard below: components'
        -- own unique index only protects against colliding with another
        -- component's normalized_name, not against colliding with an
        -- existing *alias* of some other component in the same slot.
        -- Without this check, a moderator could approve "as new" a name
        -- that's already how a different existing component is known by
        -- shorthand — creating two catalog entries for what a lookup
        -- would otherwise have already resolved as the same real part.
        perform 1 from public.component_aliases
            where technology_id = v_submission.technology_id
                and field_key = v_submission.field_key
                and normalized_alias = v_submission.normalized_name;

        if found then
            raise exception 'This normalized name is already registered as an alias of an existing component — approve as an alias of that component instead of creating a new one';
        end if;

        insert into public.components (technology_id, field_key, canonical_name, manufacturer, created_by)
        values (
            v_submission.technology_id,
            v_submission.field_key,
            v_submission.submitted_name,
            v_submission.manufacturer,
            auth.uid()
        )
        returning id into v_component_id;
    else
        perform 1 from public.components
            where id = p_alias_of_component_id
                and technology_id = v_submission.technology_id
                and field_key = v_submission.field_key;

        if not found then
            raise exception 'Component % is not a valid alias target for this submission''s technology/field', p_alias_of_component_id;
        end if;

        -- Guards a gap neither table's own unique index can catch on its
        -- own: components' uniqueness is scoped to components.normalized_name,
        -- and component_aliases' uniqueness is scoped to
        -- component_aliases.normalized_alias — two different indexes on
        -- two different tables, so nothing stops this submission's
        -- normalized text from being approved as an alias of component A
        -- while an entirely different component B already canonically
        -- owns that exact normalized name in the same technology/field
        -- slot. (The reverse case — this alias colliding with an
        -- *existing alias* of a different component — is already caught
        -- by component_aliases' own unique index and doesn't need a
        -- manual check here.)
        perform 1 from public.components
            where technology_id = v_submission.technology_id
                and field_key = v_submission.field_key
                and normalized_name = v_submission.normalized_name
                and id <> p_alias_of_component_id;

        if found then
            raise exception 'A different component already canonically owns this normalized name in this technology/field — resolve the conflict manually rather than approving as an alias';
        end if;

        insert into public.component_aliases (component_id, alias)
        values (p_alias_of_component_id, v_submission.submitted_name);

        v_component_id := p_alias_of_component_id;
    end if;

    update public.component_submissions
        set status = 'approved',
            resolved_component_id = v_component_id,
            moderator_id = auth.uid(),
            reviewed_at = now()
        where id = p_submission_id;

    return v_component_id;
end;
$$;

-- Explicit grant, not left to ambient PUBLIC default — this function
-- already self-checks is_catalog_moderator() internally and raises for
-- anyone else, so a non-moderator calling it fails either way, but
-- restricting the grant to authenticated means an unauthenticated (anon)
-- caller can't invoke it at all, rather than reaching the function body
-- only to be rejected there. Defense in depth, not a functional gap fix.
revoke execute on function public.approve_component_submission(uuid, uuid) from public;
grant execute on function public.approve_component_submission(uuid, uuid) to authenticated;

create function public.reject_component_submission(
    p_submission_id uuid,
    p_note text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    if not public.is_catalog_moderator(auth.uid()) then
        raise exception 'Only a catalog moderator may reject a submission';
    end if;

    update public.component_submissions
        set status = 'rejected',
            moderator_id = auth.uid(),
            moderator_note = p_note,
            reviewed_at = now()
        where id = p_submission_id and status = 'pending';

    if not found then
        raise exception 'Submission % not found or already resolved', p_submission_id;
    end if;
end;
$$;

revoke execute on function public.reject_component_submission(uuid, text) from public;
grant execute on function public.reject_component_submission(uuid, text) to authenticated;

commit;
