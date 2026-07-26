import { supabase } from "../core/supabase.js";

// RLS on likes (see supabase/migrations/0008_project_likes.sql) already
// scopes SELECT to the caller's own row (user_id = auth.uid()), so no
// user id needs to be passed or filtered on here — a signed-out caller
// simply shouldn't call this at all.
export async function hasLikedBuild(buildId) {
    const { data, error } = await supabase
        .from("likes")
        .select("id")
        .eq("build_id", buildId)
        .maybeSingle();

    if (error) throw error;

    return Boolean(data);
}

// set_build_like() is an idempotent desired-state RPC, not a toggle —
// liked=true ensures a like exists, liked=false ensures it doesn't, and a
// retried call with the same value is always a safe no-op. Returns the
// authoritative { liked, likes_count } after the write, which the caller
// should use to reconcile its optimistic UI rather than trusting its own
// guess.
export async function setBuildLike(buildId, liked) {
    const { data, error } = await supabase.rpc("set_build_like", {
        p_build_id: buildId,
        p_liked: liked
    });

    if (error) throw error;

    const row = Array.isArray(data) ? data[0] : data;

    return { liked: Boolean(row?.liked), likesCount: row?.likes_count ?? 0 };
}
