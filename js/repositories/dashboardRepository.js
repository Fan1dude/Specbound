import { supabase } from "../core/supabase.js";

export async function getMyBuilds(userId) {
    const { data, error } = await supabase
        .from("builds")
        .select("*")
        .eq("user_id", userId)
        .order("updated_at", { ascending: false });

    if (error) throw error;
    return data || [];
}

// Milestone 21: how many builds this account has ever published, used
// both to gate contextual editor hints (renderContextualHints.js) and to
// detect a first publish (editor/app.js) — deliberately NOT filtered by
// visibility. builds rows are only ever created by publish_draft(), and
// unpublishing (setBuildVisibility) only flips visibility, never deletes
// the row, so filtering to visibility='public' here would incorrectly
// make an unpublish-then-republish cycle look like a first publish again.
export async function getMyPublishedBuildCount(userId) {
    const { count, error } = await supabase
        .from("builds")
        .select("*", { count: "exact", head: true })
        .eq("user_id", userId);

    if (error) throw error;
    return count || 0;
}

export async function getMyRevisionCount(userId) {
    const { count, error } = await supabase
        .from("build_revisions")
        .select("*", { count: "exact", head: true })
        .eq("user_id", userId);

    if (error) throw error;
    return count || 0;
}