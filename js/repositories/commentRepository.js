import { supabase } from "../core/supabase.js";

// Page size for comment loading — was a hard, un-paginated cap through
// Milestone 8B ("a simple reasonable initial limit," Milestone 6A). Since
// comments render oldest-first (a conversational order, not a feed),
// pagination continues *forward* in time (after a cursor), not backward
// like every other keyset-paginated list in this app — "Load More" means
// "further along the thread," not "further back in history." RLS (see
// supabase/migrations/0007_comments.sql) already excludes soft-deleted
// comments and comments on a build the caller can't see, so this is a
// plain read with no extra filtering needed here. Uses a plain created_at
// cursor (not the stricter composite (created_at, id) cursor Activity
// Feed uses) — matching the same lower-precision, simpler pattern already
// used by Notifications and Follow lists.
const COMMENT_PAGE_SIZE = 50;

export async function getBuildComments(buildId, { after = null, limit = COMMENT_PAGE_SIZE } = {}) {
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

// Total comments received across a set of builds (e.g. a builder's
// published projects, for their profile stats) — a count-only query, no
// rows fetched. RLS (deleted_at is null and the parent build is visible)
// already restricts this correctly with no extra filtering needed here:
// for a public profile page, buildIds is already scoped to that builder's
// public projects, so every comment RLS would return is one that should
// count.
export async function getCommentCountForBuilds(buildIds) {
    if (!buildIds.length) return 0;

    const { count, error } = await supabase
        .from("comments")
        .select("*", { count: "exact", head: true })
        .in("build_id", buildIds);

    if (error) throw error;

    return count || 0;
}

// Batch lookup for a set of specific comment ids — Milestone 24's
// moderation queue, resolving a content_reports row whose target_type is
// "comment" (see moderationRepository.js). Same shape/pattern as
// buildRepository.js's getBuildsByIds()/profileRepository.js's
// getProfilesByIds(): a plain `.in("id", ids)` select relying entirely on
// RLS, no extra filtering here. RLS (0007_comments.sql) already excludes
// soft-deleted comments and comments on a build the caller can't see — so
// a moderator reviewing a report against a comment that's since been
// deleted, or whose build has gone private/unpublished, simply gets that
// id back missing from the result, never an error. Callers must treat a
// missing id as "unavailable," not assume every requested id resolves.
export async function getCommentsByIds(ids) {
    const uniqueIds = [...new Set(ids)];

    if (!uniqueIds.length) return [];

    const { data, error } = await supabase
        .from("comments")
        .select("id, build_id, user_id, body, created_at")
        .in("id", uniqueIds);

    if (error) throw error;

    return data || [];
}

// Calls the SECURITY DEFINER create_comment() function (see
// supabase/migrations/0007_comments.sql) — the only path allowed to
// insert into comments. auth.uid() is read server-side, not passed here,
// so it can't be spoofed.
export async function createComment(buildId, body) {
    const { data, error } = await supabase.rpc("create_comment", {
        p_build_id: buildId,
        p_body: body
    });

    if (error) throw error;

    return data;
}

// Calls the SECURITY DEFINER delete_comment() function. Soft-deletes
// (sets deleted_at) rather than removing the row — the comment then
// disappears from getBuildComments() via RLS, not because it's gone.
export async function deleteComment(commentId) {
    const { data, error } = await supabase.rpc("delete_comment", {
        p_comment_id: commentId
    });

    if (error) throw error;

    return data;
}
