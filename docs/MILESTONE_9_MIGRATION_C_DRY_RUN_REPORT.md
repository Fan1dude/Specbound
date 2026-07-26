# Migration C — Dry-Run Report

Generated immediately before applying `0018_legacy_media_linkage_backfill.sql`. All `revision_media`/`builds`/`build_revisions` figures below are live, re-queried fresh at report time. All "unclaimed object" figures for the bucket's root and the legacy user-id folder are carried over from the one-time full listing captured during Migration A's audit (before anonymous listing was restricted) — anonymous listing is now correctly denied for anything outside a caller's own authorized scope, so those two categories can no longer be re-enumerated live, which is itself expected and correct, not a gap.

---

## Eligible (Category A — will be inserted)

| Revision | Build | Storage path |
|---|---|---|
| `070cc44b-c7fe-4070-bf68-1cb4ce64f4af` (desk v0.3) | desk | `dacdf29e-.../revisions/1783540195367-Screenshot 2026-01-25 203600.png` |
| `31cdd3f9-fcd2-4509-8d58-f0ed361960f5` (desk v0.3) | desk | `dacdf29e-.../revisions/1783540440054-Screenshot 2026-01-25 203600.png` |
| `21f12b41-ae58-40e9-b9e6-59c85200369a` (desk v0.3) | desk | `dacdf29e-.../revisions/1783540456590-Screenshot 2026-01-25 203600.png` |
| `a0c03e2a-57cf-4ce8-9090-cff421a22626` (desk v0.3) | desk | `dacdf29e-.../revisions/1783540460231-Screenshot 2026-01-25 203600.png` |
| `f70b904c-84c7-42cc-af08-6729cf228d09` (desk v0.3) | desk | `dacdf29e-.../revisions/1783540741159-Screenshot 2026-01-25 203600.png` |
| `f59e6c5b-a71a-4828-9cd5-37f0d73067a5` (trap-open v0.1) | trap-open | `dacdf29e-.../1783986632675-screenshot-2026-06-15-124317.png` |
| `7f5be50a-f7b4-4f67-b34c-499bd3b5b822` (trap-open v0.4) | trap-open | `dacdf29e-.../updates/1784082807634-screenshot-2026-06-15-124311.png` |

**Count: 7.** Ownership and revision linkage both directly proven by the owning `build_revisions.image_url` value.

## Already linked (would be skipped as duplicates)

Live query against all 7 target `(revision_id, storage_path)` pairs: **0 rows found.** None of these 7 revisions currently has any `revision_media` row (the 9 rows that exist today all belong to `test-12345`'s 4 revisions). No duplicates possible; the migration's `NOT EXISTS` guard is a no-op safety net today, not something actively firing.

## Verified Legacy Covers (Category B — intentionally not backfilled)

| Build | Storage path | Reason skipped | Recommended future handling |
|---|---|---|---|
| `what-to-call` | `dacdf29e-.../1783986099945-screenshot-2026-06-15-124254.png` | Build has **zero** `build_revisions` rows at all — no revision exists to link to. | Requires a product decision: either a new, real `build_revisions` row that legitimately represents this legacy cover (making linkage genuinely provable), or a narrowly-scoped `builds.image_url`-matching RLS policy, or leave on the Migration B placeholder fallback indefinitely. Not resolvable by a pure `revision_media` insert under the current schema (`revision_id` is `not null`). |
| `build-soon` | `1783391492103-lockin.png` | Its one existing revision's own `image_url` is empty — doesn't corroborate this object as that revision's cover. | Same three options as above. |
| `desk` (build-level cover only) | `builds/1783542244110-Screenshot 2026-01-27 220458.png` | Distinct object from all 5 of `desk`'s own revisions (which *are* backfilled above) — no revision's `image_url` matches this specific path. | Same three options as above. |

**Count: 3.** For all three: ownership is provable (the build's own `image_url` column names the object), but revision linkage is not — no `build_revisions` row corroborates it. Per the approved scope, these are reported, not synthesized or attached to an unrelated revision.

## Root orphans

18 objects sitting directly at the bucket root, referenced by **no** `builds`, `build_revisions`, `revision_media`, `project_media`, or `profiles` row — captured during Migration A's pre-fix audit (the one point anonymous listing had full bucket visibility):

`1783307501387-Screenshot 2026-01-05 152506.png`, `1783309567151-Screenshot 2026-06-15 124254.png`, `1783309720230-Screenshot 2026-06-15 124254.png`, `1783309867890-Screenshot 2026-01-05 152506.png`, `1783309993864-Screenshot 2026-01-27 232936.png`, `1783310046865-Screenshot 2026-01-05 152506.png`, `1783310136553-Screenshot 2026-01-27 232936.png`, `1783310528567-Screenshot 2026-01-05 152506.png`, `1783310553087-Screenshot 2026-01-27 232936.png`, `1783310616434-Screenshot 2026-01-16 234207.png`, `1783355064960-Screenshot 2025-12-26 201553.png`, `1783355673941-Screenshot 2025-02-15 153846.png`, `1783370217163-Screenshot 2026-03-01 114414.png`, `1783385356455-My Pc..jpg`, `1783385965340-My Pc..jpg`, `1783387665740-MOLE.png`, `1783388712589-cxherry.jpg`, `1783389106453-IMG_0452 (1).HEIC`

(The original 19th root file, `1783391492103-lockin.png`, is **not** an orphan — it's `build-soon`'s Verified Legacy Cover, listed above.)

**Count: 18. Not touched by this migration. Never will be by any pure `revision_media` linkage — nothing in the database claims them.**

## Mystery-folder objects

The legacy `dacdf29e-.../` folder (a pre-`avatars/`-convention, user-id-keyed layout) had 6 files at its top level per the pre-fix audit; 2 are claimed (1 Eligible — trap-open's initial revision, 1 Verified Legacy Cover — what-to-call's build cover). The remaining 4 are unclaimed:

`1783985515126-screenshot-2026-06-15-124254.png`, `1783985524390-screenshot-2026-06-15-124254.png`, `1783985529372-screenshot-2026-06-15-124254.png`, `1783985536906-screenshot-2026-06-15-124254.png`

**Count: 4 confirmed unclaimed. Not touched by this migration.**

**Honest gap, noted rather than papered over**: the `dacdf29e-.../revisions/` and `dacdf29e-.../updates/` subfolders were never fully enumerated before anonymous listing was correctly restricted by Migration A — only the specific files within them that a `build_revisions` row references are known (the 6 Eligible/Verified-Cover paths above that live under those two subfolders). There may be additional unclaimed objects in those subfolders that are now permanently unlistable to an anonymous session — which is the intended, correct outcome of Migration A, not a shortcoming of this report. Nothing in this migration depends on that being fully known; it only affects objects this migration was never going to touch anyway.

## Duplicate rows (existing data integrity check)

```sql
select revision_id, storage_path, count(*) from public.revision_media
group by revision_id, storage_path having count(*) > 1;
```
**0 rows.** No pre-existing duplicate `(revision_id, storage_path)` pairs anywhere in the current table, unrelated to this migration's own scope but checked for completeness.

## Errors

None. All 5 builds, 12 revisions, and 9 existing `revision_media` rows were read successfully; all 7 target revision IDs were confirmed to exist in `build_revisions` (the dry-run join in the architecture proposal returns exactly 7 rows, all `visibility='public'`, matching §1-2 of the approved proposal).

---

**Summary: 7 eligible, 0 already-linked, 3 Verified Legacy Covers (reported, not inserted), 18 root orphans (untouched), 4 mystery-folder orphans (untouched), 0 duplicates, 0 errors.**

Proceeding to apply `0018_legacy_media_linkage_backfill.sql`.
