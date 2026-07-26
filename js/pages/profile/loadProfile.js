import { getPublicProfile, getProfileBuilds } from "../../repositories/profileRepository.js";
import { getCommentCountForBuilds } from "../../repositories/commentRepository.js";
import { resolveBuildImageUrls } from "../../repositories/mediaRepository.js";
import { getCurrentUser } from "../../core/auth.js";
import { renderProfile, renderProfileError } from "./renderProfile.js";

export async function loadProfile() {
    const params = new URLSearchParams(window.location.search);
    const userId = params.get("user");

    if (!userId) {
        window.location.href = "../index.html";
        return;
    }

    // Primary: the profile itself and its published projects — this IS
    // the page. A failure here means there's nothing real to show.
    let profile;
    let builds;

    try {
        profile = await getPublicProfile(userId);
        const rawBuilds = await getProfileBuilds(userId);

        // Every card on this page is this same profile's own project —
        // attach it once here rather than a per-build lookup. Previously
        // this was never attached at all, so BlueprintCard fell through to
        // its "Unknown Creator" fallback on every card here.
        builds = (await resolveBuildImageUrls(rawBuilds)).map(build => ({
            ...build,
            profiles: profile
        }));
    } catch (error) {
        console.error("Profile load error:", error);
        renderProfileError();
        return;
    }

    // Secondary: a pure cosmetic stat (Comments Received). A failure here
    // shouldn't take down an otherwise-successfully-loaded profile — it
    // just falls back to 0, same as the trigger-maintained counters
    // elsewhere in this app default to 0 rather than blocking a page.
    let commentCount = 0;

    try {
        commentCount = await getCommentCountForBuilds(builds.map(build => build.id));
    } catch (error) {
        console.error("Comment count load error:", error);
    }

    // Secondary: who's viewing the page — needed to decide whether a
    // Follow control makes sense at all (never shown on your own
    // profile) and, if so, whether it starts in the followed state. A
    // failure here degrades to "treated as signed out," not a broken page.
    let currentUser = null;

    try {
        currentUser = await getCurrentUser();
    } catch (error) {
        console.error("Current user load error:", error);
    }

    await renderProfile({ profile, builds, commentCount, currentUser });
}
