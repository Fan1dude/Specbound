-- Rollback for: 0040_harden_handle_new_user_search_path
--
-- Restores handle_new_user() to its exact pre-migration state: the same
-- real, five-column insert body production already runs today, with the
-- SET search_path clause removed again. Deliberately NOT a revert to
-- 0000_baseline_pre_tracked_tables.sql's older two-column reconstruction
-- — that version has never been what production actually runs, and
-- rolling back to it would be a real behavioral regression (dropping
-- display_name/bio/avatar_url defaulting and the email-local-part
-- username fallback), not a safe undo. See 0040's own header for the
-- full discrepancy this migration found and closed.
--
-- Ownership, the on_auth_user_created trigger wiring, and grants are
-- untouched by this rollback, matching 0040 itself. No data is affected
-- either direction — a trigger function replace never rewrites rows
-- already inserted under a prior version of the function.

begin;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
as $$
begin
    insert into public.profiles (
        id,
        username,
        display_name,
        bio,
        avatar_url
    )
    values (
        new.id,
        coalesce(new.raw_user_meta_data->>'username', split_part(new.email, '@', 1)),
        coalesce(new.raw_user_meta_data->>'username', split_part(new.email, '@', 1)),
        '',
        ''
    );

    return new;
end;
$$;

commit;
