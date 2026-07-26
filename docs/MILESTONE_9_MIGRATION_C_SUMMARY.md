# Migration C — Legacy Media Linkage Backfill — Final Summary

**Migration file:** `supabase/migrations/0018_legacy_media_linkage_backfill.sql`
**Rollback file:** `supabase/migrations/0018_legacy_media_linkage_backfill_rollback.sql`
**Applied:** 2026-07-26, by the user, in the Supabase SQL Editor.
**Status:** Verified live. Complete.

See also: [`MILESTONE_9_MIGRATION_C_LEGACY_BACKFILL.md`](MILESTONE_9_MIGRATION_C_LEGACY_BACKFILL.md) (architecture proposal) and [`MILESTONE_9_MIGRATION_C_DRY_RUN_REPORT.md`](MILESTONE_9_MIGRATION_C_DRY_RUN_REPORT.md) (pre-apply dry run).

---

## Rows inserted

**7 rows** added to `public.revision_media`, one per legacy object whose ownership *and* revision linkage were both independently provable from an existing `build_revisions.image_url` value:

| Revision | Build | Storage path |
|---|---|---|
| `070cc44b-c7fe-4070-bf68-1cb4ce64f4af` (desk v0.3) | desk | `dacdf29e-.../revisions/1783540195367-Screenshot 2026-01-25 203600.png` |
| `31cdd3f9-fcd2-4509-8d58-f0ed361960f5` (desk v0.3) | desk | `dacdf29e-.../revisions/1783540440054-Screenshot 2026-01-25 203600.png` |
| `21f12b41-ae58-40e9-b9e6-59c85200369a` (desk v0.3) | desk | `dacdf29e-.../revisions/1783540456590-Screenshot 2026-01-25 203600.png` |
| `a0c03e2a-57cf-4ce8-9090-cff421a22626` (desk v0.3) | desk | `dacdf29e-.../revisions/1783540460231-Screenshot 2026-01-25 203600.png` |
| `f70b904c-84c7-42cc-af08-6729cf228d09` (desk v0.3) | desk | `dacdf29e-.../revisions/1783540741159-Screenshot 2026-01-25 203600.png` |
| `f59e6c5b-a71a-4828-9cd5-37f0d73067a5` (trap-open v0.1) | trap-open | `dacdf29e-.../1783986632675-screenshot-2026-06-15-124317.png` |
| `7f5be50a-f7b4-4f67-b34c-499bd3b5b822` (trap-open v0.4) | trap-open | `dacdf29e-.../updates/1784082807634-screenshot-2026-06-15-124311.png` |

All 7 inserted with `display_order = 0, is_cover = true` — each is its revision's only image, matching how `build_revisions.image_url` represented it pre-migration.

## Rows skipped, and why (intentional exceptions)

**3 objects — "Verified Legacy Covers"** — explicitly *not* backfilled, per the approved scope:

| Build | Storage path | Why skipped |
|---|---|---|
| `what-to-call` | `dacdf29e-.../1783986099945-screenshot-2026-06-15-124254.png` | Build has zero `build_revisions` rows — no revision exists to link to. |
| `build-soon` | `1783391492103-lockin.png` | Its one revision's own `image_url` is empty — doesn't corroborate this object as that revision's cover. |
| `desk` (build-level cover) | `builds/1783542244110-Screenshot 2026-01-27 220458.png` | Distinct object from all 5 of desk's own revisions (which *are* backfilled) — no revision's `image_url` matches this path. |

For all three, ownership is provable (the build's own `image_url` names the object) but revision linkage is not. `revision_media.revision_id` is `not null references build_revisions(id)`, and the approved scope explicitly forbade creating synthetic revisions or attaching these to an unrelated existing revision (that would make that revision's `is_cover` claim factually false). These remain on the Migration B compatibility layer's graceful placeholder fallback indefinitely, pending a separate future product decision.

**22 further orphan objects** (18 root, 4 in the legacy `dacdf29e-.../` folder) were identified, confirmed to be referenced by no database row at all, and left completely untouched — no ownership is provable for any of them, so no linkage was ever in scope.

**0 duplicates, 0 errors.** The migration's `NOT EXISTS` guard never fired — all 7 target revisions had zero `revision_media` rows before this migration ran.

## Live verification results (post-apply, this round)

All checks run against the live database via the anonymous/publishable key, matching the user's checklist:

- **Row count**: exactly 7 rows match the 7 target `(revision_id, storage_path)` pairs precisely; total `revision_media` count went from 9 → 16 (confirmed +7, not more).
- **No duplicates**: 0 `(revision_id, storage_path)` groups with `count(*) > 1` anywhere in the table.
- **Category B not inserted**: `desk`'s build-level cover, `what-to-call`'s cover, and `build-soon`'s cover all have 0 linked `revision_media` rows.
- **No unique-cover-per-revision violations.**
- **Orphans still unreadable**: signing attempts against 2 confirmed root orphans and 2 confirmed mystery-folder orphans all correctly returned `"Object not found"`.
- **Anonymous listing still restricted and precisely scoped**: root listing shows only `"projects"` and the legacy user-id folder (now legitimately non-empty post-backfill — expected, not a leak, since only folder *existence* is revealed). Listing `dacdf29e-.../revisions` shows exactly the 5 desk filenames now linked; listing `.../updates` shows exactly the 1 trap-open filename now linked — no extraneous objects exposed in either subfolder.
- **Anonymous upload still denied**: `"new row violates row-level security policy"`.
- **The four broad Storage policies remain absent** (`"Anyone can view project images"`, `"Authenticated users can upload project images"`, `"Enable insert for authenticated users only"`, `"Enable read access for all users"`) — reconfirmed behaviorally via the listing/upload/signing results above, consistent with Migration A's live `pg_policies` re-check.
- **All 7 newly-linked images resolve through signed URLs**: `createSignedUrl()` + `fetch()` against all 7 paths returned `200 image/png` for every one.
- **`desk` build page renders correctly**: hero cover correctly still shows the placeholder (its Category B object, intentionally excluded), and all 5 revision-history images now render as real signed images (200, image/png) instead of placeholders.
- **`trap-open` build page renders correctly**: cover image and both other revision images render as real signed images (200, image/png) — trap-open's cover *is* one of the 7 backfilled objects (its v0.1 initial revision), so its hero also now renders live.
- **`test-12345` (bare-path build) unchanged**: still exactly 9 `revision_media` rows across its 4 revisions, all identical to pre-migration, all rendering as signed 200s.
- **Rollback scope**: `0018_legacy_media_linkage_backfill_rollback.sql` deletes rows by the exact 7 `(revision_id, storage_path)` pairs above. Since the duplicate check confirms no other row in the table shares any of these pairs, the rollback is provably scoped to only these 7 rows — running it returns the affected images to the Migration B compatibility layer's placeholder fallback, nothing else.

## Remaining placeholders

The following remain on the graceful placeholder fallback (no change from Migration B), and are unaffected by this migration:

- **3 Verified Legacy Covers** (`what-to-call`, `build-soon`, `desk`'s build-level cover) — see above.
- **18 root orphans** and **4 confirmed mystery-folder orphans** — referenced by no database row; not eligible for any linkage-based fix.
- Any additional objects that may exist, unenumerated, within the `dacdf29e-.../revisions/` or `.../updates/` subfolders beyond what this migration already linked — anonymous listing was correctly restricted by Migration A before a full enumeration of those two subfolders was completed, so their full contents were never confirmed. This is a known, explicitly-flagged gap in visibility only — it does not affect anything this migration touched, and nothing currently depends on it.

---

Migration C is complete and fully verified live. Stopping here, per instruction — not beginning Migration D.
