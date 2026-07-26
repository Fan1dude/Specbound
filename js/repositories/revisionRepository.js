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