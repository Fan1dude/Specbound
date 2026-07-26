import { requireAuth } from "../../core/auth.js";
import { getProfile, attachBuildProfiles } from "../../repositories/profileRepository.js";
import { getMyBuilds, getMyRevisionCount } from "../../repositories/dashboardRepository.js";
import { getBuildsByIds } from "../../repositories/buildRepository.js";
import { getLatestBuildRevision } from "../../repositories/revisionRepository.js";
import { getMyDrafts } from "../../repositories/draftRepository.js";
import { getSavedBuildRefs } from "../../repositories/savedRepository.js";
import { resolveBuildImageUrls } from "../../repositories/mediaRepository.js";
import { renderWorkshop } from "./renderWorkshop.js";
import { renderErrorState } from "../../utils/listState.js";

export async function loadWorkshop() {
    const user = await requireAuth("login.html");

    if (!user) return;

    // Primary: My Projects and Continue Building are both derived from
    // this — unlike drafts/saved (genuinely independent sections), a
    // failure here means there's no primary content to show at all, so
    // it gets a real page-level error state instead of a per-section
    // fallback that would misleadingly look like "you have no projects."
    let rawBuilds;

    try {
        rawBuilds = await getMyBuilds(user.id);
    } catch (error) {
        console.error("Workshop projects load error:", error);
        showWorkshopUnavailable();
        return;
    }

    // Secondary: only used for the greeting text ("Welcome back, {name}")
    // — the profile-link href below uses user.id directly, not this.
    let profile = null;

    try {
        profile = await getProfile(user.id);
    } catch (error) {
        console.error("Workshop profile load error:", error);
    }

    // Secondary: accepted by renderWorkshop() but not currently rendered
    // anywhere on the page — isolated the same as every other secondary
    // fetch here regardless, so a failure can't take down the page.
    let revisionCount = 0;

    try {
        revisionCount = await getMyRevisionCount(user.id);
    } catch (error) {
        console.error("Workshop revision count load error:", error);
    }

    const [drafts, savedBuilds] = await Promise.all([
        // Drafts depend on the Milestone 4A migration having been applied.
        // Don't let a missing table break the rest of the workshop page —
        // treat it as "no drafts yet" and let the create/edit flow surface
        // the real error when someone actually tries to use it.
        getMyDrafts(user.id).catch(error => {
            console.error("Draft list error:", error);
            return [];
        }),
        // Same "don't let one section's failure break the rest of the
        // page" posture — but here `null` (failed) is distinguished from
        // `[]` (genuinely no saves yet) so renderWorkshop can show an
        // actual error state instead of a misleading empty one.
        loadSavedBuilds(user.id).catch(error => {
            console.error("Saved projects load error:", error);
            return null;
        })
    ]);

    // Every build here belongs to the current user (getMyBuilds() filters
    // to user_id = user.id) — attach the profile already fetched above
    // directly, rather than a batch getProfilesByIds() call for a set of
    // ids that's always just [user.id].
    const builds = await resolveBuildImageUrls(
        rawBuilds.map(build => ({ ...build, profiles: profile }))
    );
    const latestBuild = builds[0] || null;

    // Secondary: only feeds the Continue Building card's progress bar,
    // which already renders sensible defaults (0%, "v0.1") when this is
    // null — a failure here shouldn't block the rest of an otherwise-
    // successful page load.
    let latestRevision = null;

    if (latestBuild) {
        try {
            latestRevision = await getLatestBuildRevision(latestBuild.id);
        } catch (error) {
            console.error("Workshop latest revision load error:", error);
        }
    }

    renderWorkshop({
        user,
        profile,
        builds,
        revisionCount,
        drafts,
        latestBuild,
        latestRevision,
        savedBuilds
    });
}

function showWorkshopUnavailable() {
    const continueSection = document.getElementById("workshopContinue");

    renderErrorState(continueSection, {
        message: "Could not load your Workshop. Try again.",
        // Retries the whole primary load — nothing succeeded yet in this
        // failure path, so there's no already-successful primary data
        // this could wastefully re-fetch.
        onRetry: () => loadWorkshop()
    });

    const projectCount = document.getElementById("workshopProjectCount");

    if (projectCount) projectCount.textContent = "—";
}

// Saved projects are a build_id list (saved_builds) joined against builds
// and profiles client-side — no FK for PostgREST to embed through (same
// reasoning as every other build/profile pairing in this app). A saved
// build whose project has since gone private (or, in a rare race, been
// deleted) simply won't come back from getBuildsByIds — dropped silently
// rather than rendered as a broken card, per the approved Milestone 6E
// proposal.
async function loadSavedBuilds(userId) {
    const refs = await getSavedBuildRefs(userId);

    if (!refs.length) return [];

    const rawBuilds = await getBuildsByIds(refs.map(ref => ref.build_id));
    const buildsById = new Map(rawBuilds.map(build => [build.id, build]));

    // Preserve saved-order (most recently saved first, from
    // getSavedBuildRefs) rather than whatever order .in() happens to
    // return, and drop any id that didn't come back. Unlike "My
    // Projects" above, these builds can belong to many different
    // owners, so this needs the real batch attachBuildProfiles() lookup.
    const orderedBuilds = refs
        .map(ref => buildsById.get(ref.build_id))
        .filter(Boolean);

    return resolveBuildImageUrls(await attachBuildProfiles(orderedBuilds));
}
