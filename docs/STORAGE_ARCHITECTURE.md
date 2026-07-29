# Storage Architecture

**Status: current and accurate as of Migration C (`0018_legacy_media_linkage_backfill`), applied and verified 2026-07-26.**

This document describes the final, live state of Specbound's Supabase Storage subsystem after the Milestone 9 security remediation (Migrations A, B, C). It supersedes the storage-related sections of `docs/milestones/MILESTONE_9_ARCHITECTURE.md` (findings S1, S3, S6), which are historical/pre-fix.

---

## 1. Bucket

One bucket: **`project-images`**, referenced as `BUCKET`/`PROJECT_IMAGES_BUCKET` in `js/repositories/mediaRepository.js` and `js/services/imageService.js`.

- **Public/private flag: Private**, since Migration A's post-hardening flip (verified live). The direct public object endpoint (`/storage/v1/object/public/project-images/{path}`) no longer resolves to anything for any object, regardless of the object's ownership or the referencing build's visibility.
- The **only** way to fetch an object's bytes is a signed URL (`createSignedUrl()`/`createSignedUrls()`), and generating one requires the caller's session to satisfy `storage.objects` RLS for that path — bucket privacy and RLS are independent, complementary layers (see §6).
- `list()`, `.upload()`, `.update()`, `.remove()` all evaluate the same `storage.objects` RLS regardless of the bucket's public/private flag — only the direct public object endpoint is gated purely by that flag.

## 2. Folder layout

All paths live under a single flat bucket namespace, distinguished by their first path segment (`storage.foldername(name)[1]`):

| Prefix | Contents | Written by | Convention since |
|---|---|---|---|
| `avatars/{userId}/{size}.jpg` | Profile avatar image variants — 4 sizes per user (`500`, `200`, `64`, `32`) | `imageService.uploadAvatar()` | Milestone 5A (`0003_profile_avatar_path.sql`) |
| `projects/{draftId}/{mediaId}.jpg` | Draft gallery images, keyed by the owning `project_drafts.id` and a caller-supplied media id | `imageService.uploadGalleryImage()` | Milestone 5A |
| `{legacyUserId}/...` (bare user-id folder, no `projects/`/`avatars/` prefix) | Pre-Milestone-5A gallery uploads — includes direct children and `revisions/`, `updates/`, `builds/` subfolders | Legacy code, predates current upload pipeline | Pre-5A only; nothing currently writes new objects here |
| *(bucket root, no folder)* | Legacy objects uploaded before any folder convention existed | Legacy code | Pre-5A only |

`storage.foldername(name)` is the schema's standard way to derive ownership/routing from a path — `(storage.foldername(name))[1]` gives the top-level prefix, `[2]` the next segment (a user id, a draft id, etc.), used throughout every `storage.objects` RLS policy (§6).

## 3. Upload flow

Two upload pipelines, both in `js/services/imageService.js`, both client-side-processed (resize/crop via `<canvas>`) before upload — nothing is ever uploaded unprocessed:

**Avatars** (`uploadAvatar(userId, file)`):
1. Validate MIME type (`jpeg`/`png`/`webp`) and size (≤ 8 MB).
2. Load the image, center-crop to square, render 4 size variants (500/200/64/32px) via canvas.
3. Upload each variant to `avatars/{userId}/{size}.jpg` with `upsert: true` — a re-upload overwrites in place, so no orphaned old-size files accumulate.
4. Return the canonical 500px variant's storage **path** (not a URL) — the caller persists this to `profiles.avatar_path`.

**Gallery images** (`uploadGalleryImage(draftId, mediaId, file)`):
1. Validate MIME type and size (same limits as avatars).
2. Constrain to a max 2000px dimension, preserving aspect ratio (unlike avatars, not cropped to square — lightboxes need real proportions).
3. Upload to `projects/{draftId}/{mediaId}.jpg` with `upsert: true`.
4. Currently also calls `getPublicUrl()` and returns that value — **dead output**: the bucket is private so this URL never resolves, and the only caller (`js/pages/editor/renderGallerySection.js:55`) discards the return value entirely. Flagged as cleanup item S6 in `MILESTONE_9_ARCHITECTURE.md`, not yet removed — harmless today since nothing reads or stores it, but should be deleted during Phase 9C so no code path continues constructing a public URL for a bucket that's supposed to be private.
5. `deleteGalleryImage(draftId, mediaId)` is the rollback counterpart — removes the Storage object at the same deterministic path, used when a subsequent `project_media` insert fails after a successful upload, so the file isn't orphaned.

Upload RLS: `storage.objects` INSERT is scoped per-prefix (§6) — a draft owner can only insert under `projects/{their own draftId}/`, an authenticated user can only insert under `avatars/{their own userId}/`. No broad or unscoped INSERT policy exists as of Migration A.

## 4. `revision_media` flow

`public.revision_media` is the authoritative link between a **published, immutable revision** and its storage objects — introduced in `0002_publish_draft_and_visibility.sql` alongside `publish_draft()`.

- Schema: `id uuid primary key`, `revision_id uuid not null references build_revisions(id) on delete cascade`, `storage_path text not null`, `display_order integer not null default 0`, `alt_text text not null default ''`, `is_cover boolean not null default false`, `created_at timestamptz`.
- Unique index `revision_media_one_cover_per_revision_idx on (revision_id) where is_cover` — at most one cover per revision.
- **Written exactly once, at publish time**, by `publish_draft()` (`SECURITY DEFINER`, internal `auth.uid()` ownership check) — it copies the draft's `project_media` rows into `revision_media` under the new/updated revision, as part of the same transaction that creates the `build_revisions` row. Nothing else inserts into `revision_media` in normal operation — the sole exception is Migration C's one-time backfill (§9).
- **Read** via `getRevisionMedia(revisionId)` in `mediaRepository.js`, ordered by `display_order`. This is how the build page's revision-history section and timeline get each revision's images.
- Because a revision is immutable once published, `revision_media` rows for it never change after creation (except the one-time Migration C backfill for pre-tracking legacy rows).

`project_media` is the **draft-side** counterpart — mutable, tied to `project_drafts.id`, edited freely while a project is still a draft (`getDraftMedia`, `addMedia`, `deleteMedia` in `mediaRepository.js`). `publish_draft()` is the only bridge from `project_media` to `revision_media`.

## 5. Avatar flow

- `profiles.avatar_path` (storage path, e.g. `avatars/{userId}/500.jpg`) is the current convention, written by `uploadAvatar()` since Milestone 5A (`0003_profile_avatar_path.sql`).
- `profiles.avatar_url` is the legacy pre-5A column — either empty, or a ready-to-use URL (possibly this bucket's own now-unfetchable public URL, handled by the compatibility layer, §7).
- **Read precedence**, in both `resolveAvatarUrl()` (single) and `resolveAvatarUrls()` (batch): `avatar_path` wins if present (sign it); otherwise fall back to `avatar_url`, running it through the same legacy-URL compatibility extraction as build/revision images.
- Avatar reads (signing) are open to any caller, including anonymous visitors — `avatars/*` has a public-read-equivalent SELECT policy (`"Anyone can read avatar files"`, `0002`) since avatars are inherently meant to be publicly visible (comments, profiles, follow lists). Avatar *writes* are strictly owner-scoped (`0017`'s two new policies, §6).

## 6. Signed URL flow

Every image read in the app funnels through one of two `mediaRepository.js` primitives:

- `getMediaSignedUrl(storagePath)` — single path → `createSignedUrl()`, 7-day expiry.
- `getMediaSignedUrls(storagePaths)` — deduplicated batch → one `createSignedUrls()` call, returns a `Map<path, url>` (or `""` for any path whose signing failed, e.g. a since-deleted object) so batch callers never throw on a partial failure.

**Why signing succeeds or fails is entirely `storage.objects` RLS**, independent of the bucket's public/private flag:
- An owner can sign any path under their own `projects/{draftId}/` or `avatars/{userId}/` prefix (owner policies from `0001`/`0017`).
- Anyone (including anonymous) can sign a path that is either under `avatars/*` (public-read avatar policy) or that a `revision_media` row links to a **public** build (`"Public can read revision media for public builds"`, `0014`).
- An owner can additionally sign a path their `revision_media` row links to regardless of that build's visibility (`"Owners can read their revision media"`, `0014`) — so a draft owner can preview their own unpublished/private revision images.
- A path with **no** `revision_media`/`project_media` row pointing to it, and not under `avatars/*`, satisfies no read policy for anyone — signing fails with "Object not found" even for the file's original uploader. This is the exact mechanism that makes orphaned objects permanently unreadable (§9) and is also why Migration C was necessary for the 7 legacy objects it backfilled.

7-day expiry balances two concerns (documented inline in `mediaRepository.js`): long enough that list pages (Explore, Workshop, Dashboard) aren't re-signing every render, short enough that a leaked signed URL doesn't stay valid indefinitely.

**Known, disclosed limitation** (from `0014`'s migration header, not fixed by any RLS change): a signed URL embeds a time-limited access bypass *at generation time* — RLS is evaluated once, when the URL is created, not on every subsequent fetch. If a build's visibility changes from public to private *after* a URL was already signed and handed out, that already-issued URL remains fetchable until it expires (up to 7 days). This is standard signed-URL behavior, not a bug, and is accepted as a documented tradeoff rather than solved (solving it would require abandoning signed URLs for a proxy-through-server model, which this app's architecture doesn't have).

## 7. Compatibility layer (Migration B)

`builds.image_url`, `build_revisions.image_url`, and `profiles.avatar_url` were written, pre-Milestone-5A, as full public object URLs rather than bare storage paths. Once the bucket went private (Migration A), those stored full-URL values stopped working outright — and per the approved migration scope, **no database row is ever rewritten** to fix this (read-path-only compatibility, by design, so the fix carries zero data-migration risk).

`extractStoragePath(value)` in `mediaRepository.js` is the single shared normalization function every image consumer routes through:

- If `value` isn't a full URL (`^https?://` doesn't match) → treat as an already-bare path, return unchanged.
- If it **is** a full URL and starts with this project's own `${SUPABASE_URL}/storage/v1/object/public/project-images/` prefix → strip that prefix, URL-decode the remainder, return the recovered bare path (now signable).
- If it's a full URL that does **not** match this project's own bucket shape (a genuinely external URL, or another Supabase project entirely) → return `null`, which every caller treats as "pass the original value through untouched" — this compatibility layer never touches a URL it doesn't recognize as its own.

Every read path — `resolveImageUrl`, `resolveBuildImageUrls`, `resolveAvatarUrl`, `resolveAvatarUrls` — calls `extractStoragePath()` before attempting to sign, so legacy full-URL values and modern bare paths are handled identically from the caller's perspective. This centralization was a hard requirement (Migration B requirement #4) specifically so no page ever reimplements its own URL parsing — confirmed via a repo-wide grep sweep that found and fixed one violation (`settings/app.js` had briefly duplicated the avatar_path/avatar_url branching inline; now calls `resolveAvatarUrl()` like every other consumer).

## 8. Category A vs. Category B (Migration C)

Migration C's backfill (`0018_legacy_media_linkage_backfill.sql`) restored `revision_media` linkage for legacy objects that predate that table, splitting candidates into two categories based on how strictly their ownership and linkage could be proven:

- **Category A — backfilled (7 objects)**: both **ownership** (the object belongs to a specific build) *and* **revision linkage** (a specific `build_revisions.image_url` value names this exact object) were independently provable from existing rows. These got real `revision_media` rows inserted, `is_cover: true`, `display_order: 0`.
- **Category B — reported, not backfilled (3 objects)**: ownership was provable (the *build's own* `image_url` names the object), but no `build_revisions` row corroborated it as belonging to a specific revision — including one build (`what-to-call`) with zero revisions at all to link to. Since `revision_media.revision_id` is `not null references build_revisions(id)`, and the approved scope explicitly forbade creating synthetic revisions or attaching these objects to an unrelated real revision (which would make that revision's `is_cover` claim false), these were left unbackfilled and documented as "Verified Legacy Covers" pending a future product decision (a real corroborating revision, a narrowly-scoped build-cover read policy, or indefinitely on the placeholder fallback).

This is the load-bearing distinction for the whole migration: **provable beats convenient**. A Category B object could technically have been force-linked to *some* existing revision to make it render, but that would assert something false in the data (that revision didn't actually have that cover) purely for cosmetic benefit — rejected by design.

## 9. Orphan handling

Two further classes of legacy object were identified during Migration C's audit and are **permanently untouched** by any migration, by design — no database row claims them, so no linkage is provable at all (not even at the Category B "ownership only" level):

- **18 root orphans** — objects sitting directly at the bucket root with no `builds`/`build_revisions`/`revision_media`/`project_media`/`profiles` row referencing them anywhere.
- **4 mystery-folder objects** — unclaimed files inside the legacy `{userId}/` folder, siblings of the Category A/B objects but matching nothing.

Both sets fall through `extractStoragePath()` → `getMediaSignedUrl()` → RLS denial ("Object not found") → the Migration B compatibility layer's fail-soft `.catch(() => "")` → an empty string → the app's existing placeholder-image fallback. **No code change is needed for orphans to degrade gracefully — this was true before Migration C and remains true after.** They are not a bug; they are storage-layer garbage with no database claim on them, and the correct behavior is exactly what already happens: render a placeholder, expose nothing.

Anonymous listing of these objects' containing folders is restricted by the same `storage.objects` RLS as everything else (Migration A) — an anonymous session cannot enumerate them to discover their existence, let alone read them. There is no plan to backfill, claim, or delete these objects as part of any tracked migration; a full listing was captured once, before Migration A restricted anonymous `list()`, and is preserved in `docs/milestones/MILESTONE_9_MIGRATION_C_DRY_RUN_REPORT.md` for reference. A small number of subfolders under the legacy `{userId}/` path (`revisions/`, `updates/`) were not fully enumerated before that restriction took effect — an explicitly disclosed visibility gap that affects only whether more *unclaimed* orphans might exist there, not anything this or any other migration depends on.

## 10. Migrations affecting storage

| Migration | Storage-relevant change |
|---|---|
| `0001_project_drafts_and_media.sql` | First `storage.objects` policies: owner-scoped SELECT/INSERT/UPDATE/DELETE on `projects/{draftId}/*`, keyed via `project_drafts.user_id`. |
| `0002_publish_draft_and_visibility.sql` | Introduces `revision_media` table; replaces the draft-media DELETE policy to exclude paths already linked into `revision_media` (so publishing protects the file from the draft-side delete path); adds `"Anyone can read avatar files"` (`avatars/*`, public SELECT) and `"Anyone can read files referenced by a published revision"` (later superseded by `0014`). |
| `0003_profile_avatar_path.sql` | Adds `profiles.avatar_path` (referenced throughout §5; not itself a `storage.objects` change). |
| `0014_storage_visibility_fix.sql` | Closes a real visibility leak: replaces the single `0002` revision-media read policy (which didn't check build visibility at all) with two — `"Public can read revision media for public builds"` and `"Owners can read their revision media"` — so an unpublished/private build's images stop being universally signable. |
| `0017_storage_rls_hardening.sql` (**Migration A**) | Drops 4 untracked, dashboard-default-template policies discovered live: an unconditional public SELECT, an unconditional authenticated INSERT, an **anonymous-role INSERT with `with_check = true`** (the most severe finding — let unauthenticated visitors upload anywhere), and a second unconditional public SELECT. Adds 2 owner-scoped avatar policies (`avatars/{userId}/*` INSERT/UPDATE) to legitimately cover what those broad policies had been accidentally providing. Bucket flipped from Public to Private as a separate, live-verified follow-up action (not part of the SQL file itself — a dashboard/Management-API setting). |
| `0018_legacy_media_linkage_backfill.sql` (**Migration C**) | Pure data backfill — inserts 7 `revision_media` rows for provably-linked legacy objects (§8). No RLS, policy, or bucket-config change. |

No migration has ever made the bucket public again after Migration A, added a broad/unscoped policy, or granted the `anon` role write access to any prefix.

---

**Summary of current guarantees**: the bucket is private; every read and write is mediated by path-scoped `storage.objects` RLS; every image consumer signs through the same two shared functions; legacy full-URL values and legacy pre-tracking objects are handled by a read-only compatibility/backfill layer that never rewrites data or weakens RLS; and any object with no database claim on it renders as a placeholder and stays unreadable and unlistable to everyone but a future migration that can prove real ownership.
