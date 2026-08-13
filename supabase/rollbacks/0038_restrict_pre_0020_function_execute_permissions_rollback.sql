-- Rollback for: 0038_restrict_pre_0020_function_execute_permissions
--
-- *** WARNING: running this restores the pre-0038 access state — `anon`
-- *** regains EXECUTE on all ten functions listed below, none of which
-- *** were ever meant to be callable by an unauthenticated caller. Do not
-- *** run this without a specific, reviewed reason; it exists only for
-- *** completeness, matching every other migration/rollback pair in this
-- *** chain — reverting 0038 is not expected or recommended in normal
-- *** operation.
--
-- Every grant restored below is audit-evidenced only, the same
-- classification 0033's own rollback used for its equivalent group: no
-- migration ever explicitly granted `anon` on any of these ten functions
-- — their pre-0038 anon access came entirely from Supabase's ambient
-- default-privilege configuration applying at each function's original
-- creation time (0002 through 0012, all before 0033 closed that gap for
-- future functions). `authenticated` is unaffected by 0038 and therefore
-- by this rollback either way — it was correct before and remains
-- correct after, in both directions.

begin;

grant execute on function
    public.create_comment(uuid, text),
    public.delete_comment(uuid),
    public.set_build_like(uuid, boolean),
    public.set_build_saved(uuid, boolean),
    public.mark_notification_read(uuid),
    public.mark_all_notifications_read(),
    public.publish_draft(uuid, text, text),
    public.restore_revision_to_draft(uuid, timestamptz),
    public.set_build_visibility(uuid, text),
    public.set_follow(uuid, boolean)
to anon;

commit;
