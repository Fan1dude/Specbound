import { supabase } from "../core/supabase.js";

const PUBLIC_PROFILE_COLUMNS =
    "id, username, display_name, bio, location, website, github, youtube, avatar_path, avatar_url, created_at, followers_count, following_count";

export async function getProfile(id) {
    const { data, error } = await supabase
        .from("profiles")
        .select("*")
        .eq("id", id)
        .single();

    if (error) throw error;

    return data;
}

export async function getPublicProfile(id) {
    const { data, error } = await supabase
        .from("profiles")
        .select(PUBLIC_PROFILE_COLUMNS)
        .eq("id", id)
        .single();

    if (error) throw error;

    return data;
}

// Batch lookup for rendering a list of items each attributed to a
// different user (e.g. comments) — one query instead of one per item.
// No comments.user_id -> profiles FK exists (every user_id column in this
// schema points at auth.users, not profiles — see
// supabase/migrations/0007_comments.sql), so this is a separate query the
// caller merges client-side, same pattern as every other build/profile
// pairing in this app.
export async function getProfilesByIds(ids) {
    const uniqueIds = [...new Set(ids)];

    if (!uniqueIds.length) return [];

    const { data, error } = await supabase
        .from("profiles")
        .select(PUBLIC_PROFILE_COLUMNS)
        .in("id", uniqueIds);

    if (error) throw error;

    return data || [];
}

// Batch-attaches each build's owning profile in one call — for a list of
// builds that may belong to many different owners (e.g. Explore, Home),
// not the single-owner case (a builder's own profile page, Workshop's "My
// Projects") where the caller already has the one relevant profile in
// hand and can attach it directly without a query. Builds whose profile
// lookup comes back empty (shouldn't normally happen) simply get
// profiles: null — BlueprintCard already falls back to "Unknown Creator"
// for that case.
export async function attachBuildProfiles(builds) {
    if (!builds.length) return builds;

    const uniqueUserIds = [...new Set(builds.map(build => build.user_id))];
    const profiles = await getProfilesByIds(uniqueUserIds);
    const profilesById = new Map(profiles.map(profile => [profile.id, profile]));

    return builds.map(build => ({
        ...build,
        profiles: profilesById.get(build.user_id) || null
    }));
}

// Creates a profiles row for a new user only if one doesn't already exist.
// Deliberately not an upsert: a blind upsert would overwrite a username the
// user later changed in settings every time this runs (e.g. on each login,
// since we don't know whether a DB trigger already created the row before
// email confirmation completes).
export async function ensureProfile({ id, username }) {
    const { data: existing, error: lookupError } = await supabase
        .from("profiles")
        .select("id")
        .eq("id", id)
        .maybeSingle();

    if (lookupError) throw lookupError;

    if (existing) return existing;

    const { data, error } = await supabase
        .from("profiles")
        .insert([{ id, username }])
        .select()
        .single();

    if (error) throw error;

    return data;
}

export async function updateAvatarPath(id, avatarPath) {
    const { error } = await supabase
        .from("profiles")
        .update({ avatar_path: avatarPath })
        .eq("id", id);

    if (error) throw error;
}

// The public profile page — always filters to visibility='public', even
// when the viewer is the profile's own owner, so this page shows exactly
// what any visitor sees. Owner-context listings (Dashboard, Workshop) use
// dashboardRepository.getMyBuilds() instead, which intentionally includes
// unpublished projects.
export async function getProfileBuilds(userId) {
    const { data, error } = await supabase
        .from("builds")
        .select("*")
        .eq("user_id", userId)
        .eq("visibility", "public")
        .order("created_at", { ascending: false });

    if (error) throw error;

    return data || [];
}