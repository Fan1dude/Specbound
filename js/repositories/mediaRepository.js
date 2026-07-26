import { supabase } from "../core/supabase.js";
import { SUPABASE_URL } from "../core/config.js";

const BUCKET = "project-images";

// 7 days: long enough that listing pages (Explore, Workshop, Dashboard,
// draft gallery) aren't re-signing on every render, short enough that a
// leaked URL doesn't stay valid indefinitely. project-images is a private
// bucket going forward — see supabase/migrations/0002_publish_draft_and_visibility.sql
// for the RLS policies that make signing succeed for both draft owners
// (their own paths) and anonymous visitors (avatars/*, published media).
const SIGNED_URL_EXPIRY_SECONDS = 60 * 60 * 24 * 7;

export async function getMediaSignedUrl(storagePath) {
    const { data, error } = await supabase
        .storage
        .from(BUCKET)
        .createSignedUrl(storagePath, SIGNED_URL_EXPIRY_SECONDS);

    if (error) throw error;

    return data.signedUrl;
}

const FULL_URL_PATTERN = /^https?:\/\//i;

// Milestone 9 Migration B — legacy compatibility layer. Storage RLS was
// hardened and the project-images bucket flipped to Private (see
// docs/MILESTONE_9_STORAGE_RLS_MIGRATION.md); this bucket's own public
// object URLs no longer resolve to anything at all, so any stored value
// still shaped like one needs to be converted to a signable path before
// use. Deliberately read-path-only: nothing here ever writes back to the
// database (image_url/avatar_url are never rewritten), and nothing here
// touches a URL that isn't recognizably this exact bucket's own — see
// extractStoragePath() below.
const PUBLIC_OBJECT_PREFIX = `${SUPABASE_URL}/storage/v1/object/public/${BUCKET}/`;

// builds.image_url, build_revisions.image_url, and profiles.avatar_url
// hold one of three shapes: a bare storage-relative path (e.g.
// "projects/{draftId}/{mediaId}.jpg", written since Milestone 5A — already
// signable as-is), a legacy full URL pointing at THIS project's own
// project-images bucket (written by pre-5A code, e.g. continue.js's old
// getPublicUrl() call, or an avatar uploaded before avatar_path existed —
// no longer fetchable directly now that the bucket is private, but the
// storage path can be recovered from the URL and signed), or — in
// principle, though nothing in this app currently writes one — some other
// external URL entirely, which must be left completely alone.
//
// Returns: the bare path to sign (unchanged input if it was already bare;
// the extracted path if it was our own bucket's legacy URL), or `null` if
// the value is a full URL that does NOT match this project's own bucket
// shape — the caller's signal to pass the original value through
// untouched, exactly like today, rather than mis-parsing an unrelated URL.
function extractStoragePath(value) {
    if (!FULL_URL_PATTERN.test(value)) return value;
    if (!value.startsWith(PUBLIC_OBJECT_PREFIX)) return null;

    return decodeURIComponent(value.slice(PUBLIC_OBJECT_PREFIX.length));
}

export async function resolveImageUrl(value) {
    if (!value) return "";

    const path = extractStoragePath(value);
    if (path === null) return value;

    return getMediaSignedUrl(path).catch(() => "");
}

// Batch counterpart to getMediaSignedUrl — one Storage request for any
// number of paths (createSignedUrls), instead of resolveBuildImageUrls/
// resolveAvatarUrls previously firing one request per item via
// Promise.all. Paths are deduplicated before signing (no reason to sign
// the same path twice in one call), and the returned Map lets every
// caller look its own paths back up in whatever order it needs — the
// signing request's own (deduplicated) order never leaks into a
// caller's output order.
export async function getMediaSignedUrls(storagePaths) {
    const uniquePaths = [...new Set(storagePaths.filter(Boolean))];

    if (!uniquePaths.length) return new Map();

    const { data, error } = await supabase
        .storage
        .from(BUCKET)
        .createSignedUrls(uniquePaths, SIGNED_URL_EXPIRY_SECONDS);

    if (error) throw error;

    // Per-path failures (e.g. a since-deleted object) come back as an
    // item-level `error`, not a thrown exception — resolved to "" here so
    // every caller keeps the same fail-soft contract getMediaSignedUrl's
    // individual .catch(() => "") callers already relied on.
    return new Map(data.map(item => [item.path, item.error ? "" : item.signedUrl]));
}

// Bulk counterpart for list/card rendering (Home, Explore, Workshop,
// Dashboard, Profile): resolves every build's image_url up front so the
// shared card renderers (BlueprintCard, BlueprintFeed, etc.) can stay
// synchronous and unchanged — they just receive builds whose image_url is
// already a usable src by the time they run. The output array is built by
// mapping over `builds` in its original order, so deduplicating paths for
// the signing request itself never affects the order builds come back in.
export async function resolveBuildImageUrls(builds) {
    const pathByBuild = builds.map(build => ({
        build,
        path: build.image_url ? extractStoragePath(build.image_url) : null
    }));

    const pathsNeedingSigning = pathByBuild
        .filter(({ build, path }) => build.image_url && path)
        .map(({ path }) => path);

    const urlByPath = await getMediaSignedUrls(pathsNeedingSigning).catch(() => new Map());

    return pathByBuild.map(({ build, path }) => {
        if (!build.image_url) return { ...build, image_url: "" };
        // Unrecognized external URL (not this bucket's own) — unchanged,
        // same as before Migration B.
        if (!path) return build;

        return { ...build, image_url: urlByPath.get(path) || "" };
    });
}

// profiles.avatar_path (a storage path, resolved to a signed URL) is
// preferred; profiles.avatar_url (a legacy ready-to-use URL, used as-is)
// is the fallback for a profile that hasn't re-uploaded an avatar since
// Milestone 5A — see supabase/migrations/0003_profile_avatar_path.sql.
export async function resolveAvatarUrl(profile) {
    if (profile?.avatar_path) {
        return getMediaSignedUrl(profile.avatar_path).catch(() => "");
    }

    if (!profile?.avatar_url) return "";

    // avatar_url predates avatar_path (see 0003_profile_avatar_path.sql) —
    // a profile that hasn't re-uploaded since may still hold this bucket's
    // own legacy public URL, same compatibility treatment as image_url.
    const path = extractStoragePath(profile.avatar_url);
    if (path === null) return profile.avatar_url;

    return getMediaSignedUrl(path).catch(() => "");
}

// Batch counterpart to resolveAvatarUrl — for rendering a list of avatars
// (comments, follow lists) in one Storage request instead of one per
// avatar. Returns a Map keyed by profile.id so callers can look up each
// profile's resolved URL in whatever order they render — same
// order-preservation contract as resolveBuildImageUrls.
export async function resolveAvatarUrls(profiles) {
    // Two independent sources of a signable path per profile: avatar_path
    // (the normal case since Milestone 5A) and, for a profile that hasn't
    // re-uploaded since, a legacy avatar_url that may itself be this
    // bucket's own now-unfetchable public URL — extracted the same way
    // image_url is, and batched into the same single signing request.
    const legacyPathByProfileId = new Map();

    profiles.forEach(profile => {
        if (profile?.avatar_path || !profile?.avatar_url) return;

        const path = extractStoragePath(profile.avatar_url);
        if (path) legacyPathByProfileId.set(profile.id, path);
    });

    const pathsNeedingSigning = [
        ...profiles.map(profile => profile?.avatar_path).filter(Boolean),
        ...legacyPathByProfileId.values()
    ];

    const urlByPath = await getMediaSignedUrls(pathsNeedingSigning).catch(() => new Map());

    return new Map(profiles.map(profile => {
        if (profile?.avatar_path) {
            return [profile.id, urlByPath.get(profile.avatar_path) || ""];
        }

        const legacyPath = legacyPathByProfileId.get(profile?.id);
        if (legacyPath) {
            return [profile.id, urlByPath.get(legacyPath) || ""];
        }

        // No avatar_path, and avatar_url is either empty or an
        // unrecognized external URL — unchanged, same as before
        // Migration B.
        return [profile?.id, profile?.avatar_url || ""];
    }));
}

export async function getRevisionMedia(revisionId) {
    const { data, error } = await supabase
        .from("revision_media")
        .select("*")
        .eq("revision_id", revisionId)
        .order("display_order", { ascending: true });

    if (error) throw error;

    return data || [];
}

export async function getDraftMedia(draftId) {
    const { data, error } = await supabase
        .from("project_media")
        .select("*")
        .eq("draft_id", draftId)
        .order("display_order", { ascending: true });

    if (error) throw error;

    return data || [];
}

export async function addMedia({ id, draftId, storagePath, displayOrder, altText = "" }) {
    const { data, error } = await supabase
        .from("project_media")
        .insert([{
            id,
            draft_id: draftId,
            storage_path: storagePath,
            display_order: displayOrder,
            alt_text: altText
        }])
        .select()
        .single();

    if (error) throw error;

    return data;
}

// Removes both the database record and the underlying storage object —
// deleting only the row would leave an orphaned file in the bucket forever.
export async function deleteMedia(media) {
    const { error: storageError } = await supabase
        .storage
        .from(BUCKET)
        .remove([media.storage_path]);

    if (storageError) throw storageError;

    const { error } = await supabase
        .from("project_media")
        .delete()
        .eq("id", media.id);

    if (error) throw error;
}
