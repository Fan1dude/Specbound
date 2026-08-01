# Migration Log

Migrations are written to `supabase/migrations/` for review before being run
manually in the Supabase SQL editor (no DB access exists from the
implementation environment). Status is tracked here since there's no CLI/CI
pipeline applying these automatically.

**Naming**: sequential, zero-padded, one number per applied-or-proposed
change — `0001_description.sql`, `0002_description.sql`, etc. Never reused,
never renumbered. A migration only gets edited in place if it's still
`Proposed` (not yet applied); once a migration is marked `Applied` below,
any further change to that schema is a new, higher-numbered file, even if
it's small. Each migration gets a matching rollback file in
`supabase/rollbacks/` (moved out of `supabase/migrations/` 2026-08-01 — a
real Supabase project's tooling was treating every `.sql` file in that
folder as a forward migration, applying rollbacks as forward changes).

**The one exception to "sequential starting at 0001"**: `0000` exists
specifically to sort *before* `0001` — added retroactively 2026-08-01 once
a from-empty-database dry run revealed `profiles`/`builds`/`build_revisions`
were never created by any tracked migration (see that file's own header).
Every other migration still only ever moves forward from `0001`.

## 0000_baseline_pre_tracked_tables

- **Status**: Proposed — not yet applied to the real project. Depends on
  nothing (this is the new floor of the migration sequence).
- **File**: `migrations/0000_baseline_pre_tracked_tables.sql`
- **Rollback**: `rollbacks/0000_baseline_pre_tracked_tables_rollback.sql`
- **Adds**: `public.profiles`, `public.builds`, `public.build_revisions`,
  and the `auth.users` signup trigger that populates `profiles` — none of
  which any tracked migration ever created, despite `0001` onward freely
  `ALTER`ing and foreign-keying against all three. Every column is
  reconstructed from evidence (later `ALTER TABLE` statements, migration
  function bodies, application code) — see the file's own header for the
  full method and for what's deliberately *not* included (no `UNIQUE` on
  `builds.slug` — that gap is `0015`'s to fix, faithfully; no `CHECK` on
  `builds.status`/`build_revisions.update_type` — neither ever had one).
- **Touches no existing table** (there is no earlier tracked state to
  touch).
- **Known limitation**: this is a reconstruction sufficient to bootstrap a
  fresh project, not a captured-and-verified-identical copy of the real
  production database's actual definitions. See `docs/DATABASE.md`'s
  Known Gap section and the `docs/ROADMAP.md` backlog item for what
  closing that remaining gap would require.
- **Context**: found and fixed 2026-08-01, the first time a genuine
  from-empty-database dry run of the full migration sequence was
  attempted, for `docs/milestones/MILESTONE_19_DEV_APPLICATION_PROCEDURE.md`.

## 0001_project_drafts_and_media

- **Status**: Applied.
- **File**: `migrations/0001_project_drafts_and_media.sql`
- **Rollback**: `rollbacks/0001_project_drafts_and_media_rollback.sql`
- **Adds**: `project_drafts`, `project_media` (both new, owner-only RLS), a
  `cover_media_id` FK on `project_drafts`, storage policies for the
  `projects/{draftId}/...` path prefix in the existing `project-images`
  bucket, and a reusable `public.set_updated_at()` trigger function
  (attached to `project_drafts` now; any future table with an `updated_at`
  column can reuse it rather than each one inventing its own).
- **Touches no existing table.**
- Application code (`js/repositories/draftRepository.js`) no longer sets
  `updated_at` manually — the database owns it via trigger.
- **Context**: Milestone 4 (Project Editor), Option A draft architecture —
  see project chat history for the design discussion.

## 0002_publish_draft_and_visibility

- **Status**: Applied. Its DDL (columns, `revision_media`, RLS policies,
  the `publish_draft()` function itself) succeeded — but `publish_draft()`
  had a runtime bug (referenced `builds.version`/`builds.progress`, which
  don't exist on the real table; `CREATE FUNCTION` doesn't validate
  column references inside the body, so this only surfaced when actually
  called). Fixed by `0004_fix_publish_draft_builds_columns`, which
  replaces the function only — no schema objects from this migration were
  wrong, only the function logic. Left as-applied/unedited here per this
  file's own convention (accurate history, bug included) rather than
  patched in place.
- **File**: `migrations/0002_publish_draft_and_visibility.sql`
- **Rollback**: `rollbacks/0002_publish_draft_and_visibility_rollback.sql`
- **Adds**: `project_drafts.published_build_id`, `builds.visibility`
  (`public`/`private`, defaults + backfills every existing row to
  `public`), `revision_media` (immutable gallery snapshot per revision,
  `is_cover boolean` rather than a FK from `build_revisions`, at most one
  cover per revision via a partial unique index), and
  `public.publish_draft(p_draft_id, p_version_label, p_publish_notes)` — a
  `SECURITY DEFINER` function that is the only path allowed to write
  `builds`, `build_revisions`, or `revision_media` going forward.
- **Touches**: `project_drafts` (new column), `builds` (new column + full
  RLS replacement — read-only for direct clients now), `build_revisions`
  (full RLS replacement — read-only for direct clients now),
  `storage.objects` (replaces the `projects/...` owner-delete policy from
  0001 with one that also blocks deleting a file a published revision
  still references; adds public-read policies for `avatars/*` and for any
  path referenced by `revision_media`, needed for `createSignedUrl()` to
  work for anonymous visitors).
- **Deliberately not included**: flipping the `project-images` bucket to
  private. Existing `profiles.avatar_url` / `builds.image_url` /
  `build_revisions.image_url` values are live public URLs from prior
  milestones — flipping the bucket now would break all of them
  immediately. That's a separate, later migration once every read path is
  confirmed working against signed URLs.
- **Caution on rollback**: 0002's RLS section drops *every* existing
  policy on `builds`/`build_revisions` before adding fresh ones, because
  their exact prior names weren't knowable from this environment (no DB
  introspection access). The rollback file cannot restore those original
  policies — see the warning at the top of the rollback SQL.
- **Context**: Milestone 5A (Publishing). Architecture approved with two
  adjustments from the original proposal: private-storage/signed-URL
  delivery instead of a public bucket, and `is_cover` boolean on
  `revision_media` instead of `build_revisions.cover_media_id`. See
  project chat history for the full design discussion.

## 0003_profile_avatar_path

- **Status**: Applied.
- **File**: `migrations/0003_profile_avatar_path.sql`
- **Rollback**: `rollbacks/0003_profile_avatar_path_rollback.sql`
- **Adds**: `profiles.avatar_path`, a new nullable column — purely
  additive, not a rename. `avatar_url` is left in place untouched, holding
  whatever ready-to-use URL it already had. Needed because avatar delivery
  moved to signed URLs (they expire — storing one directly in the column
  the way the old public URL was stored would silently break every user's
  avatar ~7 days after their last upload). New uploads populate
  `avatar_path` only; rendering prefers `avatar_path` (resolved to a
  signed URL at render time) and falls back to `avatar_url` as-is when
  `avatar_path` is null, so this carries no deployment-order dependency
  between schema and frontend and requires no backfill.
- **Touches**: `public.profiles` only.
- **Deferred**: dropping `avatar_url` — a later, separate cleanup
  migration once every profile has re-uploaded (or been otherwise
  backfilled) and nothing reads it anymore.
- **Context**: Milestone 5A follow-on, prompted by resolving how avatars
  should be delivered once `project-images` is private. Revised from an
  initial rename-based proposal to this additive approach per review. See
  project chat history.

## 0004_fix_publish_draft_builds_columns

- **Status**: Applied. Confirmed by real-backend test: publish and
  republish both succeeded, project reached v1.1 as expected.
- **File**: `migrations/0004_fix_publish_draft_builds_columns.sql`
- **Rollback**: `rollbacks/0004_fix_publish_draft_builds_columns_rollback.sql`
- **Fixes**: `publish_draft()`'s real-backend test failed with `column
  "version" of relation "builds" does not exist`. Confirmed against the
  actual schema via `information_schema.columns`: `builds` has no
  `version` or `progress` column at all (only `build_revisions` does).
  This migration is a `CREATE OR REPLACE FUNCTION` only — no table/column
  changes. Fixes: `builds` insert/update no longer reference
  version/progress; republish's version auto-increment now reads the most
  recent existing `build_revisions.version` for the build instead of
  `builds.version`; `build_revisions.progress` is always inserted as `0`
  (no source for "current progress" exists now that `builds` doesn't
  carry it, and progress-tracking is out of scope for this doc-first
  publish flow); `update_type` now uses `'documentation'` (an existing
  value from this app's own UI vocabulary) instead of the unverified
  invented strings `'initial_publish'`/`'update'`; `attachments` now
  defaults its literal to `'[]'::jsonb`, matching the column's own
  declared default shape.
- **Touches**: `public.publish_draft()` only.
- **Open risk**: `status: 'planning'` and `update_type: 'documentation'`
  are values used elsewhere in this app's UI, but their validity against
  any actual CHECK constraint on `builds.status` /
  `build_revisions.update_type` hasn't been confirmed — only column
  existence/type was checked, not constraints. Worth a quick
  `information_schema.check_constraints` look if a similar error recurs
  on either field.
- **Context**: Milestone 5A, correcting a real-backend test failure. See
  project chat history.

## 0005_revision_history_and_restore

- **Status**: Applied. Confirmed by real-backend test: revision URLs,
  timeline navigation, multi-revision publishing (v1.0 → v1.1 → v1.2),
  and historical revision routing all verified working.
- **File**: `migrations/0005_revision_history_and_restore.sql`
- **Rollback**: `rollbacks/0005_revision_history_and_restore_rollback.sql`
- **Preflight**: checks for builds with more than one draft linked via
  `published_build_id` before creating the unique index below, and raises
  a clear exception (naming the count) rather than letting the index
  creation fail opaquely — or worse, silently resolving duplicates itself.
  Does not delete/merge/choose between drafts. See the migration's header
  comment for the diagnostic query to run if this fails.
- **Adds**: `build_revisions.snapshot_title` / `snapshot_description` /
  `category` / `specifications` / `resources` — an actual immutable
  content snapshot per revision, which didn't exist before (only
  `builds.specifications` did, and it's overwritten on every republish).
  Named `snapshot_*` rather than reusing `title`/`description`, which
  already mean something different (the Project Log changelog entry's own
  headline/note). A unique partial index on
  `project_drafts.published_build_id` (at most one draft per published
  build — required for restore to know unambiguously which draft to
  seed). `public.restore_revision_to_draft(p_revision_id,
  p_expected_draft_updated_at)` — `SECURITY DEFINER`, verifies
  `auth.uid()` owns the build behind the revision, locks the linked draft
  with `for update`, and rejects the restore (optimistic concurrency) if
  the caller's expected `updated_at` doesn't match the draft's actual
  current `updated_at` — so restoring can't silently clobber newer
  unsaved/autosaved draft work. Replaces the draft's gallery with fresh
  `project_media` rows copied from the revision's `revision_media`
  (new ids, same storage paths) without ever writing to `revision_media`
  or `build_revisions` itself.
- **Replaces**: `publish_draft()` (`CREATE OR REPLACE`, not a new
  function) — now also writes the new snapshot columns on every publish.
  Revisions published before this migration have those fields empty;
  there's nothing to backfill from, since the data was never captured.
- **Known limitation, accepted for this milestone**: restoring deletes
  the draft's old `project_media` rows but can't delete their underlying
  Storage objects (SQL can't call the Storage API) — files not referenced
  by any `revision_media` snapshot become orphaned in Storage.
- **Touches**: `build_revisions` (5 new columns), `project_drafts` (new
  unique index), `publish_draft()` (replaced). Adds
  `restore_revision_to_draft()`.
- **Context**: Milestone 5C (Revision History & Restore). See project
  chat history for the full design discussion and the two required
  safeguards (preflight duplicate check; restore confirmation UI +
  optimistic concurrency) that shaped this migration.

## 0006_unpublish

- **Status**: Applied.
- **File**: `migrations/0006_unpublish.sql`
- **Rollback**: `rollbacks/0006_unpublish_rollback.sql`
- **Adds**: `public.set_build_visibility(p_build_id, p_visibility)` —
  `SECURITY DEFINER`, the only direct way to change `builds.visibility`
  (same "no direct-client writes to builds" posture as everything else on
  this table). Ownership-checked, validates the value, a single `UPDATE`.
  Deliberately creates no revision and does not touch
  `build_revisions`/`revision_media`/`project_drafts`. Does not bump
  `builds.updated_at` — that column tracks content changes and both
  `getNewestBuilds()`/`getMyBuilds()` sort by it; bumping it on a
  visibility flip would move an untouched project to the top of "Latest
  Builds" for no content reason.
- **Replaces**: `publish_draft()` (`CREATE OR REPLACE`) — republishing an
  unpublished build now restores `visibility = 'public'` as part of the
  same update that refreshes its content. Deliberate behavioral choice:
  publishing is the action that makes a project live, so there is no
  separate "republish visibility" step after publishing content. First
  publish is unaffected (`builds.visibility` already defaults to
  `'public'` on insert).
- **Also this milestone (not part of this migration — pure JS, no
  schema)**: `getNewestBuilds()` / `getFeaturedBuilds()` (buildRepository)
  and `getProfileBuilds()` (profileRepository) now filter to
  `visibility = 'public'`, on top of the RLS policies from 0002 that
  already enforce it — covers Home, Explore (including its in-page
  search), and the public Profile page. `getBuildBySlug()` deliberately
  left unfiltered: RLS alone already returns "no row" to a non-owner for
  a private build, identical to a nonexistent slug (no distinct
  "unpublished" page — that would leak to a non-owner that a slug used to
  exist), while still letting the owner preview their own unpublished
  build via its direct link.
- **Touches**: `publish_draft()` (replaced). Adds
  `set_build_visibility()`.
- **Context**: Milestone 5D (Unpublish). See project chat history for the
  full design discussion, including the explicit decision that
  Publish/"Publish Again" — not a separate republish-visibility action —
  is what brings an unpublished project back to public.

## 0007_comments

- **Status**: Proposed — not yet applied. Depends on 0001-0006 being
  applied first.
- **File**: `migrations/0007_comments.sql`
- **Rollback**: `rollbacks/0007_comments_rollback.sql`
- **Adds**: `comments` (`build_id`, not `revision_id` — comments belong
  to the build as a whole), `deleted_at` (soft delete; nothing hard-
  deletes a comment through the app), `parent_comment_id` (added now for
  a future replies feature that is completely out of scope this
  milestone — no UI, no query, no code references it), a `CHECK`
  constraint bounding body length (1–2000 chars, trimmed).
  `public.create_comment(p_build_id, p_body)` and
  `public.delete_comment(p_comment_id)` — both `SECURITY DEFINER`, the
  only way to write to this table. `create_comment` reads `auth.uid()`
  directly rather than accepting it as a parameter (can't be spoofed),
  re-validates the build is actually visible to the caller, and
  friendly-validates body length before the `CHECK` constraint would.
  `delete_comment` authorizes the comment's own author OR the build's
  owner, and sets `deleted_at` rather than deleting the row.
- **RLS**: SELECT only (`deleted_at is null and` the same
  public-or-owner visibility check already used for
  `build_revisions`/`revision_media`) — no insert/update/delete
  policies, matching this schema's existing "no direct writes" posture.
  Initial proposal suggested RLS alone was sufficient for insert/delete
  too (simple single-row, boolean-authorization writes); revised to
  route both through functions instead, for consistency with every
  other write path in this schema.
- **Touches**: none — new table only.
- **Context**: Milestone 6A (Project Comments). See project chat history
  for the full design discussion.

## 0008_project_likes

- **Status**: Proposed — not yet applied. Depends on 0001-0007 being
  applied first.
- **File**: `migrations/0008_project_likes.sql`
- **Rollback**: `rollbacks/0008_project_likes_rollback.sql`
- **Adds**: `likes` (`build_id`, `user_id`, `unique (build_id, user_id)` —
  the hard duplicate-prevention guarantee, independent of any application
  logic). `public.set_build_like(p_build_id, p_liked)` — `SECURITY
  DEFINER`, an idempotent desired-state RPC (not a toggle):
  `p_liked = true` ensures a like row exists, `p_liked = false` ensures it
  doesn't; a retried request with the same `p_liked` can never reverse
  what an earlier call already did. Reads `auth.uid()` directly, never as
  a parameter. Requires `builds.visibility = 'public'` exactly — NOT the
  "public or owner" rule used elsewhere in this schema — so an owner
  previewing their own unpublished project cannot like/unlike it either
  way; existing like rows on a project that later goes private are left
  untouched, only new writes are blocked. Returns the authoritative
  `(liked, likes_count)` after the write. `public.bump_likes_count()` — a
  trigger function (`security definer`, revoked from `PUBLIC`, never
  called directly) that keeps `builds.likes_count` — a pre-existing
  column, previously unpopulated by anything — in sync on every
  insert/delete, using `coalesce(likes_count, 0)` and `greatest(0, ...)`
  to guard null/negative drift.
- **RLS**: SELECT only, scoped to the caller's own row
  (`user_id = auth.uid()`) — narrower than comments' visibility-based
  read policy, since nothing here needs to expose who liked a project.
  The public like count is read off `builds.likes_count` instead, not
  this table. No insert/update/delete policies — writes only through
  `set_build_like()`.
- **Touches**: none — `builds.likes_count` already existed as a column
  (unpopulated); this migration starts maintaining it but adds no new
  column to `builds`. Adds `likes`, `bump_likes_count()`,
  `set_build_like()`.
- **Context**: Milestone 6D (Project Likes). Architecture approved with
  two required changes from the original proposal: strict
  `visibility = 'public'` check (not public-or-owner) on every like
  state change, and an idempotent desired-state RPC
  (`set_build_like(p_build_id, p_liked)`) instead of a toggle. See
  project chat history for the full design discussion.

## 0009_saved_builds

- **Status**: Proposed — not yet applied. Depends on 0001-0008 being
  applied first.
- **File**: `migrations/0009_saved_builds.sql`
- **Rollback**: `rollbacks/0009_saved_builds_rollback.sql`
- **Adds**: `saved_builds` (`build_id`, `user_id`,
  `unique (build_id, user_id)`). `public.set_build_saved(p_build_id,
  p_saved)` — `SECURITY DEFINER`, same idempotent desired-state shape as
  `set_build_like()` in 0008. Deliberately ASYMMETRIC visibility rule,
  per explicit direction: `p_saved = true` requires
  `builds.visibility = 'public'`; `p_saved = false` has no visibility
  check at all — a save is a private bookmark, not an engagement signal,
  so removing one from your own list is always allowed even after the
  project goes private. No trigger/cached counter — no public "N saves"
  count exists in this milestone's scope.
- **RLS**: SELECT only, scoped to the caller's own row
  (`user_id = auth.uid()`) — this is what makes saves private to the
  owner; nobody, including the project's own creator, can see who saved
  it. No insert/update/delete policies — writes only through
  `set_build_saved()`.
- **Touches**: none — new table only.
- **Context**: Milestone 6E (Saved Projects). Architecture approved with
  two decisions: the asymmetric save/unsave visibility rule above, and an
  unsave control added directly to Workshop's Saved Projects section (via
  a wrapper around the unmodified `BlueprintCard`, not a change to the
  card itself). See project chat history for the full design discussion.

## 0010_build_view_tracking

- **Status**: Proposed — not yet applied. Depends on 0001-0009 being
  applied first.
- **File**: `migrations/0010_build_view_tracking.sql`
- **Rollback**: `rollbacks/0010_build_view_tracking_rollback.sql`
- **Adds**: `build_view_cooldowns` — a bounded UPSERT table (one row per
  `(build_id, viewer_key)`, not an append-only events log), RLS enabled
  with **zero policies** (no legitimate direct-client read/write case
  exists; it's `record_build_view()`'s own internal bookkeeping only).
  `public.record_build_view(p_build_id, p_anon_id)` — `SECURITY DEFINER`,
  the first write RPC in this schema granted to `anon` as well as
  `authenticated` (view tracking must work signed-out). Enforces a
  30-minute per-viewer cooldown, skips the owner's own views, and only
  counts views on `visibility = 'public'` builds — all as silent no-ops
  (not exceptions), always returning the current authoritative
  `builds.views`. No trigger — views are increment-only, so the counter
  is updated inline in the same transaction as the cooldown upsert.
- **Touches**: none — `builds.views` already existed as a column
  (unpopulated); this migration starts maintaining it but adds no new
  column to `builds`. Adds `build_view_cooldowns`, `record_build_view()`.
- **Context**: Milestone 7A (Project View Tracking). Architecture
  approved as proposed, plus two additions: "Total Views" added to
  Builder Profile stats (computed client-side from already-fetched
  builds, no new query), and the build page's visible view count is
  updated in place from the RPC's returned authoritative value
  immediately after page load, rather than waiting for a refresh. See
  project chat history for the full design discussion.

## 0011_notifications

- **Status**: Proposed — not yet applied. Depends on 0001-0010 being
  applied first.
- **File**: `migrations/0011_notifications.sql`
- **Rollback**: `rollbacks/0011_notifications_rollback.sql`
- **Adds**: `notifications` (`recipient_id`, `actor_id`, `type` — CHECK
  includes `'reply'` for future schema compatibility, though nothing
  creates one yet since threaded replies aren't implemented — `build_id`,
  nullable `comment_id`, nullable `read_at`). RLS SELECT only, scoped to
  `recipient_id = auth.uid()` (private to the recipient — not even the
  actor can see it). `public.create_notification(...)` — `SECURITY
  DEFINER`, granted to **no client role at all**, only callable from
  other already-privileged `SECURITY DEFINER` functions; skips
  self-notification only, does NOT collapse/suppress duplicate
  notifications for the same (recipient, actor, build, type) per explicit
  direction — every real event gets its own notification, relying on the
  calling RPCs' own idempotency to prevent a *retry* from double-firing.
  `public.mark_notification_read(p_notification_id)` /
  `public.mark_all_notifications_read()` — `SECURITY DEFINER`,
  ownership-checked, granted to `authenticated`; nothing else in this
  schema ever sets `read_at` — no auto-mark-read on view, per explicit
  direction.
- **Replaces** (`CREATE OR REPLACE`, no signature changes):
  `create_comment()` now notifies the build's owner on every comment;
  `set_build_like()`/`set_build_saved()` now notify the build's owner
  only on a branch where a row was genuinely newly inserted (detected via
  `on conflict do nothing returning id`), never on unlike/unsave, never
  on a no-op re-like/re-save.
- **Touches**: `create_comment(uuid, text)`, `set_build_like(uuid,
  boolean)`, `set_build_saved(uuid, boolean)` (all replaced). Adds
  `notifications`, `create_notification()`, `mark_notification_read()`,
  `mark_all_notifications_read()`.
- **Context**: Milestone 7B (Notifications). Architecture approved with
  three decisions: keep `'reply'` in the schema without generating it yet,
  never auto-mark notifications read, and remove the unread-duplicate
  suppression guard from the original proposal (every real event
  notifies). See project chat history for the full design discussion.

## 0012_follows

- **Status**: Proposed — not yet applied. Depends on 0001-0011 being
  applied first.
- **File**: `migrations/0012_follows.sql`
- **Rollback**: `rollbacks/0012_follows_rollback.sql`
- **Adds**: `follows` (`follower_id`, `following_id`,
  `unique (follower_id, following_id)`, `check (follower_id <>
  following_id)` — duplicate- and self-follow prevention enforced at the
  database level). RLS SELECT is **fully public** (`using (true)`) — the
  first table in this schema since 0007 that isn't private-to-self;
  Private Accounts is out of scope and Followers/Following pages need to
  be visible to any visitor. No insert/update/delete policies — writes
  only through `set_follow()`. `profiles.followers_count`/
  `following_count` — new, trigger-maintained cached columns (both
  default 0, already correct with no backfill needed), kept in sync by
  `bump_follow_counts()` (revoked from `PUBLIC`, same posture as
  `bump_likes_count()`). `public.set_follow(p_following_id, p_followed)`
  — `SECURITY DEFINER`, idempotent desired-state RPC matching
  `set_build_like()`'s shape, granted to `authenticated` only. No
  `create_notification()` call — Follow notifications are out of scope.
- **Touches**: `public.profiles` (2 new columns, additive only). Adds
  `follows`, `bump_follow_counts()`, `set_follow()`.
- **Context**: Milestone 7C (Following Builders). Architecture approved
  as proposed, plus the profile hero layout: Username / Bio / Followers •
  Following (clickable, opening dedicated pages), THEN the existing
  stats grid below — not merged into it. See project chat history for the
  full design discussion.

## 0013_activity_feed

- **Status**: Proposed — not yet applied. Depends on 0001-0012 being
  applied first.
- **File**: `migrations/0013_activity_feed.sql`
- **Rollback**: `rollbacks/0013_activity_feed_rollback.sql`
- **Adds**: `public.get_activity_feed(p_scope, p_before_created_at,
  p_before_id, p_limit)` only — no table, no columns. Computes the
  Following/Explore feeds live from the existing `build_revisions` log
  (already immutable, timestamped, and RLS-correct — nothing to
  duplicate). Ships only `'new_project'`/`'new_revision'` activity
  types; a `'completed'` type was explicitly excluded — nothing in this
  app ever sets `builds.status` beyond `'planning'`, so there is no
  reliable historical completion event to source it from (status
  management is a separate future feature). `activity_type` is derived
  per row via a deterministic `(created_at, id)` ordering, not
  `min(created_at)` alone (two revisions for the same build could share
  an identical same-transaction timestamp). Pagination is a composite
  keyset cursor (`p_before_created_at` + `p_before_id`, ordered
  `created_at desc, id desc`) so same-timestamp rows can't be skipped or
  duplicated. `p_scope` is validated to exactly `'following'`/`'explore'`;
  `p_limit` is clamped to `[1, 50]`, default `20`.
- **`SECURITY INVOKER`, not `DEFINER`** — the first RPC in this schema
  that needs no elevated privilege at all: every table it reads
  (`build_revisions`, `builds`, `follows`) is already correctly readable
  to the calling user under their own existing RLS. Granted to `anon`
  and `authenticated` — the Explore feed must work signed out; the
  Following feed naturally returns empty for a signed-out caller with no
  special-casing needed.
- **Touches**: none — new function only.
- **Context**: Milestone 7D (Activity Feed). Architecture approved with
  four required changes from the original proposal: drop the
  `'completed'` activity type entirely (not even schema-ready), the
  composite `(created_at, id)` keyset cursor, deterministic
  `(created_at, id)`-based activity classification instead of
  `min(created_at)`, and explicit `p_scope` validation +
  `p_limit` clamping. See project chat history for the full design
  discussion.

## 0014_storage_visibility_fix

- **Status**: Proposed — not yet applied. Depends on 0001-0013 being
  applied first.
- **File**: `migrations/0014_storage_visibility_fix.sql`
- **Rollback**: `rollbacks/0014_storage_visibility_fix_rollback.sql`
- **Fixes**: a real privacy gap found in the Milestone 8 audit —
  `0002`'s original `"Anyone can read files referenced by a published
  revision"` storage policy never checked the parent build's
  `visibility`, so unpublishing a project didn't actually revoke
  Storage-level access to its images, only the database rows. Replaced
  with two separately-named policies per Milestone 8A review: `"Public
  can read revision media for public builds"` (`visibility = 'public'`
  only) and `"Owners can read their revision media"`
  (`user_id = auth.uid()` only) — both joining
  `revision_media -> build_revisions -> builds` to match
  `storage.objects.name`.
- **Known, disclosed limitation**: cannot retroactively invalidate a
  signed URL already issued before this fix — Supabase signed URLs embed
  a bypass at generation time, not at every fetch. Only stops *new*
  signed URLs from being generated for now-private content; existing
  ones simply expire on their own (≤7 days). Same category of accepted
  limitation as `0005`'s orphaned-Storage-files gap.
- **Touches**: `storage.objects` (one policy replaced by two). No table,
  column, or function changes.
- **Context**: Milestone 8A (Security & Data Integrity). See project
  chat history for the full design discussion.

## 0015_index_hardening

- **Status**: Proposed — not yet applied. Depends on 0001-0014 being
  applied first.
- **File**: `migrations/0015_index_hardening.sql`
- **Rollback**: `rollbacks/0015_index_hardening_rollback.sql`
- **Adds**: a unique index on `builds.slug` (with a preflight duplicate
  check, same pattern as `0005`'s duplicate-draft check — fails clearly
  rather than opaquely, never auto-resolves duplicates) — `builds.slug`
  had no index or uniqueness guarantee anywhere despite being the
  primary lookup key for every project-page view, and was only
  app-level, check-then-insert, and racy. Also adds
  `build_revisions (build_id, created_at, id)` and
  `build_revisions (created_at desc, id desc)` — `build_revisions` had
  zero indexes at all, despite being read by `getBuildRevisions()`,
  `publish_draft()`'s version-bump lookup, and — most severely —
  `get_activity_feed()`'s (`0013`) global keyset pagination and per-row
  correlated subquery.
- **Touches**: `builds` (new unique index), `build_revisions` (two new
  indexes). No column or function changes.
- **Context**: Milestone 8A (Security & Data Integrity). See project
  chat history for the full design discussion.

## 0016_security_definer_hygiene

- **Status**: Proposed — not yet applied. Depends on 0001-0015 being
  applied first.
- **File**: `migrations/0016_security_definer_hygiene.sql`
- **Rollback**: `rollbacks/0016_security_definer_hygiene_rollback.sql`
- **Fixes**: the one gap found by a full re-audit of every custom
  function's `SECURITY DEFINER`/`INVOKER` configuration —
  `set_updated_at()` (`0001`) was the only trigger function in the schema
  without a defensive `revoke all ... from public`, unlike its siblings
  `bump_likes_count()`/`bump_follow_counts()`. Not currently exploitable
  (a `returns trigger` function can't be invoked outside trigger
  context), but a real, fixable inconsistency. A bare `revoke`, not a
  `CREATE OR REPLACE` — `0001` itself is untouched, per this project's
  convention against editing applied migrations.
- **Touches**: none — revokes a privilege on `set_updated_at()` only.
- **Context**: Milestone 8A (Security & Data Integrity). Architecture
  approved with one required change from the original proposal: split
  `0014`'s combined public-or-owner storage policy into two separately-
  named policies. See project chat history for the full design
  discussion.

## 0017_storage_rls_hardening

- **Status**: Proposed — not yet applied. Depends on 0001-0016 being
  applied first.
- **File**: `migrations/0017_storage_rls_hardening.sql`
- **Rollback**: `rollbacks/0017_storage_rls_hardening_rollback.sql`
- **Fixes**: four `storage.objects` policies confirmed live via a direct
  `pg_policies` dump and empirical anonymous-session testing, none of
  which appear in any tracked migration — `"Anyone can view project
  images"` (unscoped SELECT), `"Authenticated users can upload project
  images"` (unscoped INSERT), `"Enable insert for authenticated users
  only"` (INSERT actually scoped to the **anon** role, `with_check =
  true` — anonymous uploads to arbitrary paths), and `"Enable read access
  for all users"` (SELECT, `qual = true`, not even bucket-scoped).
  Confirmed these let an anonymous session list the entire bucket root,
  list into other users' draft folders, and sign+fetch arbitrary files —
  independent of the bucket's public/private flag, since `list()` and
  `createSignedUrl()` both evaluate RLS regardless of it. Adds two new
  policies (`"Owners can upload/update their own avatar files"`, scoped
  to `avatars/{auth.uid()}/*`) to close the one legitimate gap the broad
  policies had been accidentally covering — avatar upload had no scoped
  policy in any tracked migration.
- **Touches**: `storage.objects` (four policies dropped, two added). No
  table, column, or function changes.
- **Deliberately excludes**: flipping the `project-images` bucket's
  public/private flag (a separate action after this migration is applied
  and live-verified) and any legacy-URL/`revision_media` backfill work
  (a separate follow-up migration). See
  `docs/milestones/MILESTONE_9_STORAGE_RLS_MIGRATION.md` for the full design and
  `docs/STORAGE_ARCHITECTURE.md` for the resulting model.
- **Context**: Milestone 9 (Production Cleanup & Launch). Split from a
  combined proposal into two tracked migrations per explicit review
  feedback — this one (Migration A, storage security repair) and a
  separate Migration B (client-side legacy URL compatibility, not yet
  started).

## 0018_legacy_media_linkage_backfill

- **Status**: Proposed — not yet applied. Depends on 0001-0017 being
  applied first.
- **File**: `migrations/0018_legacy_media_linkage_backfill.sql`
- **Rollback**: `rollbacks/0018_legacy_media_linkage_backfill_rollback.sql`
- **Adds**: 7 `revision_media` rows (`desk`'s 5 revisions, `trap-open`'s
  2) for legacy pre-Milestone-5A storage objects whose ownership *and*
  revision linkage are both independently provable from the objects'
  owning `build_revisions.image_url` values — no filename matching, no
  inference. Guarded by a `NOT EXISTS` check (idempotent re-run). A
  further 3 legacy objects ("Category B" — build-level-only covers with
  no corroborating revision) are deliberately NOT backfilled here, since
  only their ownership (not revision linkage) is provable; see
  `docs/milestones/MILESTONE_9_MIGRATION_C_LEGACY_BACKFILL.md` for the full
  categorization and the 3 options considered for handling them later.
- **Touches**: `revision_media` only (7 new rows). Never touches
  `image_url` on `builds`/`build_revisions`, `storage.objects`, any
  storage RLS policy, or the bucket's public/private flag.
- **Context**: Milestone 9 (Production Cleanup & Launch) — Migration C,
  approved with one adjustment (Category B explicitly excluded from this
  migration, reported instead of synthesized/force-linked). Follows
  Migration A (`0017`, storage RLS hardening) and Migration B (client-side
  legacy URL compatibility layer, no migration file — read-path only).

## 0019_fix_record_build_view_ambiguity

- **Status**: Proposed — not yet applied. Depends on 0001-0018 being
  applied first.
- **File**: `migrations/0019_fix_record_build_view_ambiguity.sql`
- **Rollback**: `rollbacks/0019_fix_record_build_view_ambiguity_rollback.sql`
- **Fixes**: two confirmed issues in `record_build_view()` (0010), both
  reproduced live against the real backend during the 2026-07-28
  implementation review. (1) Every call failed with Postgres 42702
  ("column reference \"views\" is ambiguous") — `returns table(views
  integer)` implicitly declares a PL/pgSQL variable named `views` that
  collided with the `builds.views` column read inside the increment
  UPDATE; view counts have almost certainly never incremented since this
  feature shipped, failing silently (caught and only `console.error`'d
  client-side). (2) The function's final `return query` ran
  unconditionally regardless of the visibility check above it, letting
  any caller learn a private build's view count by calling the RPC
  directly with its id, bypassing what RLS would otherwise prevent via a
  direct SELECT.
- **Behavior after this migration**: public builds — eligible visits may
  increment, caller always receives the count. Private build, owner
  asking — never increments, owner receives the count. Private build,
  anyone else asking — never increments, count is not revealed (returns
  `NULL`, not `0`, so it's distinguishable from a genuine zero-view
  build). Nonexistent build — unchanged, still raises `'Project not
  found.'`.
- **Touches**: `public.record_build_view()` only. RPC name, parameters,
  return shape (`table(views integer)`), and grants (`anon`,
  `authenticated`) are all unchanged from 0010. No table, column, index,
  policy, or grant added, dropped, or altered — RLS untouched.
- **Context**: Milestone 11B (Confirmed Database Bug), found during the
  2026-07-28 implementation review. Does not edit 0010 in place, per
  this project's migration convention.

## 0020_components_catalog

- **Status**: Proposed — not yet applied. Depends on 0001-0019.
- **File**: `migrations/0020_components_catalog.sql`
- **Rollback**: `rollbacks/0020_components_catalog_rollback.sql`
- **Adds**: `catalog_moderators` (the app's first admin-role concept,
  scoped to this one subsystem) and `is_catalog_moderator(uid)` (a
  `SECURITY DEFINER` helper other tables' RLS policies reference), then
  `components` — the canonical parts catalog, with a generated
  `normalized_name` column (punctuation/spacing-insensitive) backing the
  uniqueness constraint. Only a `catalog_moderators`-flagged user may
  insert directly; ordinary users contribute via `component_submissions`
  (0022) instead.
- **Touches no existing table.**
- **Context**: Milestone 19 (Structured Parts Catalog). See
  `docs/milestones/MILESTONE_19_PARTS_CATALOG_ARCHITECTURE.md` for the
  full design and `docs/milestones/MILESTONE_19_SQL_SECURITY_AUDIT.md`
  for a follow-up audit pass (non-empty checks, explicit execute grants)
  applied to this file before it was considered ready.

## 0021_component_aliases

- **Status**: Proposed — not yet applied. Depends on 0020.
- **File**: `migrations/0021_component_aliases.sql`
- **Rollback**: `rollbacks/0021_component_aliases_rollback.sql`
- **Adds**: `component_aliases` — shorthand/misspelling mappings onto an
  existing `components` row (e.g. "4080" → "NVIDIA GeForce RTX 4080"),
  moderator-curated, no client-facing write path. `technology_id`/
  `field_key` are denormalized onto this table by a trigger, purely so a
  unique index can enforce "one alias string resolves to exactly one
  component per technology/field slot."
- **Touches no existing table.**
- **Context**: Milestone 19. Ships ahead of `0022` even though aliases
  are conceptually a moderation *output* — `0022`'s approval RPC needs
  this table to already exist. See
  `docs/milestones/MILESTONE_19_SQL_SECURITY_AUDIT.md` for the audit
  pass applied (non-empty checks, defensive execute revoke on the
  trigger function).

## 0022_component_submissions

- **Status**: Proposed — not yet applied. Depends on 0020, 0021.
- **File**: `migrations/0022_component_submissions.sql`
- **Rollback**: `rollbacks/0022_component_submissions_rollback.sql`
- **Adds**: `component_submissions` — the only path an ordinary user has
  toward ever creating a canonical catalog entry, since `0020` locks
  direct inserts to moderators. `approve_component_submission(id,
  alias_of_component_id)` and `reject_component_submission(id, note)`,
  both `SECURITY DEFINER`, both internally checking
  `is_catalog_moderator(auth.uid())`, are the only way a submission's
  status ever changes. Also adds
  `enforce_component_submission_pending_cap()`, a minimal anti-spam
  trigger capping pending submissions at 20 per account.
- **Touches no existing table.**
- **Context**: Milestone 19. The SQL/security audit pass
  (`docs/milestones/MILESTONE_19_SQL_SECURITY_AUDIT.md`) found and fixed
  a real race condition in `approve_component_submission()` (missing row
  lock — two concurrent approvals of the same submission could both
  proceed and orphan one insert) and added two symmetric cross-table
  collision guards, a status-consistency check constraint, and explicit
  execute grants, all before this file was applied.

## 0023_retailers_and_retail_variants

- **Status**: Proposed — not yet applied. Depends on 0020.
- **File**: `migrations/0023_retailers_and_retail_variants.sql`
- **Rollback**: `rollbacks/0023_retailers_and_retail_variants_rollback.sql`
- **Adds**: `retailers`, `component_retail_variants` (a specific buyable
  SKU under a generic `components` row — "ASUS TUF RTX 4080 OC" under
  "RTX 4080"), and `component_retailer_links` (attaches to a variant, not
  a component directly, since one generic part is sold as many different
  variants across many retailers). Schema-only — no real affiliate
  provider integration, no write policy on any of the three tables for
  anyone yet.
- **Touches no existing table.**
- **Context**: Milestone 19. The SQL/security audit pass added non-empty/
  nonnegative checks and two uniqueness constraints
  (`(component_id, variant_name)`, `(variant_id, url)`) this file's first
  draft was missing entirely — see
  `docs/milestones/MILESTONE_19_SQL_SECURITY_AUDIT.md`.
