# Milestone 8C — Performance & Request Efficiency: Proposed Architecture

Architecture only — nothing in this document has been implemented. All findings below were re-verified directly against the current codebase and, where relevant, the live Supabase backend (confirmed `createSignedUrls` exists and its exact response shape) rather than relied on from memory.

---

## 1. Duplicate `getCurrentUser()` calls per page load

**Current request flow**: `js/core/layout.js`'s `loadNavbar()` — called first by literally every page — calls `getCurrentUser()` (→ `supabase.auth.getUser()`, a real server round-trip that re-validates the JWT, not a local read). Separately, the page's own load flow calls it again, either directly (`loadBuild.js`, `loadProfile.js`, `loadFollowList.js`, `home/app.js`) or via `requireAuth()` (`loadDashboard.js`, `loadWorkshop.js`, `settings/app.js`, `upload/app.js`, `notifications/loadNotifications.js`, `editor/app.js`, `continue.js`). Both calls fire concurrently (neither awaits the other first), so this is two full auth round-trips on every single page view in the app, all the time.

**Exact performance problem**: 2x the necessary auth network calls, site-wide, on every page load — the single highest-frequency redundant request in the app.

**Proposed architecture**: memoize `getCurrentUser()` in `js/core/auth.js` — cache the in-flight/resolved promise for the lifetime of one page load, so a second call within the same page returns the same promise instead of issuing a new request. Reset only on explicit sign-out (`js/core/layout.js`'s logout handler) so a stale "signed in" result can never survive past a sign-out action.

```js
let cachedUserPromise = null;

export function getCurrentUser() {
    if (!cachedUserPromise) {
        cachedUserPromise = supabase.auth.getUser().then(({ data }) => data.user);
    }
    return cachedUserPromise;
}

export function clearCurrentUserCache() {
    cachedUserPromise = null;
}
```

`requireAuth()` calls the same (now-memoized) `getCurrentUser()`, so it's covered for free.

**Files that would change**: `js/core/auth.js`, `js/core/layout.js` (call `clearCurrentUserCache()` in the logout handler).

**SQL/RPC changes required**: none.

**Expected request-count reduction**: 1 fewer `auth.getUser()` call per page load — on every authenticated *and* every anonymous page (the anonymous check still happens once, just not twice), site-wide. This is the single largest aggregate reduction in this milestone by call volume, even though each individual saving is small.

**Verification plan**: on a few representative pages (home, build, profile, workshop while signed in), confirm via `read_network_requests`/console instrumentation that exactly one `auth.getUser()`-shaped request fires per load instead of two; confirm sign-out still correctly clears the session (no stale "signed in" state survives a subsequent page load after logout).

---

## 2. `resolveBuildImageUrls` — batches the call site, not the network request

**Current request flow**: `js/repositories/mediaRepository.js`'s `resolveBuildImageUrls(builds)` does `Promise.all(builds.map(async build => ({ ...build, image_url: await resolveImageUrl(build.image_url) })))` — each `resolveImageUrl` → `getMediaSignedUrl` issues its own `storage.createSignedUrl(path, expiry)` call. This is the app's one and only "batch" image-resolution primitive, used by Explore, Home (both Featured Spotlight and Activity Feed), Workshop, Dashboard, Profile, Search, and Follow lists.

**Exact performance problem**: N parallel HTTP requests for N images, not one batched request. Confirmed live: Explore's `getNewestBuilds(100)` means a single Explore page load can fire up to 100 concurrent signed-URL requests. `resolveAvatarUrl` has the identical shape and is used the same unbatched way in a loop wherever multiple avatars render (`renderComments.js`, `renderFollowList.js`).

**Proposed architecture**: confirmed live against the actual Supabase Storage client that `createSignedUrls(paths: string[], expiresIn)` exists and returns one array of `{ path, signedUrl, error }` per call — genuinely one HTTP request for any number of paths. Add a batch primitive and rebuild both `resolveBuildImageUrls` and a new `resolveAvatarUrls` on top of it:

```js
export async function getMediaSignedUrls(storagePaths) {
    const uniquePaths = [...new Set(storagePaths.filter(Boolean))];
    if (!uniquePaths.length) return new Map();

    const { data, error } = await supabase.storage.from(BUCKET).createSignedUrls(uniquePaths, SIGNED_URL_EXPIRY_SECONDS);
    if (error) throw error;

    return new Map(data.map(item => [item.path, item.error ? "" : item.signedUrl]));
}

export async function resolveBuildImageUrls(builds) {
    const pathsNeedingSigning = builds
        .map(build => build.image_url)
        .filter(value => value && !FULL_URL_PATTERN.test(value));

    const urlByPath = await getMediaSignedUrls(pathsNeedingSigning).catch(() => new Map());

    return builds.map(build => {
        const value = build.image_url;
        if (!value) return { ...build, image_url: "" };
        if (FULL_URL_PATTERN.test(value)) return build;
        return { ...build, image_url: urlByPath.get(value) || "" };
    });
}

export async function resolveAvatarUrls(profiles) {
    const pathsNeedingSigning = profiles
        .map(profile => profile?.avatar_path)
        .filter(Boolean);

    const urlByPath = await getMediaSignedUrls(pathsNeedingSigning).catch(() => new Map());

    return new Map(profiles.map(profile => [
        profile?.id,
        profile?.avatar_path ? (urlByPath.get(profile.avatar_path) || "") : (profile?.avatar_url || "")
    ]));
}
```

`resolveImageUrl` (the single-item helper, still used by the build detail page's single cover image and the revision-view path) stays as-is — this is specifically about *list* rendering, where N items are resolved together.

**Files that would change**: `js/repositories/mediaRepository.js` (new batch primitive + rebuilt `resolveBuildImageUrls` + new `resolveAvatarUrls`), `js/pages/build/renderComments.js` (avatar resolution loop → `resolveAvatarUrls`), `js/pages/followList/renderFollowList.js` (same).

**SQL/RPC changes required**: none — this is a Supabase Storage client API change, not a database change.

**Expected request-count reduction**: Explore (worst case, 100 builds): ~100 requests → 1. Every other list page: N requests → 1. Comments (up to 50 avatars, and previously not even deduped by author): up to 50 requests → 1 (and deduped, so a prolific commenter's avatar is only signed once regardless of how many comments they posted).

**Verification plan**: live-verify `createSignedUrls` behavior once more against real multi-path input (already confirmed the response shape); load Explore with the network panel open and confirm exactly one Storage request fires instead of many; confirm a build with a legacy full-URL `image_url` (not a bare path) still renders correctly without being sent through signing at all; confirm a broken/missing path still degrades to `""` (no `<img>` shown) exactly as it does today, not a thrown error.

---

## 3. Comments: hard 50-cap, no continuation path

**Current request flow**: `commentRepository.js`'s `getBuildComments(buildId)` — `order("created_at", { ascending: true }).limit(50)`, no cursor parameter of any kind.

**Exact performance problem**: comments render oldest-first (a conversational thread order) — meaning the cap doesn't hide old comments, it hides *everything past the 50th ever posted*. On any build with real sustained engagement, comment #51 onward is permanently invisible to every visitor except (client-side only, for their own browser session) the person who just posted it. This is also flagged as one of the highest-write-volume tables in the app with the least pagination coverage.

**Proposed architecture**: keyset "Load More," matching the majority-established pattern already used by Notifications and Follow lists (a plain `created_at` cursor via PostgREST, not the stricter composite `(created_at, id)` cursor Activity Feed uses — comments doesn't need that level of tie-break precision, and matching the more common existing pattern keeps this a repository-only change with no new migration). Direction is `after`, not `before`, since comments display oldest-first and "more" means "further along the thread," not "further back in time":

```js
export async function getBuildComments(buildId, { after = null, limit = INITIAL_COMMENT_LIMIT } = {}) {
    let query = supabase
        .from("comments")
        .select("*")
        .eq("build_id", buildId)
        .order("created_at", { ascending: true })
        .limit(limit);

    if (after) {
        query = query.gt("created_at", after);
    }

    const { data, error } = await query;
    if (error) throw error;
    return data || [];
}
```

`renderComments.js` gains a "Load More" button (hidden unless the last page was full), matching the visual/behavioral shape already established for Notifications/Follow lists/Activity Feed — this is the "small explicit control" pagination is permitted to add per the constraints, not a redesign.

**Files that would change**: `js/repositories/commentRepository.js`, `js/pages/build/renderComments.js`, `pages/build/build.html` (add a "Load More" button element, matching the pattern already present on Notifications/Followers/Following/Home).

**SQL/RPC changes required**: none — `comments (build_id, created_at)` (added in `0007`) already serves this query shape.

**Expected request-count reduction**: this isn't a *reduction* — it's closing a correctness gap (making comment #51+ reachable at all). No change to the common case (a build with ≤50 comments makes exactly the same one request it does today).

**Verification plan**: seed/confirm a build with 50+ comments (or simulate via a mocked test), verify the 51st comment is now reachable via Load More, verify the existing 50-and-under case is pixel-for-pixel unchanged, verify Load More correctly fetches strictly-after the last-loaded comment's timestamp with no skips/duplicates.

---

## 4. Repeated profile/user-attachment queries across cards and feeds

**Current request flow, confirmed live**: `js/features/featured.js`'s Featured Spotlight carousel (home page) calls `getProfile(userId)` — a single-row, unbatched fetch — *every time the visible slide changes*: on initial load, on every 6-second auto-advance, and on every manual prev/next click. It cycles through only 5 builds (`getNewestBuilds(5)`), so within 30 seconds of a visit, all 5 profiles have already been fetched once — and continuing to sit on the page re-fetches the exact same 5 profiles over and over, indefinitely, for as long as the tab stays open, with zero caching. Separately on the same page, `js/pages/home/renderActivityFeed.js` batch-fetches profiles for its own visible builds via `attachBuildProfiles`. These two sections have high overlap potential (Featured Spotlight shows the newest builds; Activity Feed's Explore scope also surfaces the newest activity) and never share results.

**Exact performance problem**: an unbounded, ever-repeating redundant fetch pattern (not just a one-time duplication) for a small, static set of profiles, purely from leaving the homepage open — the most severe individual finding in this milestone by "requests over time," even though it's invisible in a single-page-load request count.

**Proposed architecture**: cache resolved builder names for the lifetime of the carousel (it only ever needs the same 5 names, known up front once `featuredBuilds` loads) instead of re-fetching per slide change:

```js
async function loadFeaturedBuilds() {
    const builds = await getNewestBuilds(5);
    if (!builds?.length) return;

    featuredBuilds = await resolveBuildImageUrls(builds);

    const uniqueUserIds = [...new Set(featuredBuilds.map(b => b.user_id).filter(Boolean))];
    const profiles = await getProfilesByIds(uniqueUserIds);
    builderNameById = new Map(profiles.map(p => [p.id, p.username || "Unknown Builder"]));

    showBuild(0);
    startCarousel();
}
```

`showBuild()` becomes a synchronous lookup (`builderNameById.get(build.user_id) || "Unknown Builder"`) instead of an async fetch. This also incidentally fixes the redundancy against Activity Feed for free — not because the two sections start sharing a cache (that would require a cross-module coordination layer this milestone's "no broad refactoring" constraint argues against), but because Featured Spotlight's own request count drops from "unbounded, forever" to "one batch call, once."

**Files that would change**: `js/features/featured.js`.

**SQL/RPC changes required**: none — reuses the existing `getProfilesByIds` batch helper.

**Expected request-count reduction**: from an unbounded number of `getProfile()` calls (growing for as long as the tab stays open) to exactly 1 batched call for the whole carousel's lifetime.

**Verification plan**: load the homepage, let the carousel auto-advance through several full cycles, confirm via network monitoring that exactly one profile-batch request fires total (not one per slide change); confirm builder names still display correctly on every slide, including after manual prev/next clicks.

---

## 5. Duplicate/redundant calls between page controllers and child renderers

Beyond `getCurrentUser()` (§1) and the Featured Spotlight case (§4), a full re-audit of every batch-enrichment call site (`getProfilesByIds`, `attachBuildProfiles`, `getBuildsByIds`, `enrichNotifications`) found the batch-fetch layer itself is clean — every site correctly dedupes ids via `Set` before calling and merges via `Map` afterward. One narrow, low-impact edge case: if a build's own owner has also commented on their own project, `js/pages/build/loadBuild.js` (fetches the creator's profile once, for the byline) and `renderComments.js` (batch-fetches every comment author's profile, which would include the owner if they commented) issue two separate single-purpose queries that happen to overlap in that one specific case.

**Proposed architecture**: not proposing a fix for the comment-author overlap — it only occurs when a build owner comments on their own project, the two fetches serve genuinely different purposes (byline vs. comment attribution) and different data shapes, and coordinating them would mean threading extra state between `loadBuild.js` and `renderComments.js` for a case that saves at most one query, occasionally. This is exactly the kind of "unnecessary abstraction for a marginal case" the constraints ask to avoid. No changes proposed for this item beyond what §1 and §4 already cover.

**Files that would change**: none beyond §1/§4.

**SQL/RPC changes required**: none.

**Expected request-count reduction**: none beyond §1/§4 (already counted there).

**Verification plan**: none needed beyond §1/§4's verification.

---

## 6. Activity Feed query behavior after the new `build_revisions` indexes

**Current request flow**: `get_activity_feed()` (`0013`, indexes added in `0015`/Milestone 8A) orders `build_revisions` by `(created_at desc, id desc)` and, per candidate row, runs a correlated subquery against `build_revisions` (for `new_project`/`new_revision` classification) and, for the `following` scope only, an `exists` check against `follows`.

**Analysis**:
- **Explore scope**: well-served by the new indexes. `build_revisions (created_at desc, id desc)` drives the ordering/pagination directly; `build_revisions (build_id, created_at, id)` drives the per-row classification subquery as an index range scan instead of a sequential scan. No further change needed.
- **Following scope**: the classification subquery is equally well-served. But the `follows`-membership filter is evaluated *after* rows are pulled in global time order — for a user following very few people relative to total platform activity, the query may need to scan considerably more of `build_revisions` than the eventual result-set size before accumulating `p_limit` matching rows, especially on deep pagination (page 5+). This is a real, understood limitation of computing the feed live rather than maintaining a per-follower fan-out table (the exact tradeoff already decided against in Milestone 7D, for good reason — a fan-out table means real write-time cost and duplication for a feature with, currently, very light usage).

**Proposed architecture**: no schema or query change is proposed as *required* right now — there's no evidence this is an actual bottleneck at current or realistically-near-term scale (few users, few follow relationships), and a "fan out on write" table is explicitly the kind of broader architectural change this milestone's constraints ask to avoid. **Optional, low-risk, additive recommendation** worth doing now since it's cheap and non-disruptive: add `create index build_revisions_user_id_created_at_id_idx on build_revisions (user_id, created_at desc, id desc);` — this doesn't require changing `get_activity_feed()`'s existing query shape to pay off (Postgres's planner can already use it opportunistically for the `follows`-adjacent lookups), and it sets up the option of later rewriting the `following` scope's filter as `br.user_id = any(...)` instead of a correlated `exists`, which this index would serve very well as a per-user merge-scan, if evidence ever shows the current shape is too slow.

**Files that would change**: (if the optional index is approved) a new migration only — no application code changes.

**SQL/RPC changes required**: one optional new index, `build_revisions_user_id_created_at_id_idx`. No change to `get_activity_feed()` itself.

**Expected request-count reduction**: none — this is a query-cost concern, not a request-count concern. Flagging it here because the milestone explicitly asked for a review of Activity Feed behavior post-indexing.

**Verification plan**: not applicable unless the optional index is approved — if it is, verify via `pg_indexes` that it was created successfully; no behavior change to verify client-side since nothing about the feed's visible output changes.

---

## 7. N+1 request patterns — full sweep

Beyond `resolveBuildImageUrls`/`resolveAvatarUrl` (§2, the two real N+1 offenders) and Featured Spotlight (§4, an N+1-over-time pattern), a targeted re-check found no other loop-with-per-item-await pattern:
- No list view shows a per-card like/save/follow control today (those only exist on the single-build detail page), so there's no per-card "check my like status" loop to worry about.
- `getCommentCountForBuilds`, `getFollowedIds`, `enrichNotifications`, `attachBuildProfiles`, `getBuildsByIds` are all already correctly batched, confirmed by direct re-reading of every call site.
- The Featured Spotlight fix in §4 and the avatar-batching fix in §2 together close every N+1-shaped pattern found in this codebase.

**Files that would change**: none beyond §2/§4.

**SQL/RPC changes required**: none beyond §2/§4.

**Expected request-count reduction**: none beyond §2/§4 (already counted there).

**Verification plan**: none needed beyond §2/§4's verification.

---

## 8. Large DOM rendering loops — incremental rendering for growing lists

**Current request flow / rendering pattern**: Activity Feed, Notifications, and Follow lists all implement "Load More" by appending the new page to an in-memory array, then doing `container.innerHTML = allItems.map(renderRow).join("")` — a full rebuild of the *entire accumulated list*, including every previously-rendered card, on every single "Load More" click. By the 4th–5th click (80–100 items), each additional click re-parses and re-lays-out the whole growing DOM tree instead of just appending 20 new items.

**Exact performance problem**: rendering cost grows with total accumulated items, not with the size of the new page — quadratic-ish cost across a session of repeated "Load More" clicks, worst on Activity Feed since its cards (`BlueprintCard`) are the heaviest markup of the three.

**Proposed architecture**: split "append a new page" from "patch an existing item" — these three files already cleanly separate their `renderList()` (full rebuild) from single-item mutation logic (which, confirmed by re-reading all three, already correctly patches just the one affected DOM node rather than re-rendering — marking one notification read, or toggling one follow row, do **not** trigger a full rebuild today, matching the milestone's own hoped-for behavior already). The one remaining case is specifically "Load More": change it from "rebuild everything from the full array" to "append only the newly-fetched page's rendered markup" via `insertAdjacentHTML("beforeend", newPageHtml)`, and re-bind event listeners only on the newly-inserted nodes (each file already scopes its listener binding to a `querySelectorAll` pass — this changes to running that pass over the newly-inserted fragment only, not the whole container).

Workshop's Saved Projects "remove" action (no pagination, but does a full-array re-render on every single removal) is a smaller, lower-priority candidate for the same treatment — removing one card could become a direct `.remove()` on that one DOM node instead of re-rendering the whole grid. Given it's unpaginated and realistically small (tens of items, not hundreds — see the Milestone 8 audit's own assessment that this was an acceptable tradeoff at current scale), I'd recommend including it only if the Load-More fix is approved and goes smoothly, not as an equally urgent item.

**Files that would change**: `js/pages/home/renderActivityFeed.js`, `js/pages/notifications/renderNotifications.js`, `js/pages/followList/renderFollowList.js`, and (once §3 ships) `js/pages/build/renderComments.js`'s new Load More path. Optionally `js/pages/workshop/renderWorkshop.js`'s saved-remove path.

**SQL/RPC changes required**: none — this is pure client-side rendering, no data-layer change.

**Expected request-count reduction**: none — this is a rendering-cost fix, not a network-request fix. Included because the milestone explicitly asked for it.

**Verification plan**: click "Load More" repeatedly on Activity Feed/Notifications/Follow lists (real or mocked data) and confirm via a DOM-mutation observer or manual inspection that only the new page's nodes are added to the DOM (the existing nodes are never removed/recreated — checkable by tagging existing nodes and confirming they're the exact same element references after a subsequent Load More, not new elements with identical content); confirm single-item mutations (mark-read, remove, follow-toggle) are unaffected and remain exactly as targeted as they already are today.

---

## Summary: files touched across all approved items

| File | Reason |
|---|---|
| `js/core/auth.js` | §1 — memoize `getCurrentUser()` |
| `js/core/layout.js` | §1 — clear cache on sign-out |
| `js/repositories/mediaRepository.js` | §2 — batch signed-URL primitive |
| `js/pages/build/renderComments.js` | §2 (avatar batching) + §3 (pagination) + §8 (append-only Load More) |
| `js/pages/followList/renderFollowList.js` | §2 (avatar batching) + §8 (append-only Load More) |
| `js/repositories/commentRepository.js` | §3 — pagination |
| `pages/build/build.html` | §3 — Load More control |
| `js/features/featured.js` | §4 — cache builder names for the carousel's lifetime |
| `js/pages/home/renderActivityFeed.js` | §8 — append-only Load More |
| `js/pages/notifications/renderNotifications.js` | §8 — append-only Load More |
| (optional) new migration | §6 — additive `build_revisions(user_id, created_at desc, id desc)` index |
| (optional) `js/pages/workshop/renderWorkshop.js` | §8 — incremental remove, lower priority |

No item in this plan requires a required SQL/RPC change — §6's index is explicitly optional and additive. Nothing here changes visible product behavior except §3 and §8's Load More controls, which are the explicitly-permitted "small explicit control" pagination requires.

Stopping here for review before implementing.
