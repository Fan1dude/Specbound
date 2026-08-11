import { supabase } from "../core/supabase.js";
import { escapeLikeSpecialChars, quoteForOrFilter } from "../utils/sqlEscaping.js";

// Deliberately the SAME column list this had before Milestone 20 —
// getPublicProfile()/getProfilesByIds() are used far beyond the profile
// page itself (Home's Featured section, Explore, every build page's
// creator attribution, comments, follow lists, search, notifications —
// see the grep this comment is explaining) for simple build/comment
// attribution that never needed headline or featured_build_id. A
// PostgREST explicit column-list select fails ENTIRELY if any one named
// column doesn't exist yet (unlike select("*"), which just omits it), so
// adding those two columns here would have broken every one of those
// unrelated call sites the moment migration 0024 was written, well
// before it's actually applied to any database. getBuilderPortfolioProfile()
// below carries the two new columns instead, scoped to the one call site
// that actually needs them.
const PUBLIC_PROFILE_COLUMNS =
    "id, username, display_name, bio, location, website, github, youtube, avatar_path, avatar_url, created_at, followers_count, following_count";

// building_since_year (Milestone 23) joins headline/featured_build_id
// here for the exact same reason — only the Builder Portfolio page
// renders it, so every other PUBLIC_PROFILE_COLUMNS caller stays
// unaffected if this column doesn't exist yet on some environment.
const PORTFOLIO_PROFILE_COLUMNS = `${PUBLIC_PROFILE_COLUMNS}, headline, featured_build_id, building_since_year`;

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

// The Builder Portfolio page's own fetch (js/pages/profile/loadProfile.js
// only) — the one place headline/featured_build_id are actually read.
// Kept separate from getPublicProfile() precisely so every OTHER caller
// stays unaffected until migration 0024 is applied — see the comment on
// PUBLIC_PROFILE_COLUMNS above.
export async function getBuilderPortfolioProfile(id) {
    const { data, error } = await supabase
        .from("profiles")
        .select(PORTFOLIO_PROFILE_COLUMNS)
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

const SEARCH_PROFILE_COLUMNS = "id, username, display_name, headline, avatar_path, avatar_url";
const PROFILE_SEARCH_RESULT_LIMIT = 20;

// Milestone 23 §5 — "Creator" scope (and the Builders section of "All").
// There's no private-profile concept anywhere in this schema — every
// profiles row is already publicly selectable (same RLS every other
// function in this file already relies on) — so, unlike searchBuilds(),
// there's no visibility filter to apply here. Deliberately a slim,
// dedicated column list rather than PUBLIC_PROFILE_COLUMNS: a search
// result card only needs enough to identify and link to the builder
// (avatar, name, one-line headline), not their full bio/social
// links/follower counts.
export async function searchProfiles(query) {
    const trimmed = query.trim();

    if (!trimmed) return [];

    const likePattern = `%${escapeLikeSpecialChars(trimmed)}%`;
    const quotedPattern = quoteForOrFilter(likePattern);

    const { data, error } = await supabase
        .from("profiles")
        .select(SEARCH_PROFILE_COLUMNS)
        .or([
            `username.ilike.${quotedPattern}`,
            `display_name.ilike.${quotedPattern}`,
            `headline.ilike.${quotedPattern}`
        ].join(","))
        .order("username", { ascending: true })
        .limit(PROFILE_SEARCH_RESULT_LIMIT);

    if (error) throw error;

    return data || [];
}

// Confirms a profiles row exists for a signed-up user — created by an
// auth.users trigger (see docs/AUTH_ARCHITECTURE.md), not by this
// function. This used to also attempt an .insert() as a fallback for
// the case where the trigger hadn't run yet, "since we don't know
// whether a DB trigger already created the row before email
// confirmation completes." That fallback is removed: profiles has no
// INSERT policy at all (by design, confirmed live — see
// docs/AUTH_ARCHITECTURE.md), so the insert could never actually
// succeed. It wasn't a working safety net, just a call guaranteed to
// fail with a confusing RLS-denial error in the one scenario it was
// meant to handle. If the row genuinely doesn't exist, that means the
// trigger didn't fire — a real, rare failure worth surfacing honestly
// rather than papering over with an attempt that was always going to
// fail the same way.
export async function ensureProfile({ id }) {
    const { data: existing, error } = await supabase
        .from("profiles")
        .select("id")
        .eq("id", id)
        .maybeSingle();

    if (error) throw error;

    if (!existing) {
        throw new Error("Your profile wasn't created. Try refreshing, or contact support if this keeps happening.");
    }

    return existing;
}

// Marks the first-sign-in Welcome dialog as seen (Milestone 21). Called
// fire-and-forget from WelcomeDialog.js's exit handler — the dialog
// closes immediately regardless of whether this write succeeds; a
// failure only means it may show again on a later session (see
// core/onboarding.js's sessionStorage guard for the current-session
// case), never a blocking condition.
//
// .select("id").single() forces PostgREST to return the updated row
// (or throw) instead of silently reporting success on zero rows matched
// — a plain .update().eq() with no .select() does NOT error when the id
// doesn't match anything, which is exactly how the earlier profile.id
// (undefined) bug went unnoticed: the write silently affected zero rows
// every time. .single() throws when it gets back anything other than
// exactly one row, so an id that matches no profile (or, in principle,
// more than one) is now a real caught error, not a silent no-op. RLS is
// unchanged: the existing owner-scoped "Users can update their own
// profile" policy (0000) still governs which row this id is allowed to
// touch.
export async function markOnboardingWelcomed(id) {
    const { error } = await supabase
        .from("profiles")
        .update({ onboarding_welcomed_at: new Date().toISOString() })
        .eq("id", id)
        .select("id")
        .single();

    if (error) throw error;
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