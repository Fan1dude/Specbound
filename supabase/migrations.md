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
- **Corrected 2026-08-01** (same day, second dry run): the first version
  of this file reconstructed the *current* (post-`0023`) shape of these
  tables instead of the state immediately before `0001` — it included
  columns that `0002`/`0003`/`0005`/`0012` add themselves, so applying
  `0000` then running forward hit "column already exists" at `0002`
  (`builds.visibility`), then `0003` (`profiles.avatar_path`). Rewritten
  to exclude every column any tracked migration (`0001`-`0023`) adds via
  `ALTER TABLE` — full removal list, and which migration correctly owns
  each one, in the file's own header comment and the audit that produced
  it (see the commit that made this correction).
- **Corrected again 2026-08-01** (third dry run, reached `0017`): also
  adds the `project-images` Storage bucket and four `storage.objects`
  policies that predate migration tracking — `0017_storage_rls_hardening.sql`
  itself `DROP POLICY`s all four, and its own header states outright they
  match "Supabase's own dashboard-generated default-policy template
  names/shapes." Recreated verbatim from
  `0017`'s own rollback file (a direct `pg_policies` capture, not a
  reconstruction) rather than inferred. Cross-checked every `DROP POLICY`/
  `DROP FUNCTION`/`DROP TRIGGER` across all 24 migrations afterward — no
  other target is missing a tracked creator.
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
- **Fresh-database safety (added 2026-08-01)**: the 7 `revision_id`
  values are specific rows from the real production database — on a
  freshly-bootstrapped database none of them exist, and since
  `revision_media.revision_id` is a `NOT NULL` FK to `build_revisions(id)`,
  the `INSERT` failed outright instead of just finding nothing to guard
  against. Added a `join public.build_revisions` so the migration is a
  clean no-op on a fresh/dev database (0 rows match) and unchanged on the
  real one (all 7 still match). Audited every other migration mentioning
  "backfill" for the same hardcoded-literal-data pattern — `0018` is the
  only one; the rest are column-default backfills (`0002`) or explicitly
  backfill nothing (`0003`, `0005`, `0012`).
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
- **REWRITTEN for production compatibility** (2026-08-05): a real `db
  push` against production stopped safely at this exact migration —
  production already has a populated, differently-shaped
  `public.components` (9 rows; columns `id`, `technology_id`,
  `component_type`, `canonical_name`, `manufacturer`, `metadata`,
  `created_at`, `updated_at`, `canonical_key`; RLS; a public SELECT
  policy; its own indexes/constraints; a live
  `search_components(text,text,text,integer)` RPC with no migration file
  anywhere in this repo), which the original unconditional `CREATE
  TABLE` version of this file could never coexist with. The file is now
  fully additive/idempotent (`CREATE TABLE IF NOT EXISTS` →
  `ADD COLUMN IF NOT EXISTS` → null-guarded backfill → constraints added
  only after backfill → `IF NOT EXISTS` indexes → `DROP IF
  EXISTS`/`CREATE` trigger and policy) so it produces the identical
  final schema on a fresh database and on production's legacy one, and
  it **never drops or redefines** `component_type`, `canonical_key`, or
  `search_components()`. `field_key`/`normalized_name`/`created_by` are
  the new columns, backfilled from `component_type`/`canonical_name` and
  kept in sync with them going forward by a new
  `sync_component_legacy_fields` trigger — deliberately a plain column
  kept in sync by trigger, not `GENERATED ALWAYS AS`, since Postgres
  cannot convert `canonical_key`'s existing populated plain column into
  a generated one. See the file's own header comment for the full
  compatibility strategy and the paired rewritten rollback (which,
  unlike its original version, never drops `public.components` either).
- **Adds**: `catalog_moderators` (the app's first admin-role concept,
  scoped to this one subsystem) and `is_catalog_moderator(uid)` (a
  `SECURITY DEFINER` helper other tables' RLS policies reference), then
  `components` — the canonical parts catalog. Only a
  `catalog_moderators`-flagged user may insert directly; ordinary users
  contribute via `component_submissions` (0022) instead.
- **Touches no existing table** — see above for what "touches" means
  now that a legacy install path exists (adds columns/constraints to a
  pre-existing table, never renames or drops any of its columns).
- **Grant parity confirmed, not assumed** (read-only production audit,
  2026-08-06): this file adds no explicit `GRANT` statements on
  `components`/`component_aliases`/`catalog_moderators` themselves,
  relying instead on production's own `postgres`-owned default
  privileges (confirmed to already grant table/sequence privileges and
  function `EXECUTE` to `anon`/`authenticated`/`service_role` in
  `public`) applying automatically to these new objects the same way
  they already do to every existing table. This only works because
  every object this migration creates is created as `postgres` — no
  migration file in this repo ever switches role/owner — matching how
  production's existing `components`/`component_aliases` are
  themselves `postgres`-owned. RLS remains the actual row-level access
  control on top of this; the default privileges only establish that
  the tables are reachable at all. The local test harness (see
  `supabase/tests/` and `supabase/config.toml`'s
  `auto_expose_new_tables`) is deliberately configured to reproduce
  this confirmed behavior rather than the local CLI's newer, stricter
  default, so it accurately exercises what production will actually do.
- **Context**: Milestone 19 (Structured Parts Catalog). See
  `docs/milestones/MILESTONE_19_PARTS_CATALOG_ARCHITECTURE.md` for the
  full design and `docs/milestones/MILESTONE_19_SQL_SECURITY_AUDIT.md`
  for a follow-up audit pass (non-empty checks, explicit execute grants)
  applied to this file before it was considered ready. Automated
  fresh-install and legacy-upgrade tests for this file (through 0033)
  live in `supabase/tests/migration_0020_0033_fresh_install.test.sql`
  and `supabase/tests/migration_0020_0033_legacy_upgrade.test.sql`.

## 0021_component_aliases

- **Status**: Proposed — not yet applied. Depends on 0020.
- **File**: `migrations/0021_component_aliases.sql`
- **Rollback**: `rollbacks/0021_component_aliases_rollback.sql`
- **REWRITTEN for production compatibility**, same pass and same reason
  as 0020: production already has a populated `public.component_aliases`
  (6 rows; columns `id`, `component_id`, `alias`, `created_at`,
  `alias_key`). Rewritten the same way — additive/idempotent, never
  drops or redefines `alias`/`alias_key`, backfills the new
  `technology_id`/`field_key`/`normalized_alias` columns from the
  parent `components` row before adding constraints, and keeps
  `alias_key` in sync with `normalized_alias` going forward via
  `set_component_alias_technology_and_field` (extended, not replaced).
  Paired rollback rewritten the same way (never drops
  `public.component_aliases`).
- **Adds**: `component_aliases` — shorthand/misspelling mappings onto an
  existing `components` row (e.g. "4080" → "NVIDIA GeForce RTX 4080"),
  moderator-curated, no client-facing write path. `technology_id`/
  `field_key` are denormalized onto this table by a trigger, purely so a
  unique index can enforce "one alias string resolves to exactly one
  component per technology/field slot."
- **Touches no existing table** — see 0020's entry for what that means
  on the legacy-upgrade path.
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
- **Reviewed (not changed) for production compatibility**, same pass as
  0020/0021: `component_submissions` is wholly new on every install
  path, and `approve_component_submission()`/
  `reject_component_submission()` need no functional changes — every
  column they read or write is preserved unchanged by the corrected
  0020/0021, and their INSERTs into `components`/`component_aliases`
  transparently fire the new sync triggers, so legacy compatibility
  fields are populated consistently without this file needing to know
  those legacy columns exist. See the added header paragraph in the file
  itself for the full review notes.
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

## 0024_profile_headline_and_featured_build

- **Status**: Proposed — not yet applied. Depends on 0000-0023.
- **File**: `migrations/0024_profile_headline_and_featured_build.sql`
- **Rollback**: `rollbacks/0024_profile_headline_and_featured_build_rollback.sql`
- **Adds**: two nullable columns on `profiles` — `headline` (short hero
  tagline, `<=120` chars via a CHECK constraint, distinct from the
  existing longer `bio`) and `featured_build_id` (a builder-controlled
  pin, FK to `builds(id) on delete set null`, never selected
  automatically by likes or any other engagement metric). A new trigger,
  `validate_featured_build_before_write` /
  `public.validate_featured_build()`, enforces that `featured_build_id`
  — when set — always references a build owned by the same profile; RLS's
  existing whole-row "Users can update their own profile" policy can't
  express that cross-row ownership check on its own. The trigger checks
  ownership only, not visibility — a builder may pin a build that isn't
  currently public; the read path falls back to the documented selection
  chain (completed → published → hidden) whenever the pin is unset or no
  longer eligible.
- **Touches no other table.**
- **Context**: Milestone 20 (Builder Portfolio). See
  `docs/milestones/MILESTONE_20_BUILDER_PORTFOLIO_SPECIFICATION.md` §16
  for the full design and rationale, including why visibility is
  deliberately not enforced at write time.

## 0025_profile_onboarding_welcomed

- **Status**: Proposed — not yet applied. Depends on 0000-0024.
- **File**: `migrations/0025_profile_onboarding_welcomed.sql`
- **Rollback**: `rollbacks/0025_profile_onboarding_welcomed_rollback.sql`
- **Adds**: one nullable column on `profiles` — `onboarding_welcomed_at`,
  set the first time a builder exits the first-sign-in Welcome dialog
  (Continue, close, Escape, or backdrop click all count as "exited").
  `null` means eligible to see the Welcome screen on the next
  authenticated page load; any non-null value means never show it again.
  Backfills every pre-existing row to its own `created_at`, so only
  accounts created after this migration is applied are eligible to see
  onboarding — existing builders are never shown it.
- **Touches no other table.**
- **Context**: Milestone 21 (First-Time Builder Experience). See
  `docs/milestones/MILESTONE_21_FIRST_TIME_BUILDER_EXPERIENCE_SPECIFICATION.md`
  §4 for the full design, including why this is the only Milestone 21
  state that needed a schema change — everything else is either computed
  live or kept in namespaced `localStorage`.

## 0026_social_connections

- **Status**: Proposed — not yet applied. Depends on 0000-0025.
- **File**: `migrations/0026_social_connections.sql`
- **Rollback**: `rollbacks/0026_social_connections_rollback.sql`
- **Adds**: `social_connections` — a mirror of a builder's connected
  Discord identity (provider-discriminated, shaped for a future second
  OAuth provider without a rename), and `sync_discord_identity()`, the
  only way a row is created. OAuth itself is handled entirely by
  Supabase Auth's native `linkIdentity()` — this table never stores a
  token, only public identity claims. `is_public` (default false)
  independently controls whether a connection is ever shown on a public
  profile; connecting never implies displaying.
- **Touches no other table.**
- **Context**: Milestone 22 (Community Foundation). See
  `docs/milestones/MILESTONE_22_COMMUNITY_FOUNDATION_SPECIFICATION.md`
  §4 and §0.1 for the full design, including why this shape was
  generalized beyond a Discord-only table during the final design
  review.

## 0027_profile_roles

- **Status**: Proposed — not yet applied. Depends on 0000-0026.
- **File**: `migrations/0027_profile_roles.sql`
- **Rollback**: `rollbacks/0027_profile_roles_rollback.sql`
- **Adds**: `profile_roles` (manually-awarded and permission-bearing
  community roles — `community_builder`, `project_mentor`, `moderator`,
  `staff`; automatic roles are never stored, see `communityRecognition.js`),
  `is_platform_moderator()`, `is_platform_staff()`. Read-only in this
  file — the write RPCs (`grant_profile_role()`/`revoke_profile_role()`)
  are in `0028_moderation.sql`, since they need to log into
  `moderation_actions`, which doesn't exist until that file.
- **Touches no other table.**
- **Context**: Milestone 22 (Community Foundation). See
  `docs/milestones/MILESTONE_22_COMMUNITY_FOUNDATION_SPECIFICATION.md`
  §5, §8.1.

## 0028_moderation

- **Status**: Proposed — not yet applied. Depends on 0000-0027.
- **File**: `migrations/0028_moderation.sql`
- **Rollback**: `rollbacks/0028_moderation_rollback.sql`
- **Adds**: `content_reports`, `moderation_actions`,
  `report_content()`, `resolve_report()`, `grant_profile_role()`,
  `revoke_profile_role()`. Deliberately two tables, not one — see the
  file's own header and spec §0.2 for the concrete reasons a merge would
  make the design worse, not just look bigger on paper.
- **Touches no other table** (this migration and `0031` must be applied
  together — `resolve_report()`/`grant_profile_role()` call
  `create_notification()` with no `build_id`, which is only valid once
  `0031` widens that function's signature).
- **Context**: Milestone 22 (Community Foundation). See
  `docs/milestones/MILESTONE_22_COMMUNITY_FOUNDATION_SPECIFICATION.md`
  §8.

## 0029_feedback_submissions

- **Status**: Proposed — not yet applied. Depends on 0000-0028.
- **File**: `migrations/0029_feedback_submissions.sql`
- **Rollback**: `rollbacks/0029_feedback_submissions_rollback.sql`
- **Adds**: `feedback_submissions`, `submit_feedback()`. `user_id` is
  nullable with `on delete set null` (not `cascade`) — feedback is
  product signal that should outlive the account that submitted it.
- **Touches no other table.**
- **Context**: Milestone 22 (Community Foundation). See
  `docs/milestones/MILESTONE_22_COMMUNITY_FOUNDATION_SPECIFICATION.md`
  §9.

## 0030_beta_invites

- **Status**: Proposed — not yet applied. Depends on 0000-0029.
- **File**: `migrations/0030_beta_invites.sql`
- **Rollback**: `rollbacks/0030_beta_invites_rollback.sql`
- **Adds**: `beta_invites`, `redeem_beta_invite()`. Narrowed scope per
  the final design review (spec §0.2) — only for shareable, redeem-
  anywhere codes; direct email invitations use Supabase Auth's native
  admin invite feature and need no schema at all.
- **Touches no other table.**
- **Context**: Milestone 22 (Community Foundation). See
  `docs/milestones/MILESTONE_22_COMMUNITY_FOUNDATION_SPECIFICATION.md`
  §10.

## 0031_guidelines_and_notification_types

- **Status**: Proposed — not yet applied. Depends on 0000-0030 (and must
  be applied together with `0028`, see that entry above).
- **File**: `migrations/0031_guidelines_and_notification_types.sql`
- **Rollback**: `rollbacks/0031_guidelines_and_notification_types_rollback.sql`
- **Adds**: `profiles.guidelines_accepted_at` (one nullable timestamp).
  **Modifies**: `notifications.type` CHECK widened to add
  `role_awarded`/`report_resolved`; `notifications.build_id` relaxed to
  nullable (a role grant or report resolution isn't necessarily about a
  build); `create_notification()` replaced to give `p_build_id` a
  default of `null`, matching this project's existing convention of
  modifying already-applied functions via `CREATE OR REPLACE` rather
  than editing the migration that first defined them.
- **Context**: Milestone 22 (Community Foundation). See
  `docs/milestones/MILESTONE_22_COMMUNITY_FOUNDATION_SPECIFICATION.md`
  §7, §11.

## 0032_restrict_profile_roles_visibility

- **Status**: Proposed — not yet applied. Depends on 0000-0031.
- **File**: `migrations/0032_restrict_profile_roles_visibility.sql`
- **Rollback**: `rollbacks/0032_restrict_profile_roles_visibility_rollback.sql`
- **Fixes**: a data-exposure finding from the Milestone 20 Builder
  Portfolio branch's final review — 0027's `profile_roles` SELECT
  policy was `using (true)` with no column restriction, so `note`
  (a moderator's internal grant comment) and `granted_by` were
  retrievable by any direct API caller, not just the `role` column the
  app itself ever asked for.
- **Modifies**: `profile_roles`' SELECT policy, replaced with
  authenticated-only access to a user's own roles or (for a
  moderator/staff caller) everyone's. **Adds**:
  `get_public_profile_roles(uuid)` — a SECURITY DEFINER function
  returning only `role`, granted to `anon` and `authenticated`, the new
  public read path for role badges. A function rather than a public
  view on purpose — see the migration's own header for why a view here
  would risk Supabase's "security_definer_view" footgun (silently
  exposing every row, not just the intended columns).
- **Touches no other table.** `communityRepository.js`'s
  `getProfileRoles()` was updated in the same commit to call the new
  function instead of selecting from the table directly; its exported
  signature is unchanged.
- **Context**: post-merge-review hardening for Milestone 22 (Community
  Foundation).

## 0033_restrict_function_execute_permissions

- **Status**: Applied to production. The 17 explicit per-function
  REVOKE/GRANT statements (the SQL manually applied through the
  Supabase SQL Editor, verified successful) had already secured the 17
  existing functions in production before this migration file existed.
  The GLOBAL default-privilege statement (`alter default privileges
  for role postgres revoke execute on functions from public;`) was
  added afterward and initially validated only in local testing; it
  has since been applied to the linked Specbound production project
  (ref `xpxjqyraizntbtijzoyp`) via `supabase db push --linked`, and
  migration 0033 is now recorded in that project's migration-history
  table. A later read-only preflight re-confirmed this: a fresh
  `supabase migration list --linked` showed matching local and remote
  entries through 0033, and a fresh `supabase db push --linked
  --dry-run` showed zero pending migrations. No additional production
  changes were made during that preflight or during this documentation
  update, and the rollback was not run at any point in this work.
  Every statement in this migration is idempotent, so a repeat run
  would remain safe even though production's grants already match it.
  Merging the pull request containing this file did not itself deploy
  it — this repository's CI runs only static/browser-test checks and
  does not apply database migrations; deployment required the manual
  CLI step described above. Depends on 0000-0032.
- **File**: `migrations/0033_restrict_function_execute_permissions.sql`
- **Rollback**: `rollbacks/0033_restrict_function_execute_permissions_rollback.sql`
- **Fixes**: a read-only production audit (pg_catalog/information_schema
  only) found that every function introduced by 0020-0032 had effective
  EXECUTE access for both `anon` and `authenticated`, regardless of what
  each migration's own `revoke ... from public` intended — that
  statement only removes what PUBLIC (the pseudo-role) held, never a
  privilege granted directly to `anon`/`authenticated` as their own
  roles, which Supabase's own default-privilege configuration for the
  public schema was doing on every new `postgres`-owned function.
  `create_notification()` was the highest-severity instance: `SECURITY
  DEFINER`, accepts caller-supplied `recipient_id`/`actor_id`/type/IDs,
  and has no internal `auth.uid()` check of its own — its entire
  protection was supposed to be the (broken) grant.
- **Changes default privileges** so future `postgres`-owned functions in
  `public` no longer automatically become callable by `public`/`anon`/
  `authenticated`. **Revokes** unintended `anon`/`authenticated` access
  from all 17 functions 0020-0032 introduced. **Re-grants**
  `authenticated`-only access to the 12 that are genuine signed-in RPCs
  or RLS helpers (`is_catalog_moderator`/`is_platform_moderator` are in
  this list because `authenticated` needs EXECUTE for the RLS policies
  that call them to evaluate at all — not because they're meant to be
  called directly by most users). Leaves the 4 trigger-only functions
  and `create_notification()` with no client-facing grant at all — none
  of them are meant to be reachable by a client role, trigger or
  internal-only. **Re-confirms** `get_public_profile_roles(uuid)` for
  both `anon` and `authenticated` — unaffected, already correct by
  design since 0032.
- **Touches no table, no RLS policy, no schema.** `service_role` and
  every function's owner are untouched — out of scope for this
  migration (see the PR description for why).
- **Local verification note**: local testing found that a schema-scoped
  default-privilege revoke alone was not sufficient — PostgreSQL's
  hardcoded global PUBLIC-EXECUTE default for new functions is only
  overridden by a matching GLOBAL `pg_default_acl` entry, not a
  schema-scoped one. 0033 now issues both a global and a schema-scoped
  `alter default privileges` statement. See the migration file's own
  header and `migration_0033_function_execute_permissions.test.sql`
  test 7 for the full explanation and the confirmed fix.
- **Context**: post-merge production security audit, Milestone 22
  (Community Foundation) follow-up.

## 0034_profile_guidelines_accepted_version

- **Status**: Applied to production. Confirmed via `supabase migration
  list --linked` during the Milestone 23 production deployment
  preflight (2026-08-12): 0034 was already present in the linked
  Specbound production project's (`xpxjqyraizntbtijzoyp`) migration-
  history table, matching local — it had been deployed at some earlier
  point, before that audit, without this file's status ever being
  updated to say so. Only 0035 (below) was genuinely pending at that
  time; that mismatch between this document and the real database is
  what the preflight caught. Depends on 0000-0033 (specifically 0031,
  which introduced `guidelines_accepted_at`).
- **File**: `migrations/0034_profile_guidelines_accepted_version.sql`
- **Rollback**:
  `rollbacks/0034_profile_guidelines_accepted_version_rollback.sql`
- **Adds**: one nullable `text` column on `profiles` —
  `guidelines_accepted_version`, plus a CHECK constraint
  (`profiles_guidelines_accepted_version_format_check`) requiring it to
  be null or a `YYYY-MM-DD` date string. Records which specific revision
  of the Community Guidelines a user last agreed to, distinct from
  `guidelines_accepted_at` (when they agreed to it).
- **No backfill, by design** — every existing row, including rows with a
  pre-existing non-null `guidelines_accepted_at` from accepting the
  earlier draft Guidelines page, is left with
  `guidelines_accepted_version = null`. The application gate
  (`js/repositories/communityRepository.js`) requires the stored version
  to equal `CURRENT_GUIDELINES_VERSION`
  (`js/config/guidelines.js`, currently `"2026-08-11"`) — a draft-era
  timestamp with no matching version does not satisfy it, so those users
  are correctly re-prompted to accept the finalized text.
- **Touches no other table.**
- **Context**: Community Guidelines finalization — the guidelines page
  shipped as a draft in 0031/Milestone 22; this migration lets the
  acceptance gate distinguish "accepted the draft" from "accepted the
  final published text."

## 0035_setup_inventory_and_builder_dates

- **Status**: Applied to production. Before deployment, a real Builder
  Portfolio page load against the shared/production project failed
  with `42703 column profiles.building_since_year does not exist`,
  confirming it was genuinely pending. Applied 2026-08-12 via `supabase
  db push --linked --yes` to the linked Specbound production project
  (`xpxjqyraizntbtijzoyp`) — the one migration a dry run identified as
  pending (0000-0034 already matched local at that point; see 0034's
  own entry above for that discrepancy). Verified afterward: a fresh
  `supabase migration list --linked` showed 0000-0035 matching local
  and remote, and a second `supabase db push --linked --dry-run`
  reported production up to date. Depends on 0000-0034 (specifically
  0002/0004/0006 for `publish_draft()`'s current body and 0005 for
  `restore_revision_to_draft()`'s).
- **File**: `migrations/0035_setup_inventory_and_builder_dates.sql`
- **Rollback**:
  `rollbacks/0035_setup_inventory_and_builder_dates_rollback.sql`
- **Adds**:
  - `setup_inventory jsonb not null default
    '{"schemaVersion":1,"currency":"USD","categories":[]}'::jsonb` on
    `project_drafts`, `builds`, and `build_revisions` — the Setup
    technology's (`technology.id === "setup"`) structured product
    inventory. Deliberately a separate structure from the existing
    per-technology `specifications` jsonb column — it does not replace
    or touch `specifications` on any table, so PC-build/Arduino/
    robotics/3D-printer/homelab specs, the parts catalog, imports, and
    revision history are all untouched.
  - `public.saved_setup_categories` (id, user_id, name, normalized_name,
    created_at, updated_at) — private, owner-scoped, reusable category
    templates. RLS: 4 owner-only policies (select/insert/update/delete,
    all `auth.uid() = user_id`); **no public/anon read policy**. A
    case/whitespace-insensitive unique index on `(user_id,
    normalized_name)` prevents duplicate saved categories per builder. A
    `CHECK` requires a non-blank, length-bounded name. Reuses the
    existing shared `public.set_updated_at()` trigger; adds one new
    trigger function, `set_saved_setup_category_normalized_name()`.
  - `profiles.building_since_year integer`, nullable, with a `CHECK`
    bounding it to `1980..extract(year from now())`. Distinct from the
    existing, unrelated `profiles.created_at` (the account's real join
    date) — no backfill; every existing row gets `null`.
  - Replaces `publish_draft()` and `restore_revision_to_draft()` in
    place — full bodies sourced from their true latest prior
    definitions (0006 and 0005 respectively, confirmed by grepping every
    later redefinition, not assumed), each with a small, clearly marked
    addition so `setup_inventory` is copied on publish/republish (into
    both `builds` and the new `build_revisions` row) and restored from a
    revision snapshot back onto the draft. `create or replace function`
    preserves each function's existing grants — no new `grant execute`
    statements needed for either.
- **No new SECURITY DEFINER function** — every new table's CRUD goes
  through plain RLS-governed `supabase-js` calls, the same
  "RLS is the real gate, no RPC needed" pattern already used for
  `onboarding_welcomed_at`/`guidelines_accepted_at`/`_version`. Migration
  0033's function-EXECUTE hardening therefore has no new surface to
  close here.
- **Compatibility**: a pre-existing revision restored after this
  migration gets `setup_inventory` from its own DB-level column default
  (the empty-inventory shape) if the revision predates snapshot capture
  for this field; the editor and public build page both render an empty
  inventory as "nothing to show" rather than an error. Confirmed live
  against a real pre-Milestone-23 Setup blueprint: the new public
  Setup-Inventory section renders in the DOM but stays cleanly hidden,
  while that build's legacy `specifications` fields render exactly as
  before.
- **Context**: Milestone 23 (Setup Inventory, Search & Builder History) —
  see `docs/milestones/MILESTONE_23_SETUP_INVENTORY_SEARCH_SPECIFICATION.md`
  for the full architecture, JSON contract, and security rationale.

## 0036_resolve_report_atomic_status_guard

- **Status**: Applied to the local disposable Supabase/Docker stack
  (`npx supabase migration up --local`, 2026-08-12), verified live, then
  applied to production the same day ahead of merging PR #19, per the
  approved migration-first release order.
- **Purpose**: closes a double-resolution race in `resolve_report()`
  (0028_moderation.sql, Milestone 22) found and empirically confirmed
  during PR #19 review for Milestone 24 — two moderator sessions could
  both successfully resolve the same report, the second silently
  overwriting the first's decision and producing duplicate
  `moderation_actions`/notification rows for one event.
- **Change**: `create or replace function public.resolve_report(...)` —
  identical signature, security mode, `search_path`, authorization
  check, `moderation_actions` insert, notification call, and grants.
  Only the `UPDATE`'s `WHERE` clause changes, adding `and status =
  'open'`, with `UPDATE ... RETURNING` itself as the atomic claim (no
  new locking primitive or isolation level — ordinary Postgres
  row-level UPDATE locking under READ COMMITTED is sufficient). A
  report that no longer matches now raises a distinct `'This report has
  already been resolved.'` message, separate from the pre-existing
  `'Report not found.'` case.
- **No table/column/index change** — this migration touches only one
  function's body and its grants.
- **Rollback**: `0036_resolve_report_atomic_status_guard_rollback.sql`
  in `supabase/rollbacks/` restores the exact pre-0036 function body,
  verbatim from 0028. No data is touched by either direction.
- **Local verification**: the exact two-session sequence that produced
  conflicting/duplicate rows before this migration was re-run
  immediately after applying it — the second call now raises the
  already-resolved error, the first decision is untouched, and exactly
  one `moderation_actions` row and one notification remain. See
  `supabase/tests/milestone_24_resolve_report_atomic_guard.test.sql`
  (10 assertions, all passing) plus the corrected Test 13 in
  `supabase/tests/milestone_24_moderator_report_queue.test.sql`.
- **Context**: Milestone 24 (Moderator Report Queue) — see
  `docs/milestones/MILESTONE_24_MODERATOR_REPORT_QUEUE_SPECIFICATION.md`
  §4 for the full writeup, including the empirical before/after
  demonstration.

## 0037_follow_notifications

- **Status**: Applied to the local disposable Supabase/Docker stack only
  (`npx supabase migration up --local`, 2026-08-13), live-verified
  end-to-end via two real local accounts, plus a full rollback-and-
  restore-forward rehearsal against real local notification rows.
  **Not applied to production.**
- **Purpose**: `set_follow()` (0012_follows.sql, Milestone 7C) has never
  called `create_notification()` — that file's own header comment says
  so explicitly, calling it out-of-scope at the time. Milestone 25
  closes that gap: a builder is now notified when someone new follows
  them.
- **Change**: widens `notifications_type_check` to add `'follow'` to
  the existing allowed set. `create or replace function
  public.set_follow(...)` — identical signature, `SECURITY DEFINER`,
  `search_path`, self-follow protection, and grants. Only the
  `p_followed = true` branch changes: the `insert ... on conflict
  (follower_id, following_id) do nothing` now captures the inserted
  row's id via `returning id into v_inserted_id`, and
  `create_notification(p_following_id, v_follower_id, 'follow')` is
  called only when that id is non-null — i.e. only on a genuinely new
  follow row, never on an already-existing follow (idempotent re-calls,
  a duplicate button click) and never on unfollow. The `p_followed =
  false` (unfollow) branch is untouched. Reuses the exact atomic
  `INSERT ... ON CONFLICT ... RETURNING ... check not null` pattern
  from `0036_resolve_report_atomic_status_guard.sql`.
- **Stored notification shape**: `type = 'follow'`, `recipient_id` =
  the followed user, `actor_id` = the follower, `build_id = null`,
  `comment_id = null` — a follow has no associated build, same
  shape as `report_resolved`.
- **Rollback is intentionally behavioral, not a full schema reversal**
  — this was a required correction before implementation began.
  `0037_follow_notifications_rollback.sql` restores only `set_follow()`
  to its exact pre-0037 body (future follows stop notifying). It
  deliberately does **not** narrow `notifications_type_check` back to
  its pre-0037 values, and never touches, deletes, or rewrites any
  existing `'follow'`-typed notification row — narrowing the
  constraint back would fail outright once any `'follow'` row exists,
  or would require destroying legitimate user notifications to make it
  succeed. An already-old (pre-Milestone-25) frontend encountering a
  `'follow'` row it doesn't recognize already has a safe fallback path:
  `notificationFormat.js`'s `default` case (the same fallback
  `role_awarded` rows have relied on, unremarked, since migration
  `0031`) — proven directly in this session, not assumed, by rolling
  back locally with three real pre-rollback `'follow'` notifications
  present, confirming all three survived unchanged and a post-rollback
  follow created no fourth row, then restoring `0037` forward again.
- **No table/column/index removal ever, in either direction.**
- **Rollback**: `0037_follow_notifications_rollback.sql` in
  `supabase/rollbacks/`.
- **Related fix, same branch, different file**: live verification of
  this migration surfaced a pre-existing bug in
  `notificationRepository.js`'s `enrichNotifications()` — unrelated to
  this migration's own SQL, but only actually exercised by a real
  browser session once a notification with `build_id = null` existed
  and its type wasn't filtered out before hitting `getBuildsByIds()`.
  That helper does an unguarded `.in("id", ids)`; a raw `null` in that
  array reaches PostgREST as the literal `id=in.(null)`, and Postgres
  rejects `null` as a `uuid` (`22P02`), breaking the notification bell
  and the notifications page entirely for the affected user. This
  already affects `report_resolved` notifications live in production
  today (`report_resolved` also always has `build_id = null`) — it
  predates this milestone and was not introduced by it. Fixed by
  filtering out falsy `build_id` values before the batch fetch. See
  `js/repositories/notificationRepository.js`.
- **Context**: Milestone 25 (Follow Notifications) — see
  `docs/milestones/MILESTONE_25_FOLLOW_NOTIFICATIONS_SPECIFICATION.md`.

## 0038_restrict_pre_0020_function_execute_permissions

- **Status**: Applied to the local disposable Supabase/Docker stack only
  (full `supabase db reset --local` through `0038`, plus an isolated
  apply/rollback/reapply rehearsal), live-verified against both the
  grant state and actual signed-in/signed-out call behavior. **Not
  applied to production.**
- **Purpose**: security-hardening follow-up from Milestone 25's
  production release. `0033_restrict_function_execute_permissions.sql`
  closed the "every function has a stray `anon` EXECUTE grant left by
  Supabase's own default privileges, despite the migration's own `revoke
  all ... from public` clearly intending `authenticated`-only" finding
  for every function introduced by `0020`-`0032`. It was explicitly
  scoped to that generation only and never re-examined the earlier
  `0002`-`0012` functions, which predate it. A grant audit performed
  during Milestone 25's production release found the identical pattern
  still live on `set_follow(uuid, boolean)` (`0012`/`0037`) and, on
  closer inspection, on nine sibling pre-`0020` functions.
- **Change**: `revoke execute ... from anon` (only — `authenticated` is
  completely untouched) on: `create_comment(uuid, text)`,
  `delete_comment(uuid)`, `set_build_like(uuid, boolean)`,
  `set_build_saved(uuid, boolean)`, `mark_notification_read(uuid)`,
  `mark_all_notifications_read()`, `publish_draft(uuid, text, text)`,
  `restore_revision_to_draft(uuid, timestamptz)`,
  `set_build_visibility(uuid, text)`, `set_follow(uuid, boolean)`. Every
  one of these already had an explicit `grant execute ... to
  authenticated` in the migration that introduced it — none of them was
  ever meant to be callable by `anon`. No function body is touched; no
  new default-privilege statement is added (`0033` already closed that
  gap for every function created after it).
- **Deliberately not touched**: `get_activity_feed()` and
  `record_build_view(uuid, uuid)` (both intentionally `anon` +
  `authenticated` per their own `0013`/`0010` source — genuinely public
  reads), `get_public_profile_roles(uuid)` (intentionally public per
  `0032`, re-confirmed by `0033`), `create_notification()` and every
  function `0033` already covers (confirmed unchanged by direct live
  `proacl` inspection before writing this migration), and
  `resolve_report()` (redefined again by `0036`, which reissued its own
  authenticated-only grant — confirmed already `anon`-free).
- **Not exploitable before this fix**: every one of the ten functions
  has its own internal `auth.uid()`-null check that rejects an
  unauthenticated caller before any read or write happens. This is
  defense-in-depth, not a fix for a demonstrated access bypass. Verified
  directly: before `0038`, calling `set_follow()` as `anon` failed
  inside the function body (`'You must be signed in to follow a
  builder.'`); after `0038`, the same call fails earlier, at the grant
  layer itself (`permission denied for function set_follow`, Postgres
  `42501`) — a strictly stronger failure mode, empirically confirmed,
  not just asserted.
- **Signed-in behavior confirmed unaffected**: `authenticated` grants
  are completely untouched by this migration and no function body
  changed, so there is no mechanism by which normal signed-in behavior
  could regress. Verified directly against two disposable local
  accounts: `set_follow()` and `mark_all_notifications_read()` both
  still succeed identically as `authenticated`, before and after.
- **Rollback**: `0038_restrict_pre_0020_function_execute_permissions_
  rollback.sql` in `supabase/rollbacks/` — restores the exact pre-0038
  (`anon`-inclusive) grant on all ten functions. Rehearsed locally:
  applied, confirmed `anon` regained EXECUTE, then reapplied `0038`
  forward again.
- **Context**: Milestone 25 follow-up (security hardening) — see
  `docs/milestones/MILESTONE_25_FOLLOW_NOTIFICATIONS_SPECIFICATION.md`
  and the spawned follow-up task recorded during that milestone's
  production release.

## 0039_feedback_status_workflow

- **Status**: Applied to the local disposable Supabase/Docker stack only
  (full `supabase db reset --local` through `0039`, plus an isolated
  apply/rollback/reapply rehearsal with real feedback rows and real
  actorless notification rows present). **Not applied to production.**
- **Purpose**: `feedback_submissions` (0029, Milestone 22) has carried a
  `status` column since it shipped, but nothing has ever written past
  its `'open'` default — no RPC, no UPDATE RLS policy. Milestone 26
  closes that gap: a moderator or staff member can now mark a submission
  Reviewed or Closed, and the submitter is notified.
- **Schema changes**:
  - `feedback_submissions.status_updated_at timestamptz`, nullable, no
    default. Existing/new Open rows keep it `null`; only a successful
    `update_feedback_status()` call ever sets it, atomically with the
    status change itself. Lets the reviewer History view sort by "most
    recently actioned" instead of `created_at`.
  - `notifications_type_check` widened to add `'feedback_reviewed'` and
    `'feedback_closed'` — two distinct frozen event types (not one type
    with a live status join), so a notification's rendered text can
    never retroactively change if the same submission is later actioned
    again.
  - `notifications.actor_id` changed from `not null` to nullable — the
    reviewer-identity privacy fix, added as a required correction before
    implementation began (the original plan reused `report_resolved`'s
    pattern of a real `actor_id` + fixed rendered text, but inspecting
    the full data path showed the raw `actor_id` and a separately-fetched
    actor profile are both already client-visible via
    `notifications.select("*")`/`enrichNotifications()`, regardless of
    what the UI chooses to render). Every existing notification type is
    completely unaffected — all of them always pass a real actor_id;
    this only permits a new possibility, it requires nothing.
- **New function**: `update_feedback_status(p_feedback_id uuid,
  p_expected_status text, p_new_status text)` — `SECURITY DEFINER`,
  re-checks `is_platform_moderator(auth.uid())` itself, validates the
  transition against an explicit 3-entry allow-list (`open→reviewed`,
  `open→closed`, `reviewed→closed`; Closed is terminal, no no-op is ever
  valid), and claims the row atomically (`update ... where id = ... and
  status = p_expected_status returning ...`) — same technique as
  `resolve_report()`'s guard (`0036`), generalized with an explicit
  expected-status parameter since feedback's graph has two valid source
  statuses where a report's has one. On success, creates exactly one
  notification (`recipient_id` = the submitter, `actor_id` = `null`,
  never `auth.uid()`) — skipped entirely when `user_id` is null (a
  deleted submitter's row updates silently). No UPDATE RLS policy is
  added; this function remains the only write path, matching
  `submit_feedback()`'s existing insert-only posture.
- **Rollback is deliberately the narrowest in this chain so far** — it
  drops ONLY the function. It does **not** drop `status_updated_at`
  (a populated column would be destroyed with no way to recover it by
  reapplying forward), does **not** narrow `notifications_type_check`
  back (would fail outright or destroy real notifications once either
  new type has been used), and does **not** restore `actor_id`'s `not
  null` constraint (would fail outright once any actorless row exists,
  and has no protective value to restore once nothing can insert one
  anyway). Net effect: schema stays exactly as `0039` left it, all
  feedback rows/statuses/timestamps and all notifications (actor-backed
  and actorless alike) are untouched; only future status changes stop
  being possible until re-applied.
- **Rollback**: `0039_feedback_status_workflow_rollback.sql` in
  `supabase/rollbacks/`.
- **Related fix, same branch, different file**: `enrichNotifications()`
  (`js/repositories/notificationRepository.js`) now filters out falsy
  `actor_id` values (the same `.filter(Boolean)` guard it already
  applied to `build_id` since `0037`'s follow-up fix) before batching
  the profile lookup — an actorless notification's `actor_id` would
  otherwise reach `getProfilesByIds()`'s `.in("id", ids)` as a literal
  `null` in the array and be rejected by Postgres the same way an
  unfiltered `build_id` was.
- **Context**: Milestone 26 (Feedback Review) — see
  `docs/milestones/MILESTONE_26_FEEDBACK_REVIEW_SPECIFICATION.md`.
