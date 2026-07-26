import { requireAuth } from "../../core/auth.js";
import { getProfile } from "../../repositories/profileRepository.js";
import { getMyBuilds, getMyRevisionCount } from "../../repositories/dashboardRepository.js";
import { resolveBuildImageUrls } from "../../repositories/mediaRepository.js";
import { renderDashboard } from "./renderDashboard.js";
import { renderErrorState } from "../../utils/listState.js";

export async function loadDashboard() {
    const user = await requireAuth("../pages/login.html");

    if (!user) return;

    // This page has no meaningfully "secondary" data — profile, builds,
    // and revision count are all part of the same primary content (unlike
    // Workshop, which has genuinely independent sections). A failure
    // anywhere here means there's nothing real to show, so it gets one
    // page-level error state instead of a per-field fallback that would
    // silently look like "you have nothing yet."
    try {
        const profile = await getProfile(user.id);
        const builds = await resolveBuildImageUrls(await getMyBuilds(user.id));
        const revisionCount = await getMyRevisionCount(user.id);

        renderDashboard({
            profile,
            builds,
            revisionCount
        });
    } catch (error) {
        console.error("Dashboard load error:", error);
        showDashboardUnavailable();
    }
}

function showDashboardUnavailable() {
    const buildsContainer = document.getElementById("dashboardBuilds");

    renderErrorState(buildsContainer, {
        message: "Could not load your Workshop. Try again.",
        // Retries the whole primary load — nothing on this page succeeded
        // yet in this failure path, so there's no already-successful
        // primary data this could wastefully re-fetch.
        onRetry: () => loadDashboard()
    });

    const stats = document.getElementById("dashboardStats");

    if (stats) stats.innerHTML = "";
}
