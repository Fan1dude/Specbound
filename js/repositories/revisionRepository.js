import { supabase } from "../core/supabase.js";

// A successful query returning zero revisions is a genuine, legitimate
// result (a build with no history yet) — only a real network/database/
// permission/malformed-response failure throws. Callers must be able to
// tell "this build has no revisions" apart from "the revisions failed to
// load," which silently returning [] on error made impossible.
export async function getBuildRevisions(buildId) {
    const { data, error } = await supabase
        .from("build_revisions")
        .select("*")
        .eq("build_id", buildId)
        .order("created_at", { ascending: true });

    if (error) throw error;

    return data || [];
}

export async function getLatestBuildRevision(buildId) {
    const { data, error } = await supabase
        .from("build_revisions")
        .select("*")
        .eq("build_id", buildId)
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();

    if (error) throw error;

    return data;
}

export async function getRevisionById(revisionId) {
    const { data, error } = await supabase
        .from("build_revisions")
        .select("*")
        .eq("id", revisionId)
        .maybeSingle();

    if (error) throw error;

    return data;
}

// Feeds Builder Journey (see
// docs/milestones/MILESTONE_20_BUILDER_PORTFOLIO_SPECIFICATION.md §17.3) —
// a capped, most-recent-first window of one builder's revisions across ALL
// their public projects, joined to each revision's own build for the
// title/slug/category the timeline needs to display. Deliberately not the
// builder's entire history: buildBuilderJourney() (the pure function that
// consumes this) only ever surfaces a curated top 10, so fetching more than
// a few dozen recent rows here would just be discarded work. `limit`
// defaults to 100 as a generous window past that top-10, not a page size —
// there is no pagination for this feature (see spec §3.3d), so a
// builder's very old milestones falling outside this window is a known,
// accepted V1 limitation, not a bug.
export async function getRecentBuilderRevisions(userId, { limit = 100 } = {}) {
    const { data, error } = await supabase
        .from("build_revisions")
        .select(
            "id, build_id, title, snapshot_title, version, milestone, update_type, created_at, " +
            "builds!inner(title, slug, category, user_id, visibility)"
        )
        .eq("builds.user_id", userId)
        .eq("builds.visibility", "public")
        .order("created_at", { ascending: false })
        .limit(limit);

    if (error) throw error;

    return data || [];
}