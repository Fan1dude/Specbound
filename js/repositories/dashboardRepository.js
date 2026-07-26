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

export async function getMyRevisionCount(userId) {
    const { count, error } = await supabase
        .from("build_revisions")
        .select("*", { count: "exact", head: true })
        .eq("user_id", userId);

    if (error) throw error;
    return count || 0;
}