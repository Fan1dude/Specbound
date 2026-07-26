import { supabase } from "../core/supabase.js";

// get_activity_feed() is a pure read (SECURITY INVOKER — see
// supabase/migrations/0013_activity_feed.sql), computed live from
// build_revisions/builds/follows, not a stored table. Composite keyset
// cursor (beforeCreatedAt + beforeId) — both must be passed together for
// any page after the first, since comparing created_at alone could skip
// or duplicate rows when two revisions share a timestamp.
export async function getActivityFeed({ scope, beforeCreatedAt = null, beforeId = null, limit = 20 } = {}) {
    const { data, error } = await supabase.rpc("get_activity_feed", {
        p_scope: scope,
        p_before_created_at: beforeCreatedAt,
        p_before_id: beforeId,
        p_limit: limit
    });

    if (error) throw error;

    return data || [];
}
