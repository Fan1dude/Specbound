import { supabase } from "../core/supabase.js";

// RLS on saved_builds (see supabase/migrations/0009_saved_builds.sql)
// already scopes SELECT to the caller's own row (user_id = auth.uid()),
// so a signed-out caller simply shouldn't call this at all.
export async function hasSavedBuild(buildId) {
    const { data, error } = await supabase
        .from("saved_builds")
        .select("id")
        .eq("build_id", buildId)
        .maybeSingle();

    if (error) throw error;

    return Boolean(data);
}

// set_build_saved() is an idempotent desired-state RPC, not a toggle —
// saved=true ensures a save exists, saved=false ensures it doesn't, and a
// retried call with the same value is always a safe no-op. Returns the
// authoritative `saved` state after the write.
export async function setBuildSaved(buildId, saved) {
    const { data, error } = await supabase.rpc("set_build_saved", {
        p_build_id: buildId,
        p_saved: saved
    });

    if (error) throw error;

    const row = Array.isArray(data) ? data[0] : data;

    return Boolean(row?.saved);
}

// Ordered most-recently-saved first. Returns only the join row
// (build_id, created_at) — the caller batch-fetches the actual build rows
// itself (same two-query, no-N+1 pattern as everywhere else in this app),
// since saved_builds has no FK PostgREST could embed a join through
// anyway (same reasoning as profiles never being embedded off user_id).
export async function getSavedBuildRefs(userId) {
    const { data, error } = await supabase
        .from("saved_builds")
        .select("build_id, created_at")
        .eq("user_id", userId)
        .order("created_at", { ascending: false });

    if (error) throw error;

    return data || [];
}
