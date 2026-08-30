-- Rollback for: 0044_normalize_user_deletion_fks
--
-- Restores the reconstructed-0000-baseline shape (ON DELETE CASCADE on
-- all three FKs) — this is the documented rollback target for
-- consistency with the tracked migration chain, NOT a claim that this
-- shape is correct or recommended. Production is documented (per
-- docs/OPERATIONS.md §10 and 0044's own header) to NOT have these
-- cascades. Only run this rollback with that in mind — restoring
-- CASCADE here without also reverting every migration that now depends
-- on the NO ACTION shape (0048_self_delete_account.sql's RPC explicitly
-- deletes builds/profiles itself, so it does not break either way, but
-- restoring CASCADE reintroduces the exact ambiguity 0044 resolved).

begin;

alter table public.build_revisions
    drop constraint if exists build_revisions_user_id_fkey;

alter table public.build_revisions
    add constraint build_revisions_user_id_fkey
    foreign key (user_id) references auth.users(id) on delete cascade;

alter table public.builds
    add constraint builds_user_id_fkey
    foreign key (user_id) references auth.users(id) on delete cascade;

alter table public.profiles
    add constraint profiles_id_fkey
    foreign key (id) references auth.users(id) on delete cascade;

commit;
