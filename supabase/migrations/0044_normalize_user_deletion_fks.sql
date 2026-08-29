-- Migration: 0044_normalize_user_deletion_fks
-- Milestone: none — Launch Readiness self-service account deletion,
-- foundation pass. Status: PROPOSED — not yet applied. Depends on
-- 0000-0043 being applied first.
--
-- Purpose: converge a documented schema-drift discrepancy, additively
-- and idempotently, so account deletion can be built against one known
-- shape regardless of which shape a given environment actually starts
-- from.
--
--   0000_baseline_pre_tracked_tables.sql (itself an inferred
--   reconstruction of pre-tracking state, by its own extensive internal
--   commentary — never an executed migration) defines:
--     profiles.id          references auth.users(id) on delete cascade
--     builds.user_id        references auth.users(id) on delete cascade
--     build_revisions.user_id references auth.users(id) on delete cascade
--
--   docs/OPERATIONS.md §10 documents the opposite, sourced from a direct,
--   dated, live `pg_constraint`/`information_schema` introspection
--   against the linked production project (2026-08-15) — and has since
--   been directly re-confirmed against production for this migration:
--     profiles.id          — NO foreign key to auth.users at all
--     builds.user_id         — NO foreign key to auth.users at all
--     build_revisions.user_id — HAS a foreign key to auth.users, but with
--                                NO ON DELETE action (defaults to
--                                NO ACTION/RESTRICT, blocking a delete
--                                unless this column is cleared first)
--
--   Production is now confirmed authoritative. This migration converges
--   BOTH possible starting shapes — a fresh install built from the
--   reconstructed 0000 baseline, and the real, already-live production
--   shape — to the production-confirmed target, using read-before-write
--   PL/pgSQL rather than a blind DROP/ADD that would error on whichever
--   shape doesn't currently match what it assumes. Running this
--   migration against either starting shape is safe and produces the
--   identical end state; running it twice against the same
--   already-converged database is a no-op, not an error.
--
--   Deliberately NOT touched, per explicit instruction and because both
--   sources already agree on them:
--     build_revisions.build_id references public.builds(id)
--       on delete cascade (0000) — untouched.
--     profiles.featured_build_id references public.builds(id)
--       on delete set null (0024) — untouched.
--
--   Why this matters for account deletion specifically: with this
--   migration applied, `builds`/`profiles` are NEVER automatically
--   cleaned up by deleting `auth.users` — they must be explicitly
--   deleted first (or in the same transaction) by whatever performs the
--   deletion, exactly as docs/OPERATIONS.md §10.6 already does by hand.
--   0048_self_delete_account.sql's RPC does this explicitly and
--   defensively regardless of this migration's outcome, so this
--   migration is what makes that RPC's assumptions actually true, not a
--   substitute for the RPC's own explicit statements.
--
-- Touches: profiles (drops a stray FK to auth.users if present), builds
-- (same), build_revisions (normalizes its auth.users FK to NO ACTION,
-- adding it fresh if entirely absent). No column added or removed, no
-- table created, no data touched.
--
-- Rollback: see 0044_normalize_user_deletion_fks_rollback.sql in
-- supabase/rollbacks/. Restores the reconstructed-baseline shape
-- (CASCADE on all three) — see that file's own header for why this is
-- the documented, not-necessarily-recommended, rollback target.

begin;

-- --- profiles.id: drop any FK to auth.users, if one exists -------------
do $$
declare
    v_conname text;
begin
    select conname into v_conname
    from pg_constraint
    where conrelid = 'public.profiles'::regclass
      and contype = 'f'
      and confrelid = 'auth.users'::regclass;

    if v_conname is not null then
        execute format('alter table public.profiles drop constraint %I', v_conname);
        raise notice 'Dropped % (profiles -> auth.users FK)', v_conname;
    else
        raise notice 'profiles has no FK to auth.users already — nothing to drop';
    end if;
end $$;

-- --- builds.user_id: drop any FK to auth.users, if one exists ----------
do $$
declare
    v_conname text;
begin
    select conname into v_conname
    from pg_constraint
    where conrelid = 'public.builds'::regclass
      and contype = 'f'
      and confrelid = 'auth.users'::regclass;

    if v_conname is not null then
        execute format('alter table public.builds drop constraint %I', v_conname);
        raise notice 'Dropped % (builds -> auth.users FK)', v_conname;
    else
        raise notice 'builds has no FK to auth.users already — nothing to drop';
    end if;
end $$;

-- --- build_revisions.user_id: ensure the FK exists with NO ACTION ------
-- pg_constraint.confdeltype: 'a' = NO ACTION (the target shape), 'c' =
-- CASCADE, 'n' = SET NULL, 'r' = RESTRICT. Only 'a' is left alone.
do $$
declare
    v_conname text;
    v_confdeltype "char";
begin
    select conname, confdeltype into v_conname, v_confdeltype
    from pg_constraint
    where conrelid = 'public.build_revisions'::regclass
      and contype = 'f'
      and confrelid = 'auth.users'::regclass;

    if v_conname is null then
        alter table public.build_revisions
            add constraint build_revisions_user_id_fkey
            foreign key (user_id) references auth.users(id);
        raise notice 'Added build_revisions_user_id_fkey (NO ACTION) — none existed';
    elsif v_confdeltype <> 'a' then
        execute format('alter table public.build_revisions drop constraint %I', v_conname);
        alter table public.build_revisions
            add constraint build_revisions_user_id_fkey
            foreign key (user_id) references auth.users(id);
        raise notice 'Replaced % (was not NO ACTION) with build_revisions_user_id_fkey (NO ACTION)', v_conname;
    else
        raise notice '% is already NO ACTION — nothing to do', v_conname;
    end if;
end $$;

commit;
