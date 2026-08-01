import { getPublicProfile, getProfileBuilds } from "../../repositories/profileRepository.js";
import { getCommentCountForBuilds } from "../../repositories/commentRepository.js";
import { getRecentBuilderRevisions } from "../../repositories/revisionRepository.js";
import { resolveBuildImageUrls } from "../../repositories/mediaRepository.js";
import { getCurrentUser } from "../../core/auth.js";
import { renderProfile, renderProfileError } from "./renderProfile.js";
import { buildBuilderJourney } from "./buildBuilderJourney.js";
import { cardGridSkeleton, listSkeleton } from "../../utils/skeletons.js";

export async function loadProfile() {
    const params = new URLSearchParams(window.location.search);
    const userId = params.get("user");

    if (!userId) {
        window.location.href = "../index.html";
        return;
    }

    showLoadingSkeletons();

    // Primary: the profile itself and its published projects — this IS
    // the page. A failure here means there's nothing real to show.
    let profile;
    let builds;

    try {
        profile = await getPublicProfile(userId);
        const rawBuilds = await getProfileBuilds(userId);

        // Every card on this page is this same profile's own project —
        // attach it once here rather than a per-build lookup.
        builds = (await resolveBuildImageUrls(rawBuilds)).map(build => ({
            ...build,
            profiles: profile
        }));
    } catch (error) {
        console.error("Profile load error:", error);
        renderProfileError();
        return;
    }

    // Secondary: pure cosmetic/supplementary data. A failure in any of
    // these shouldn't take down an otherwise-successfully-loaded profile
    // — each falls back to an empty/default value, same as the
    // trigger-maintained counters elsewhere in this app.
    let commentCount = 0;

    try {
        commentCount = await getCommentCountForBuilds(builds.map(build => build.id));
    } catch (error) {
        console.error("Comment count load error:", error);
    }

    let currentUser = null;

    try {
        currentUser = await getCurrentUser();
    } catch (error) {
        console.error("Current user load error:", error);
    }

    // Builder Journey (spec §17.3/§17.4) — a capped recent-revisions
    // fetch, synthesized into a curated top-10 timeline. Only worth
    // fetching when there's at least one public build; a failure here
    // just means the Journey section is omitted, not a broken page.
    let journeyEvents = [];

    if (builds.length) {
        try {
            const revisions = await getRecentBuilderRevisions(userId);
            journeyEvents = buildBuilderJourney(builds, revisions);
        } catch (error) {
            console.error("Builder journey load error:", error);
        }
    }

    await renderProfile({ profile, builds, commentCount, currentUser, journeyEvents });
}

// Both sections start `hidden` in the static HTML (spec §7 — a
// conditional section is omitted, not shown empty, until we know
// whether it has content) and the real render functions later decide
// their true final visibility. Unhiding them here just for the loading
// state is safe: if there turns out to be nothing to show, renderProjectGallery()/
// renderBuilderJourney() re-hide them once the real data resolves.
function showLoadingSkeletons() {
    const galleryEl = document.getElementById("profileGallery");
    const gridEl = document.getElementById("profileBuilds");
    if (galleryEl && gridEl) {
        galleryEl.hidden = false;
        gridEl.innerHTML = cardGridSkeleton(6);
    }

    const journeyEl = document.getElementById("profileJourney");
    if (journeyEl) {
        journeyEl.hidden = false;
        journeyEl.innerHTML = listSkeleton(4);
    }
}
