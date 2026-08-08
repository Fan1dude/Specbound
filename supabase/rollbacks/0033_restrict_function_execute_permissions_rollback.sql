-- Rollback for: 0033_restrict_function_execute_permissions
--
-- *** WARNING: running this restores the INSECURE pre-0033 access state
-- *** that the production audit confirmed and this migration was
-- *** written to fix — every function 0033 touches (including
-- *** create_notification(), which has no internal auth.uid() check of
-- *** its own) becomes callable again by `anon` and `authenticated`
-- *** exactly as before. Do not run this without a specific, reviewed
-- *** reason; it exists only for completeness, matching every other
-- *** migration/rollback pair in this chain — reverting 0033 is not
-- *** expected or recommended in normal operation.
--
-- This is NOT a uniformly "precise reversal" — the grants below come from
-- two different kinds of evidence, and the difference matters:
--
--   * Grants marked (migration-evidenced) below are backed by an actual
--     `grant execute ... to authenticated` statement still sitting in
--     migrations 0020-0032's own source (checked directly, function by
--     function, against 0020, 0021, 0022, 0026, 0027, 0028, 0029, 0030).
--   * Grants marked (audit-evidenced only) are NOT stated anywhere in
--     0020-0032's migration text — no migration ever explicitly granted
--     `anon`, and three functions (see group B below) never had an
--     explicit `authenticated` grant either. Their pre-0033 access came
--     entirely from Supabase's project-level default privileges applying
--     silently at function-creation time. The only record that this
--     access existed is the read-only production audit performed before
--     0033 was written (confirmed via `aclexplode()`/
--     `has_function_privilege()` against live production metadata), not
--     the migrations themselves. This rollback reproduces that
--     audit-confirmed access state by explicit grant; it does not, and
--     cannot, reproduce "silently via ambient default privileges" for
--     objects that already exist, since `alter default privileges` only
--     ever affects objects created after it runs.
--
-- Restores, in reverse order of 0033's own five statement groups:
--   1. Both default-privilege changes 0033 made, reversed in the
--      opposite scope order (schema-specific first, then global,
--      mirroring 0033's global-then-schema application order):
--      new postgres-owned functions in public go back to automatically
--      receiving EXECUTE for public/anon/authenticated on creation, the
--      same ambient state that let this finding happen in the first
--      place. See migration 0033's own header for why both a GLOBAL and
--      a SCHEMA-scoped statement are needed here — PostgreSQL's
--      hardcoded global PUBLIC-EXECUTE default for new functions is
--      only restored by a matching global grant, not a schema-scoped
--      one.
--   2a. Group A (12 functions) — authenticated: migration-evidenced;
--       anon: audit-evidenced only. Every one of these 12 has its own
--       `grant execute ... to authenticated` in the migration that
--       introduced it (is_catalog_moderator: 0020;
--       approve_component_submission/reject_component_submission: 0022;
--       is_platform_moderator/is_platform_staff: 0027;
--       report_content/resolve_report/grant_profile_role/
--       revoke_profile_role: 0028; submit_feedback: 0029;
--       redeem_beta_invite: 0030; sync_discord_identity: 0026). None of
--       those migrations ever grants anon — anon's pre-0033 access to
--       these 12 is audit-evidenced only.
--   2b. Group B (3 functions) — both anon AND authenticated:
--       audit-evidenced only. set_component_alias_technology_and_field()
--       (0021) and enforce_component_submission_pending_cap() (0022)
--       each only ever `revoke execute ... from public`, with no grant
--       statement to any role. create_notification() (0011, re-stated by
--       0031) only ever `revoke all ... from public`, also with no grant
--       to any role, ever — it was never intended to be client-callable
--       at all. All three functions' entire pre-0033 anon/authenticated
--       access is an artifact of Supabase's ambient default privileges,
--       confirmed only by the production audit, not by migration intent.
--   3. PUBLIC EXECUTE restored specifically on
--      sync_component_legacy_fields()/validate_featured_build() — the
--      two functions the audit found still had PUBLIC=true (neither had
--      ever been explicitly revoked from PUBLIC before 0033, and neither
--      the migrations nor this rollback grant them to anon/authenticated
--      by name — audit-evidenced only, same as above).
--   4. get_public_profile_roles(uuid) is deliberately left untouched —
--      it was anon+authenticated before 0033 (0032's own explicit grant
--      — migration-evidenced) and remains anon+authenticated after;
--      0033 re-stated that grant, it didn't change it, so there is
--      nothing to revert here.

begin;

alter default privileges for role postgres in schema public
    grant execute on functions to anon, authenticated;

alter default privileges for role postgres
    grant execute on functions to public;

-- Group A — authenticated: migration-evidenced; anon: audit-evidenced only.
grant execute on function
    public.is_catalog_moderator(uuid),
    public.approve_component_submission(uuid, uuid),
    public.reject_component_submission(uuid, text),
    public.is_platform_moderator(uuid),
    public.is_platform_staff(uuid),
    public.report_content(text, uuid, text),
    public.resolve_report(uuid, text, text),
    public.grant_profile_role(uuid, text, text),
    public.revoke_profile_role(uuid, text, text),
    public.submit_feedback(text, text, text),
    public.redeem_beta_invite(text),
    public.sync_discord_identity()
to anon, authenticated;

-- Group B — anon AND authenticated: audit-evidenced only (no migration
-- ever granted either role on these three).
grant execute on function
    public.set_component_alias_technology_and_field(),
    public.enforce_component_submission_pending_cap(),
    public.create_notification(uuid, uuid, text, uuid, uuid)
to anon, authenticated;

-- Group C — PUBLIC: audit-evidenced only (never explicitly revoked by
-- any migration, so this is the ambient state, not a migration grant).
grant execute on function
    public.sync_component_legacy_fields(),
    public.validate_featured_build()
to public;

commit;
