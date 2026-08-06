// Featured Project selection — see
// docs/milestones/MILESTONE_20_BUILDER_PORTFOLIO_SPECIFICATION.md §3.3(b),
// §17.2. Builder-controlled, never likes-based. Resolution order:
//   1. profile.featured_build_id, if it still points at one of this
//      builder's own PUBLIC builds — a pin can go stale if the build was
//      later made private (deletion is handled at the DB level via
//      `on delete set null`, so a deleted build never reaches this
//      function as a dangling id).
//   2. The most recently updated build with status "completed".
//   3. The most recently updated public build, any status.
//   4. null — the caller omits the Featured Project section entirely.
//
// `builds` is expected to already be filtered to visibility "public" (the
// shape getProfileBuilds() already returns) — no separate query is made
// here, this is a pure selection over data the caller already has.
export function resolveFeaturedBuild(profile, builds) {
    const pinned = profile.featured_build_id
        ? builds.find(build => build.id === profile.featured_build_id && build.visibility === "public")
        : null;
    if (pinned) return pinned;

    const completed = builds.filter(build => build.status === "completed");
    if (completed.length) {
        return mostRecentlyUpdated(completed);
    }

    if (builds.length) {
        return mostRecentlyUpdated(builds);
    }

    return null;
}

function mostRecentlyUpdated(list) {
    return list.slice().sort((a, b) => new Date(b.updated_at) - new Date(a.updated_at))[0];
}
