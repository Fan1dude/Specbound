# Migration C — Legacy Media Linkage Backfill: Architecture Proposal

**Status:** Architecture only. Nothing applied. No migration file created yet. Stopping after this proposal, as instructed.

**Goal:** restore authorized (RLS-covered) access to legacy storage objects that genuinely belong to existing public builds/revisions, by inserting `revision_media` rows only where both **ownership** and **revision linkage** are independently provable from existing database records — never from filename similarity or folder location.

---

## 1–2. Identification + path extraction (done against live data)

Queried every build, every `build_revisions` row, and every existing `revision_media` row directly. All 4 legacy builds and their revisions are now fully enumerated — this is a small, closed, already-fully-characterized dataset (12 revisions total across 5 builds), not an open-ended pattern to run generically.

Paths were extracted using the **exact same logic as the shared compatibility helper** (`extractStoragePath()` in `js/repositories/mediaRepository.js`, added in Migration B) — I ran the real values through that real function during Migration B's own verification, so every path below is independently confirmed correct (decoded, prefix-stripped) rather than re-derived by hand for this proposal.

| Build | Revision | image_url shape | Extracted path |
|---|---|---|---|
| `desk` (014abbca…) | 070cc44b… (v0.3) | legacy URL | `dacdf29e-.../revisions/1783540195367-Screenshot 2026-01-25 203600.png` |
| `desk` | 31cdd3f9… (v0.3) | legacy URL | `dacdf29e-.../revisions/1783540440054-Screenshot 2026-01-25 203600.png` |
| `desk` | 21f12b41… (v0.3) | legacy URL | `dacdf29e-.../revisions/1783540456590-Screenshot 2026-01-25 203600.png` |
| `desk` | a0c03e2a… (v0.3) | legacy URL | `dacdf29e-.../revisions/1783540460231-Screenshot 2026-01-25 203600.png` |
| `desk` | f70b904c… (v0.3) | legacy URL | `dacdf29e-.../revisions/1783540741159-Screenshot 2026-01-25 203600.png` |
| `trap-open` (18677326…) | f59e6c5b… (v0.1, initial) | legacy URL | `dacdf29e-.../1783986632675-screenshot-2026-06-15-124317.png` |
| `trap-open` | 7f5be50a… (v0.4, hardware) | legacy URL | `dacdf29e-.../updates/1784082807634-screenshot-2026-06-15-124311.png` |

(`dacdf29e-...` = `dacdf29e-ea56-4a85-a6a3-6a60cb7c1210`, truncated for table width.)

---

## 3. Authoritative relationship per object — and where it breaks down

For every one of the 12 legacy-shaped values (5 builds' own `image_url` + 8 revisions' `image_url` — note `build-soon`'s single revision has an *empty* `image_url`, so it contributes 0), I checked whether the build-level cover matches any of that build's own revisions' covers:

| Build | Owner (`user_id`) | Visibility | Revisions | Build cover matches a revision's cover? |
|---|---|---|---|---|
| `what-to-call` | dacdf29e… | public | **0 revisions exist at all** | N/A — nothing to match against |
| `build-soon` ("cool cool") | 52daee09… | public | 1 revision, `image_url = ""` | No — that revision has no image |
| `desk` ("Test build") | dacdf29e… | public | 5 revisions, each with its **own distinct** image | No — the build's cover is a *different* object from all 5 |
| `trap-open` | dacdf29e… | public | 2 revisions | **Yes** — exactly matches the latest (v0.4) revision |

This splits cleanly into two categories, and they need different treatment:

### Category A — revision linkage is provable (safe to backfill now)

The 7 rows in the table above. Each `build_revisions.image_url` value **is itself the database's own record of that exact revision owning that exact object** — no inference needed, no filename matching, just reading a column that already makes this claim. `is_cover = true` is correct for all 7 (each revision has exactly one image today, so it genuinely is that revision's cover; the schema's `revision_media_one_cover_per_revision_idx` unique index confirms none of these revisions currently has any cover, so no conflict).

### Category B — revision linkage is NOT provable (cannot be backfilled via `revision_media` in this migration)

- `what-to-call`'s build-level cover (0 revisions exist to attach it to)
- `build-soon`'s build-level cover (its one revision's own `image_url` is empty — doesn't match)
- `desk`'s build-level cover *specifically* (distinct from its 5 revisions, which are Category A) — the build's own denormalized cover has no revision of its own

`revision_media.revision_id` is `not null references build_revisions(id)` — there is no way to insert a row here without a real revision to point at. **Build ownership is provable for all three** (the build's own `image_url` column, plus `builds.user_id`/`visibility`, are exactly the kind of existing-database-record proof this migration is supposed to require) — but requirement #4 asks for ownership **and revision linkage**, and only ownership is provable here. Per that stricter reading, I'm not proposing to attach these to an unrelated existing revision just to give them *a* home — that would be linking on convenience, not proof, and revision_media's own schema semantics (`is_cover` = "this revision's cover") would become factually wrong for a row that isn't really that revision's image.

**Three honest options for Category B, none implemented here:**

1. **Leave as-is (recommended default for this migration).** The Migration B compatibility layer already makes these fail *gracefully* (placeholder, not a broken image) rather than erroring. Zero new risk, zero new policy surface. These 3 objects stay exactly as unreachable as they are today until a separate, explicit decision is made.
2. **A new, narrowly-scoped RLS policy** matching `storage.objects.name = builds.image_url` (visibility/ownership-gated, same rigor as the existing revision_media policies — not a wildcard/prefix policy). This would resolve it, but you explicitly asked this migration not to add any new storage read policy, so I'm naming it only as a future option, not proposing it now.
3. **A new, real `build_revisions` row** (e.g., an explicit "legacy cover" entry) whose own `image_url` **is** the object — this would satisfy requirement #4's strict reading by making the revision linkage genuinely true instead of approximated, but it changes these builds' visible revision history/timeline, which is a bigger, more visible change than a pure backfill and deserves its own explicit sign-off.

I'd recommend (1) for now and revisiting (2) vs (3) as its own small follow-up once you've seen this proposal, rather than me picking one unilaterally.

---

## 4. Duplicate preflight

None of the 7 Category A revisions currently have **any** `revision_media` row (confirmed directly — I queried every existing `revision_media` row live; all 9 that exist today belong entirely to `test-12345`'s 4 revisions, none to `desk` or `trap-open`). So there is no actual duplicate risk today. The apply SQL still guards against re-running safely (idempotent `WHERE NOT EXISTS`), in case this migration is ever applied twice or partially retried.

```sql
-- Preflight: would any of the 7 target rows already exist?
select rm.id, rm.revision_id, rm.storage_path
from public.revision_media rm
where (rm.revision_id, rm.storage_path) in (
    ('070cc44b-c7fe-4070-bf68-1cb4ce64f4af', 'dacdf29e-ea56-4a85-a6a3-6a60cb7c1210/revisions/1783540195367-Screenshot 2026-01-25 203600.png'),
    ('31cdd3f9-fcd2-4509-8d58-f0ed361960f5', 'dacdf29e-ea56-4a85-a6a3-6a60cb7c1210/revisions/1783540440054-Screenshot 2026-01-25 203600.png'),
    ('21f12b41-ae58-40e9-b9e6-59c85200369a', 'dacdf29e-ea56-4a85-a6a3-6a60cb7c1210/revisions/1783540456590-Screenshot 2026-01-25 203600.png'),
    ('a0c03e2a-57cf-4ce8-9090-cff421a22626', 'dacdf29e-ea56-4a85-a6a3-6a60cb7c1210/revisions/1783540460231-Screenshot 2026-01-25 203600.png'),
    ('f70b904c-84c7-42cc-af08-6729cf228d09', 'dacdf29e-ea56-4a85-a6a3-6a60cb7c1210/revisions/1783540741159-Screenshot 2026-01-25 203600.png'),
    ('f59e6c5b-a71a-4828-9cd5-37f0d73067a5', 'dacdf29e-ea56-4a85-a6a3-6a60cb7c1210/1783986632675-screenshot-2026-06-15-124317.png'),
    ('7f5be50a-f7b4-4f67-b34c-499bd3b5b822', 'dacdf29e-ea56-4a85-a6a3-6a60cb7c1210/updates/1784082807634-screenshot-2026-06-15-124311.png')
);
-- Expected: 0 rows.
```

Also confirms the unique-cover-per-revision index won't be violated (`is_cover=true` on a revision that already has a cover would fail loudly at INSERT time regardless — a second, structural safety net beyond this query).

---

## 6a. Orphan detection — what this migration deliberately does NOT touch

The mystery folder (`dacdf29e-.../`) contains 6 files total; only 3 of them (the two listed for `trap-open` plus the one for `what-to-call`) are referenced by any `builds`/`build_revisions` row. The other 3, and every one of the ~19 loose root-level files, are referenced by **nothing** in the database — no build, no revision, no profile.

```sql
-- Every object under this bucket that no build/revision/profile column
-- currently claims — i.e. everything this migration will NOT create
-- access for, listed explicitly so it's visible rather than silently
-- skipped. (storage.objects is a real, queryable Postgres table.)
select o.name, o.created_at, o.metadata->>'size' as size_bytes
from storage.objects o
where o.bucket_id = 'project-images'
  and not exists (
      select 1 from public.builds b
      where b.image_url = o.name
         or b.image_url like '%/object/public/project-images/' || o.name
  )
  and not exists (
      select 1 from public.build_revisions br
      where br.image_url = o.name
         or br.image_url like '%/object/public/project-images/' || o.name
  )
  and not exists (
      select 1 from public.revision_media rm where rm.storage_path = o.name
  )
  and not exists (
      select 1 from public.project_media pm where pm.storage_path = o.name
  )
  and not exists (
      select 1 from public.profiles p
      where p.avatar_path = o.name
         or p.avatar_url = o.name
         or p.avatar_url like '%/object/public/project-images/' || o.name
  )
order by o.created_at;
```

This is expected to return the ~19 root-level files plus the 3 unclaimed mystery-folder files — none of them get touched by this migration, and none of them should ever be resolvable through `revision_media`, `avatars/*`, or any owner-scoped `projects/*` policy, since literally nothing in the database claims them. If a future cleanup ever wants to delete truly-orphaned storage objects, this exact query is the starting point — but deletion is explicitly out of scope here too.

---

## 6b. Ambiguous-record report

Only the 3 Category B objects qualify as "ambiguous" in the sense of "a build record points at this, but a revision record doesn't corroborate it":

```sql
select b.slug, b.title, b.image_url as build_cover_url, b.visibility, b.user_id,
       (select count(*) from public.build_revisions br where br.build_id = b.id) as revision_count,
       exists (
           select 1 from public.build_revisions br
           where br.build_id = b.id and br.image_url = b.image_url
       ) as a_revision_matches_the_build_cover
from public.builds b
where b.image_url like 'https://%/object/public/project-images/%'
  and not exists (
      select 1 from public.build_revisions br
      where br.build_id = b.id and br.image_url = b.image_url
  );
-- Expected: what-to-call, build-soon, desk (3 rows) — see §3 Category B.
```

No object anywhere in this migration is resolved by filename similarity — every Category A row is matched by an *exact* value stored in an existing column, and everything in Category B is reported, not force-linked.

---

## 5 / Dry-run SQL

```sql
-- Dry run: exactly what would be inserted, with the owning build/user
-- and visibility shown alongside each row for final human review before
-- the real INSERT runs.
select
    br.id as revision_id,
    b.slug,
    b.user_id as owning_user,
    b.visibility,
    v.storage_path,
    true as is_cover
from public.build_revisions br
join public.builds b on b.id = br.build_id
join (values
    ('070cc44b-c7fe-4070-bf68-1cb4ce64f4af'::uuid, 'dacdf29e-ea56-4a85-a6a3-6a60cb7c1210/revisions/1783540195367-Screenshot 2026-01-25 203600.png'),
    ('31cdd3f9-fcd2-4509-8d58-f0ed361960f5'::uuid, 'dacdf29e-ea56-4a85-a6a3-6a60cb7c1210/revisions/1783540440054-Screenshot 2026-01-25 203600.png'),
    ('21f12b41-ae58-40e9-b9e6-59c85200369a'::uuid, 'dacdf29e-ea56-4a85-a6a3-6a60cb7c1210/revisions/1783540456590-Screenshot 2026-01-25 203600.png'),
    ('a0c03e2a-57cf-4ce8-9090-cff421a22626'::uuid, 'dacdf29e-ea56-4a85-a6a3-6a60cb7c1210/revisions/1783540460231-Screenshot 2026-01-25 203600.png'),
    ('f70b904c-84c7-42cc-af08-6729cf228d09'::uuid, 'dacdf29e-ea56-4a85-a6a3-6a60cb7c1210/revisions/1783540741159-Screenshot 2026-01-25 203600.png'),
    ('f59e6c5b-a71a-4828-9cd5-37f0d73067a5'::uuid, 'dacdf29e-ea56-4a85-a6a3-6a60cb7c1210/1783986632675-screenshot-2026-06-15-124317.png'),
    ('7f5be50a-f7b4-4f67-b34c-499bd3b5b822'::uuid, 'dacdf29e-ea56-4a85-a6a3-6a60cb7c1210/updates/1784082807634-screenshot-2026-06-15-124311.png')
) as v(revision_id, storage_path) on v.revision_id = br.id;
-- Expected: 7 rows, all visibility='public', owning_user matching the
-- table in §1-2, br.id present in build_revisions (confirms the FK will
-- succeed before actually inserting).
```

## Apply SQL

```sql
-- Migration: 0018_legacy_media_linkage_backfill (Migration C)
-- Only touches revision_media (7 new rows). Never touches image_url on
-- builds/build_revisions, never touches storage.objects, never touches
-- RLS policies, never touches the bucket's public/private flag.
begin;

insert into public.revision_media (revision_id, storage_path, display_order, is_cover)
select v.revision_id, v.storage_path, 0, true
from (values
    ('070cc44b-c7fe-4070-bf68-1cb4ce64f4af'::uuid, 'dacdf29e-ea56-4a85-a6a3-6a60cb7c1210/revisions/1783540195367-Screenshot 2026-01-25 203600.png'),
    ('31cdd3f9-fcd2-4509-8d58-f0ed361960f5'::uuid, 'dacdf29e-ea56-4a85-a6a3-6a60cb7c1210/revisions/1783540440054-Screenshot 2026-01-25 203600.png'),
    ('21f12b41-ae58-40e9-b9e6-59c85200369a'::uuid, 'dacdf29e-ea56-4a85-a6a3-6a60cb7c1210/revisions/1783540456590-Screenshot 2026-01-25 203600.png'),
    ('a0c03e2a-57cf-4ce8-9090-cff421a22626'::uuid, 'dacdf29e-ea56-4a85-a6a3-6a60cb7c1210/revisions/1783540460231-Screenshot 2026-01-25 203600.png'),
    ('f70b904c-84c7-42cc-af08-6729cf228d09'::uuid, 'dacdf29e-ea56-4a85-a6a3-6a60cb7c1210/revisions/1783540741159-Screenshot 2026-01-25 203600.png'),
    ('f59e6c5b-a71a-4828-9cd5-37f0d73067a5'::uuid, 'dacdf29e-ea56-4a85-a6a3-6a60cb7c1210/1783986632675-screenshot-2026-06-15-124317.png'),
    ('7f5be50a-f7b4-4f67-b34c-499bd3b5b822'::uuid, 'dacdf29e-ea56-4a85-a6a3-6a60cb7c1210/updates/1784082807634-screenshot-2026-06-15-124311.png')
) as v(revision_id, storage_path)
where not exists (
    select 1 from public.revision_media rm
    where rm.revision_id = v.revision_id and rm.storage_path = v.storage_path
);

commit;
```

## Rollback SQL

```sql
-- Rollback for 0018_legacy_media_linkage_backfill
-- Deletes exactly the 7 rows this migration adds, identified by their
-- precise (revision_id, storage_path) pairs — not a broader "delete
-- anything that looks like a backfill" match, so it can't accidentally
-- remove a legitimate row added by something else later.
begin;

delete from public.revision_media
where (revision_id, storage_path) in (
    ('070cc44b-c7fe-4070-bf68-1cb4ce64f4af', 'dacdf29e-ea56-4a85-a6a3-6a60cb7c1210/revisions/1783540195367-Screenshot 2026-01-25 203600.png'),
    ('31cdd3f9-fcd2-4509-8d58-f0ed361960f5', 'dacdf29e-ea56-4a85-a6a3-6a60cb7c1210/revisions/1783540440054-Screenshot 2026-01-25 203600.png'),
    ('21f12b41-ae58-40e9-b9e6-59c85200369a', 'dacdf29e-ea56-4a85-a6a3-6a60cb7c1210/revisions/1783540456590-Screenshot 2026-01-25 203600.png'),
    ('a0c03e2a-57cf-4ce8-9090-cff421a22626', 'dacdf29e-ea56-4a85-a6a3-6a60cb7c1210/revisions/1783540460231-Screenshot 2026-01-25 203600.png'),
    ('f70b904c-84c7-42cc-af08-6729cf228d09', 'dacdf29e-ea56-4a85-a6a3-6a60cb7c1210/revisions/1783540741159-Screenshot 2026-01-25 203600.png'),
    ('f59e6c5b-a71a-4828-9cd5-37f0d73067a5', 'dacdf29e-ea56-4a85-a6a3-6a60cb7c1210/1783986632675-screenshot-2026-06-15-124317.png'),
    ('7f5be50a-f7b4-4f67-b34c-499bd3b5b822', 'dacdf29e-ea56-4a85-a6a3-6a60cb7c1210/updates/1784082807634-screenshot-2026-06-15-124311.png')
);

commit;
```

## Row counts before/after

```sql
select revision_id, count(*) from public.revision_media
where revision_id in (
    '070cc44b-c7fe-4070-bf68-1cb4ce64f4af','31cdd3f9-fcd2-4509-8d58-f0ed361960f5',
    '21f12b41-ae58-40e9-b9e6-59c85200369a','a0c03e2a-57cf-4ce8-9090-cff421a22626',
    'f70b904c-84c7-42cc-af08-6729cf228d09','f59e6c5b-a71a-4828-9cd5-37f0d73067a5',
    '7f5be50a-f7b4-4f67-b34c-499bd3b5b822'
)
group by revision_id;
-- Before: 0 rows returned (none of these revision_ids appear at all).
-- After:  7 rows, each with count = 1.

select count(*) from public.revision_media; -- before: 9, after: 16.
```

---

## 8. Post-backfill verification plan

1. **The four affected legacy builds render their authorized images** — re-run the same live regression methodology from Migration B's verification (fetch each `<img>` src with cache-busting, confirm `signed-real-image` classification and 200) against `desk` and `trap-open`'s pages specifically, since those are the ones with real Category A rows now. (`what-to-call` and `build-soon`'s *build-level* covers remain placeholder-fallback per §3 — expected, not a regression.)
2. **Anonymous users still cannot sign unrelated legacy objects** — re-run the exact orphan-detection query's result set (the ~19 root files + 3 unclaimed mystery-folder files) through `createSignedUrl()` anonymously; every one must still fail with `"Object not found"`, unchanged from Migration A's verification.
3. **Root and arbitrary-folder listing remain restricted** — re-run the anonymous `list("")`, `list("projects")`, `list("dacdf29e-...")` checks from Migration A's verification; results must be identical (only the one public build's linked folder visible), since this migration adds zero storage policies.
4. **No duplicate `revision_media` rows** — the row-count queries above, plus re-confirming the unique-cover-per-revision index wasn't violated (`select revision_id, count(*) from revision_media where is_cover group by revision_id having count(*) > 1` → expect 0 rows).
5. **Current bare-path builds (`test-12345`) are unchanged** — same regression check as Migration B, confirming its 4 existing `revision_media` rows and rendering are untouched (this migration never writes to any row belonging to `test-12345`).

---

## Should `image_url` be normalized now or later?

**Recommend: leave `builds.image_url`/`build_revisions.image_url` untouched, for now, as a deliberate choice — not an oversight.**

- The Migration B compatibility layer already makes the *current* legacy-URL values fully functional at read time (once Category A's linkage exists, signing succeeds directly from the stored legacy URL — no dependency on the column shape being bare vs. full-URL).
- Normalizing these columns to bare paths would be a pure tidiness change with no functional benefit today, and it's exactly the kind of database rewrite you've asked to defer at every stage of this work (Migration B explicitly avoided it; this migration is scoped to `revision_media` inserts only).
- It does become worth doing eventually, for two real reasons: (a) it lets the `FULL_URL_PATTERN`/`extractStoragePath` compatibility branch in `mediaRepository.js` eventually be deleted once nothing in the database needs it anymore — permanent code for a temporary data shape is exactly the kind of thing worth cleaning up once, not maintaining forever; (b) it removes the last trace of the pre-5A architecture from the live data, which is a reasonable "done" signal for this whole legacy-URL saga.
- Recommend treating it as its own small, low-risk, explicitly-scoped **Migration D** later — a straightforward `UPDATE ... SET image_url = <extracted path>` for exactly these known rows, proposed and reviewed the same way this one was, once Category A is confirmed working in production and there's no rush. Not needed to consider this milestone "done."

---

Stopping here for review, as instructed. Nothing has been applied — no migration file created, no SQL run, no code changed.
