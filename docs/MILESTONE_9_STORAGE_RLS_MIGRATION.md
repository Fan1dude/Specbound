# Storage RLS Hardening — Migration Proposal (pre-implementation)

**Status:** Proposal only. Nothing in this document has been applied. No migration file has been created under `supabase/migrations/`. No application code has changed. Stopping for review per instructions.

**Input:** the live `pg_policies` dump for `storage.objects`, provided directly.

---

## 1. Every current policy, classified

11 policies exist today. 7 come from tracked migrations and are correctly scoped. 4 do not appear in any tracked migration and are dangerously broad.

| Policy | Roles | Cmd | Scope | Verdict |
|---|---|---|---|---|
| "Anyone can read avatar files" | public | SELECT | `bucket_id='project-images' AND foldername[1]='avatars'` | **Correct — keep.** Matches `0002`. Intended: avatars are public by design. |
| **"Anyone can view project images"** | public | SELECT | `bucket_id='project-images'` — **no further scoping at all** | **DROP.** Grants read on every object in the bucket to everyone, unconditionally. Not in any tracked migration. |
| **"Authenticated users can upload project images"** | authenticated | INSERT | `bucket_id='project-images'` — **no path/ownership scoping** | **DROP.** Any authenticated user can write to any path, including another user's avatar or draft folder. Not in any tracked migration. |
| **"Enable insert for authenticated users only"** | **anon** | INSERT | `with_check = true` — **no scoping, and the role is `anon`, not `authenticated`, despite the name** | **DROP — the single most dangerous policy found.** Unauthenticated visitors can currently upload arbitrary files to arbitrary paths in the bucket. This is a Supabase default-template artifact (the name is the dashboard's stock "Enable insert for authenticated users only" template, evidently applied to the wrong role at some point pre-tracking). Not in any tracked migration. |
| **"Enable read access for all users"** | public | SELECT | `qual = true` — **no `bucket_id` check, applies bucket-wide across all buckets** | **DROP.** Same default-template pattern as above; broader even than "Anyone can view project images" since it isn't even bucket-scoped. Not in any tracked migration. |
| "Owners can delete their draft media files" | public | DELETE | project_drafts ownership, `projects/*`, excludes rows referenced by `revision_media` | Correct — keep. Matches `0002`. |
| "Owners can insert their draft media files" | public | INSERT | project_drafts ownership, `projects/*` | Correct — keep. Matches `0001`. |
| "Owners can read their revision media" | public | SELECT | build ownership via `revision_media`→`build_revisions`→`builds` join | Correct — keep. Matches `0014`. |
| "Owners can select their draft media files" | public | SELECT | project_drafts ownership, `projects/*` | Correct — keep. Matches `0001`. |
| "Owners can update their draft media files" | public | UPDATE | project_drafts ownership, `projects/*` | Correct — keep. Matches `0001`. |
| "Public can read revision media for public builds" | public | SELECT | `builds.visibility='public'` via the same join | Correct — keep. Matches `0014`. |

**This fully explains everything observed empirically**: the two broad SELECT policies are why anonymous `list()` returned the entire bucket and why `createSignedUrl()` succeeded for arbitrary paths; the anon-role INSERT policy is why (untested, but implied) anonymous uploads would currently succeed too.

---

## 2. The gap the broad policies were accidentally covering

Cross-referencing every Storage write call in the app (`imageService.js`, `mediaRepository.js`) against the 7 correct policies: **avatar upload/update has no scoped policy at all.**

- `uploadAvatar()` writes to `avatars/{userId}/{size}.jpg` with `upsert: true` (needs INSERT + UPDATE).
- The only tracked write policies are scoped to `projects/*` (gallery/draft images) — nothing covers `avatars/*` writes.
- Avatar upload has only ever "worked" because of the two broad INSERT policies being dropped above. **Removing them without adding a replacement breaks avatar upload/re-upload.**

Gallery/draft image writes (`uploadGalleryImage`, `deleteGalleryImage`, `mediaRepository.deleteMedia`) are already fully covered by the 5 correct `projects/*`-scoped policies — no gap there.

---

## 3. Proposed final policy set

**Drop (exact names, matches live `pg_policies` output):**
```sql
drop policy "Anyone can view project images" on storage.objects;
drop policy "Authenticated users can upload project images" on storage.objects;
drop policy "Enable insert for authenticated users only" on storage.objects;
drop policy "Enable read access for all users" on storage.objects;
```

**Add (the one confirmed gap — avatar writes, owner-scoped to match the app's actual upload path shape):**
```sql
create policy "Owners can upload their own avatar files" on storage.objects
    for insert
    with check (
        bucket_id = 'project-images'
        and (storage.foldername(name))[1] = 'avatars'
        and (storage.foldername(name))[2] = auth.uid()::text
    );

create policy "Owners can update their own avatar files" on storage.objects
    for update
    using (
        bucket_id = 'project-images'
        and (storage.foldername(name))[1] = 'avatars'
        and (storage.foldername(name))[2] = auth.uid()::text
    );
```

**Keep, unchanged:** all 7 correctly-scoped policies listed in §1.

**Net result** — every legitimate operation retains coverage:

| Operation | Covered by |
|---|---|
| Owner reads their own draft's gallery images | "Owners can select their draft media files" (unchanged) |
| Owner uploads/updates their own draft's gallery images | "Owners can insert/update their draft media files" (unchanged) |
| Owner deletes their own draft's gallery images | "Owners can delete their draft media files" (unchanged) |
| Public reads a public build's revision media | "Public can read revision media for public builds" (unchanged) |
| Owner reads their own build's revision media (public or not) | "Owners can read their revision media" (unchanged) |
| Anyone reads any avatar | "Anyone can read avatar files" (unchanged) |
| Owner uploads/re-uploads their own avatar | **new** "Owners can upload/update their own avatar files" |

And every path from §1's dangerous-policy list stops working: anonymous bucket listing, anonymous cross-user signing, anonymous uploads.

---

## 4. The known, deliberate gap this creates — legacy media not in `revision_media`

Both remaining SELECT policies for build/revision images require the storage path to exist as a **row in `revision_media`**, joined up to the owning build. Every publish since the current architecture shipped populates that table correctly. But the empirical data pull earlier found:

- **4 of 5 builds'** `image_url` and **8 of 12 `build_revisions.image_url`** values are legacy full public URLs, from before `revision_media` existed as a table at all — they were never captured into it.

**Under the tightened policies, these specific legacy images become unreadable — including for their own owner, and even though their builds are public.** This is a real, scoped side effect of moving to the correct model, not a new bug introduced by this migration. Two ways to close it, and I'm recommending against baking a fix into the RLS policies themselves:

- **Rejected approach**: extend the SELECT policies to also match `builds.image_url`/`build_revisions.image_url` directly (string-comparing against legacy full-URL and new bare-path shapes in the same predicate). This works, but makes the policies materially harder to read and audit, mixes two different storage conventions into permanent security logic, and is exactly the kind of RLS complexity this migration is trying to reduce, not add.
- **Recommended approach**: leave the policies clean, matching the tracked migrations' original intent exactly. Treat "these 12 specific legacy rows need a `revision_media` row backfilled so they're covered by the *existing, correct* policy" as its own small, explicit, reviewable follow-up migration — a one-time data fix, not a permanent policy exception. This is exactly the kind of database write your instructions say to hold until "the read-path fix is proven" — so I'm proposing it as the next phase after this one, not bundled into it.

Given the affected rows are clearly test/development content (`"trap open"`, `"desk"`, `"build-soon"`, `"what-to-call"`), I'd suggest this is an acceptable, explicitly-flagged temporary regression rather than something that needs to block this security fix — but flagging clearly so it's a decision, not a surprise.

---

## 5. Legacy URL normalization (client-code, read path only — no data writes)

Per your spec, this is purely a `js/repositories/mediaRepository.js` read-time change — it never touches the database.

**Current behavior** (`resolveImageUrl`, `resolveBuildImageUrls`, `resolveAvatarUrl`, `resolveAvatarUrls`): if a stored value matches `FULL_URL_PATTERN` (`/^https?:\/\//i`), it's returned **as-is**, never signed — correct when the bucket was public, broken once it's private (and, per §4, likely already permission-denied at the RLS layer for the 12 affected rows even with a correct extraction, until the follow-up backfill lands).

**Proposed addition** — a new helper, used everywhere `FULL_URL_PATTERN` is currently checked:

```js
// Only strips the prefix if it's actually this project's own public-object
// URL shape — anything else (an unrecognized external URL, if one were
// ever stored) is left untouched rather than guessed at.
const SUPABASE_PUBLIC_OBJECT_PREFIX =
    `${SUPABASE_URL}/storage/v1/object/public/${BUCKET}/`;

function extractStoragePath(value) {
    if (!FULL_URL_PATTERN.test(value)) return value; // already bare
    if (!value.startsWith(SUPABASE_PUBLIC_OBJECT_PREFIX)) return null; // not ours — don't touch
    return decodeURIComponent(value.slice(SUPABASE_PUBLIC_OBJECT_PREFIX.length));
}
```

Every resolver would call this first; if it returns a real path, sign it (whether or not it needed extraction); if it returns `null` (a URL that doesn't match our own bucket's shape), fall back to today's behavior — return the value unchanged, exactly as now, so nothing that isn't recognized gets mishandled.

This covers all three cases you specified in one function: legacy `builds/...` paths, current `projects/...`/revision-media paths (already bare, pass through unchanged), and avatar paths (same URL shape, same extraction).

**What this does and doesn't fix**: it makes the *code* correct for any legacy URL regardless of prefix. It does **not**, by itself, make the 12 rows from §4 readable — that still needs the RLS-level fix (either the backfill or, if you'd rather do it now instead, the rejected broader-policy approach). I'm holding this code change until the policy migration is approved, per your instruction not to implement it separately yet.

---

## 6. Verification test plan (to run once the migration is applied)

**Anonymous — must still succeed:**
- List `avatars/{knownUserId}` → readable
- Sign + fetch a public build's `revision_media`-linked image → 200
- Sign + fetch any avatar path → 200

**Anonymous — must now fail (currently succeeds, this is the fix being verified):**
- `list("")` on the bucket root → empty/denied
- `list("projects")`, `list("projects/{anyDraftId}")` → empty/denied
- `createSignedUrl()` for a path inside someone's private draft folder → denied
- `.upload()` to any arbitrary path → denied

**Authenticated owner — must still succeed:**
- Read/list their own draft's gallery images
- Upload and re-upload (upsert) their own avatar
- Upload new gallery images into their own draft

**Authenticated, targeting a different user's content — must fail:**
- Sign a URL for another user's private draft image
- Upload/overwrite another user's avatar path
- Upload into another user's draft folder

The anonymous cases can be run the same way I gathered the evidence above (unauthenticated browser session, no login). The authenticated/cross-user cases need two real signed-in test accounts — I don't have credentials for either, so those four checks will need to be run by you (or with test accounts you provide) as part of confirming the migration before the bucket flip.

---

## Sequencing recap (matches your 6 requirements)

1. ✅ Broad policies identified (§1) — 4 of them, 2 SELECT + 1 INSERT(anon, unscoped) + 1 INSERT(authenticated, unscoped).
2. ✅ Compared against every intended access rule (§3's table).
3. Migration designed (§3's exact SQL) — **not yet written to `supabase/migrations/`, not yet applied.**
4. ✅ Confirmed required access is preserved for every category you listed (§3's coverage table) — including the one gap (avatar writes) that needed a genuinely new policy.
5. ✅ Confirmed the drop set eliminates anonymous listing, enumeration, signing, and reads of unrelated files (§1, tied to the empirical findings from the live testing).
6. ✅ Test plan proposed (§6), split into what I can verify myself (anonymous cases) vs. what needs your test accounts (cross-user cases).

Legacy URL normalization (§5) is included in this same plan as requested, sequenced after the access-rule design, with the data-backfill portion (§4) explicitly deferred to a follow-up phase rather than bundled in.

**Stopping here for your review, as instructed.** Nothing has been applied or implemented. Waiting on your go-ahead before I create the actual migration file, write the rollback, or touch `mediaRepository.js`.
