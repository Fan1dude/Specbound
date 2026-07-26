import { supabase } from "../core/supabase.js";

// follows RLS is fully public (see supabase/migrations/0012_follows.sql),
// so this is a plain read, not scoped to the caller like
// hasLikedBuild/hasSavedBuild are — anyone can check whether any given
// follower/following pair exists.
export async function hasFollowed(followerId, followingId) {
    const { data, error } = await supabase
        .from("follows")
        .select("id")
        .eq("follower_id", followerId)
        .eq("following_id", followingId)
        .maybeSingle();

    if (error) throw error;

    return Boolean(data);
}

// set_follow() is an idempotent desired-state RPC, not a toggle —
// followed=true ensures a follow exists, followed=false ensures it
// doesn't, and a retried call with the same value is always a safe
// no-op. Returns the authoritative followed state plus both sides'
// counts, so the caller can reconcile immediately without a second fetch.
export async function setFollow(followingId, followed) {
    const { data, error } = await supabase.rpc("set_follow", {
        p_following_id: followingId,
        p_followed: followed
    });

    if (error) throw error;

    const row = Array.isArray(data) ? data[0] : data;

    return {
        followed: Boolean(row?.followed),
        followersCount: row?.followers_count ?? 0,
        followingCount: row?.following_count ?? 0
    };
}

// Keyset pagination (not offset), same shape as notificationRepository's
// getNotificationsPage — before is the created_at of the last row already
// loaded, so relationships formed between page loads can't shift results
// into skipped/duplicated rows the way offset pagination could.
export async function getFollowersPage(userId, { before = null, limit = 20 } = {}) {
    let query = supabase
        .from("follows")
        .select("follower_id, created_at")
        .eq("following_id", userId)
        .order("created_at", { ascending: false })
        .limit(limit);

    if (before) {
        query = query.lt("created_at", before);
    }

    const { data, error } = await query;

    if (error) throw error;

    return data || [];
}

// Batch check: of these targetIds, which does followerId already follow?
// One query for a whole rendered page of rows, not one per row.
export async function getFollowedIds(followerId, targetIds) {
    if (!targetIds.length) return [];

    const { data, error } = await supabase
        .from("follows")
        .select("following_id")
        .eq("follower_id", followerId)
        .in("following_id", targetIds);

    if (error) throw error;

    return (data || []).map(row => row.following_id);
}

export async function getFollowingPage(userId, { before = null, limit = 20 } = {}) {
    let query = supabase
        .from("follows")
        .select("following_id, created_at")
        .eq("follower_id", userId)
        .order("created_at", { ascending: false })
        .limit(limit);

    if (before) {
        query = query.lt("created_at", before);
    }

    const { data, error } = await query;

    if (error) throw error;

    return data || [];
}
