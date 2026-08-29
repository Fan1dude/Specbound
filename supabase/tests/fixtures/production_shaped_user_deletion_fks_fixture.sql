-- Fixture: production_shaped_user_deletion_fks_fixture.sql
--
-- Converts a freshly-reset local database (0000-0043 applied, which per
-- the reconstructed 0000_baseline_pre_tracked_tables.sql creates
-- profiles.id/builds.user_id/build_revisions.user_id as ON DELETE
-- CASCADE) into the shape production is actually confirmed to have
-- (see supabase/migrations/0044_normalize_user_deletion_fks.sql's own
-- header): no FK at all on profiles.id/builds.user_id, and
-- build_revisions.user_id's FK present but NO ACTION, not CASCADE.
--
-- Run this BEFORE applying migration 0044, so
-- migration_0044_legacy_upgrade.test.sql exercises 0044 against the
-- real starting shape it has to converge, not just the reconstructed
-- baseline's shape. This intentionally does NOT touch
-- build_revisions.build_id (builds -> cascade, 0000) or
-- profiles.featured_build_id (builds -> set null, 0024) — both sources
-- already agree on those, so this fixture leaves them untouched.
--
-- Never run this against anything other than a disposable local
-- Supabase/Docker database that already has 0000-0043 applied.

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
    end if;
end $$;

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
    end if;
end $$;

do $$
declare
    v_conname text;
begin
    select conname into v_conname
    from pg_constraint
    where conrelid = 'public.build_revisions'::regclass
      and contype = 'f'
      and confrelid = 'auth.users'::regclass;

    if v_conname is not null then
        execute format('alter table public.build_revisions drop constraint %I', v_conname);
    end if;

    alter table public.build_revisions
        add constraint build_updates_user_id_fkey
        foreign key (user_id) references auth.users(id);
end $$;
