import { supabase } from "../core/supabase.js";
import { getAnonViewerId } from "../core/anonViewerId.js";

// record_build_view() is idempotent-per-cooldown-window, not a toggle —
// calling it repeatedly within 30 minutes for the same viewer is always a
// safe no-op. p_anon_id is always sent (even when signed in); the
// function itself prefers auth.uid() when present and simply ignores the
// anon id in that case, so the client doesn't need to branch on auth
// state here. Always returns the current authoritative views count, even
// when it didn't increment (owner, private, or within cooldown).
export async function recordBuildView(buildId) {
    const { data, error } = await supabase.rpc("record_build_view", {
        p_build_id: buildId,
        p_anon_id: getAnonViewerId()
    });

    if (error) throw error;

    const row = Array.isArray(data) ? data[0] : data;

    return row?.views ?? 0;
}
