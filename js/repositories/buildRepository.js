import { supabase } from "../core/supabase.js";

export async function getBuildById(id) {
    const { data, error } = await supabase
        .from("builds")
        .select("*")
        .eq("id", id)
        .maybeSingle();

    if (error) throw error;

    return data;
}

export async function getBuildBySlug(slug) {
    const { data, error } = await supabase
        .from("builds")
        .select("*")
        .eq("slug", slug)
        .single();

    if (error) throw error;

    return data;
}

// Batch lookup for a set of build ids (e.g. a user's saved projects) — one
// query instead of one per id. Deliberately unfiltered by visibility, same
// reasoning as getBuildBySlug: RLS alone already returns nothing for a
// build a non-owner shouldn't see (e.g. a saved project that later went
// private), so the caller just gets back fewer rows than ids requested —
// see savedRepository.js/renderWorkshop.js for how that gap is handled.
export async function getBuildsByIds(ids) {
    if (!ids.length) return [];

    const { data, error } = await supabase
        .from("builds")
        .select("*")
        .in("id", ids);

    if (error) throw error;

    return data || [];
}

// Public listing surfaces (Home, Explore) — RLS already blocks a private
// build from being read by anyone but its owner, but this filter is still
// needed for correct *behavior*, not just access control: without it, an
// owner browsing Explore would see their own unpublished projects mixed
// into a page that's supposed to show what everyone else sees.
export async function getFeaturedBuilds() {
    const { data, error } = await supabase
        .from("builds")
        .select("*")
        .eq("featured", true)
        .eq("visibility", "public")
        .order("featured_order");

    if (error) throw error;

    return data;
}

export async function getNewestBuilds(limit = 12) {
    const { data, error } = await supabase
        .from("builds")
        .select("*")
        .eq("visibility", "public")
        .order("created_at", { ascending: false })
        .limit(limit);

    if (error) throw error;

    return data;
}

const SEARCH_RESULT_LIMIT = 60;

// Postgres ILIKE treats %, _, and \ as special — escaping them first means
// a literal "%" or "_" typed by the user matches literally instead of
// acting as a wildcard.
function escapeLikeSpecialChars(value) {
    return value.replace(/\\/g, "\\\\").replace(/%/g, "\\%").replace(/_/g, "\\_");
}

// PostgREST's .or() filter is a small DSL where "," "." "(" ")" are
// structural, not literal — this is its own escaping layer on top of the
// ILIKE escaping above, needed only for values embedded in an .or()
// string. Wrapping a value in double quotes (escaping any literal quote/
// backslash first) is PostgREST's documented way to pass an arbitrary
// string safely, so a search containing a comma or parenthesis can't
// corrupt or extend the filter.
function quoteForOrFilter(value) {
    return `"${value.replace(/\\/g, "\\\\").replace(/"/g, "\\\"")}"`;
}

// Public builds only, matched against title/description/category directly,
// or against the builder's username via a separate profiles lookup first
// (builds.user_id references auth.users, not profiles — there's no FK for
// PostgREST to embed a join through, same reasoning as
// profileRepository.getProfilesByIds). Two queries total, not N+1.
export async function searchBuilds(query) {
    const trimmed = query.trim();

    if (!trimmed) return [];

    const likePattern = `%${escapeLikeSpecialChars(trimmed)}%`;

    const { data: matchingProfiles, error: profileError } = await supabase
        .from("profiles")
        .select("id")
        .ilike("username", likePattern);

    if (profileError) throw profileError;

    const matchingUserIds = (matchingProfiles || []).map(profile => profile.id);

    const quotedPattern = quoteForOrFilter(likePattern);

    const orConditions = [
        `title.ilike.${quotedPattern}`,
        `description.ilike.${quotedPattern}`,
        `category.ilike.${quotedPattern}`
    ];

    if (matchingUserIds.length) {
        orConditions.push(`user_id.in.(${matchingUserIds.join(",")})`);
    }

    const { data, error } = await supabase
        .from("builds")
        .select("*")
        .eq("visibility", "public")
        .or(orConditions.join(","))
        .order("created_at", { ascending: false })
        .limit(SEARCH_RESULT_LIMIT);

    if (error) throw error;

    return data || [];
}