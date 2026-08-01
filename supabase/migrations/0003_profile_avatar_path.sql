-- Migration: 0003_profile_avatar_path
-- Milestone: 5A (Publishing) — avatar delivery follow-on
-- Status: PROPOSED — not yet applied.
--
-- Purpose: profiles.avatar_url currently stores a resolved, ready-to-use
-- URL (from Storage's getPublicUrl(), applied directly as an <img src>
-- with no re-resolution). Milestone 5A switches avatar delivery to signed
-- URLs (see js/services/imageService.js), which expire — storing one
-- verbatim in avatar_url would silently break every user's avatar
-- sitewide ~7 days after their last upload.
--
-- Purely additive, not a rename: avatar_path is a new nullable column.
-- New avatar uploads populate avatar_path (a bare storage-relative path,
-- e.g. "avatars/{userId}/500.jpg") only — avatar_url is left completely
-- untouched, still holding whatever ready-to-use URL it already had.
-- Application code prefers avatar_path (resolved to a signed URL at
-- render time) and falls back to rendering avatar_url as-is when
-- avatar_path is null, so existing avatars keep working immediately with
-- no backfill and no data transformation. avatar_url is only dropped in a
-- later, separate cleanup migration once every profile has re-uploaded (or
-- been otherwise backfilled) and nothing reads it anymore.
--
-- Touches: public.profiles only.
--
-- Rollback: see 0003_profile_avatar_path_rollback.sql in supabase/rollbacks/.

begin;

alter table public.profiles add column avatar_path text;

commit;
