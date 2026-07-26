import { supabase } from "../core/supabase.js";

export async function searchComponents({
    query,
    technologyId = null,
    componentType = null,
    limit = 10
}) {
    const normalizedQuery = String(query || "").trim();

    if (!normalizedQuery) {
        return [];
    }

    const { data, error } = await supabase.rpc(
        "search_components",
        {
            search_query: normalizedQuery,
            requested_technology: technologyId,
            requested_type: componentType,
            result_limit: limit
        }
    );

    if (error) {
        console.error("Component search error:", error);
        throw error;
    }

    return data || [];
}