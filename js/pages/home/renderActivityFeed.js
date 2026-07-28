import { getActivityFeed } from "../../repositories/activityRepository.js";
import { getBuildsByIds } from "../../repositories/buildRepository.js";
import { attachBuildProfiles } from "../../repositories/profileRepository.js";
import { resolveBuildImageUrls } from "../../repositories/mediaRepository.js";
import { BlueprintCard } from "../../components/BlueprintCard.js";
import { hydrateProgressBars } from "../../utils/progressBar.js";
import { cardGridSkeleton } from "../../utils/skeletons.js";
import { formatRelativeTime } from "../../utils/notificationFormat.js";
import { escapeHtml } from "../../utils/escapeHtml.js";

const PAGE_SIZE = 20;

// currentUser is whoever is viewing the home page (or null if signed
// out) — decides the default tab and whether Following is offered at
// all. BlueprintCard itself is never modified — each activity wraps the
// unmodified card in a small label, same "wrap, don't touch" pattern as
// Saved Projects (6E).
export async function renderActivityFeed(currentUser) {
    const gridEl = document.getElementById("activityFeedGrid");
    const loadMoreBtn = document.getElementById("activityFeedLoadMore");
    const followingTab = document.getElementById("activityFeedFollowingTab");
    const exploreTab = document.getElementById("activityFeedExploreTab");

    if (!gridEl) return;

    if (currentUser && followingTab) {
        followingTab.hidden = false;
    }

    let scope = currentUser ? "following" : "explore";
    let activities = [];
    let hasMore = false;

    setActiveTab(scope);

    if (followingTab) {
        followingTab.addEventListener("click", () => switchScope("following"));
    }

    if (exploreTab) {
        exploreTab.addEventListener("click", () => switchScope("explore"));
    }

    if (loadMoreBtn) {
        loadMoreBtn.addEventListener("click", loadNextPage);
    }

    await loadFirstPage();

    async function switchScope(nextScope) {
        if (nextScope === scope) return;

        scope = nextScope;
        setActiveTab(scope);
        await loadFirstPage();
    }

    async function loadFirstPage() {
        gridEl.setAttribute("role", "status");
        gridEl.setAttribute("aria-live", "polite");
        gridEl.setAttribute("aria-label", "Loading activity");
        gridEl.innerHTML = cardGridSkeleton();
        if (loadMoreBtn) loadMoreBtn.hidden = true;

        try {
            const page = await getActivityFeed({ scope, limit: PAGE_SIZE });

            activities = await enrich(page);
            hasMore = page.length === PAGE_SIZE;

            renderGrid();
        } catch (error) {
            console.error("Activity feed load error:", error);
            gridEl.innerHTML = `<p class="text-secondary">Could not load the activity feed. Try refreshing the page.</p>`;
        }
    }

    async function loadNextPage() {
        loadMoreBtn.disabled = true;
        loadMoreBtn.textContent = "Loading...";

        try {
            const last = activities[activities.length - 1];

            const page = await getActivityFeed({
                scope,
                beforeCreatedAt: last?.created_at,
                beforeId: last?.id,
                limit: PAGE_SIZE
            });

            const nextActivities = await enrich(page);

            activities = [...activities, ...nextActivities];
            hasMore = page.length === PAGE_SIZE;

            // Appends only the newly-fetched page instead of re-rendering
            // every previously-loaded card — BlueprintCard is the
            // heaviest markup in the app, so rebuilding the whole grid on
            // every Load More click gets more expensive the longer a
            // session's been open. Cards have no per-card listeners
            // (their <a> links are plain navigation), so a simple
            // insertAdjacentHTML append is enough — nothing to re-bind.
            gridEl.insertAdjacentHTML("beforeend", nextActivities.map(renderCard).join(""));

            if (loadMoreBtn) loadMoreBtn.hidden = !hasMore;
        } catch (error) {
            console.error("Activity feed load more error:", error);
        } finally {
            loadMoreBtn.disabled = false;
            loadMoreBtn.textContent = "Load More";
        }
    }

    // Batch-enriches a page of raw activity rows (build_id/user_id only)
    // into full, renderable builds in three queries total, not one per
    // row — same pattern as everywhere else in this app. A build that's
    // since gone private (or, in a rare race, been deleted) simply won't
    // come back from getBuildsByIds — dropped silently rather than
    // rendered as a broken card, same handling as Saved Projects (6E).
    async function enrich(page) {
        if (!page.length) return [];

        const uniqueBuildIds = [...new Set(page.map(activity => activity.build_id))];
        const rawBuilds = await getBuildsByIds(uniqueBuildIds);
        const builds = await resolveBuildImageUrls(await attachBuildProfiles(rawBuilds));
        const buildsById = new Map(builds.map(build => [build.id, build]));

        return page
            .map(activity => ({ ...activity, build: buildsById.get(activity.build_id) }))
            .filter(activity => activity.build);
    }

    function renderGrid() {
        if (!activities.length) {
            gridEl.innerHTML = scope === "following"
                ? `
                    <div class="empty-state">
                        <h3>Your Following feed is empty.</h3>
                        <p>Follow some builders to see their latest projects and updates here.</p>
                        <a class="btn btn-primary" href="pages/explore.html">Explore Projects</a>
                    </div>
                `
                : `
                    <div class="empty-state">
                        <h3>No activity yet.</h3>
                        <p>Published projects and updates will show up here.</p>
                    </div>
                `;

            if (loadMoreBtn) loadMoreBtn.hidden = true;
            return;
        }

        gridEl.innerHTML = activities.map(renderCard).join("");
        hydrateProgressBars(gridEl);

        if (loadMoreBtn) loadMoreBtn.hidden = !hasMore;
    }

    function renderCard(activity) {
        const label = activity.activity_type === "new_project" ? "New Project" : "New Update";

        return `
            <div class="activity-feed-card">
                <p class="activity-feed-label">${escapeHtml(label)} &middot; ${escapeHtml(formatRelativeTime(activity.created_at))}</p>
                ${BlueprintCard(activity.build, "")}
            </div>
        `;
    }

    function setActiveTab(activeScope) {
        [followingTab, exploreTab].forEach(tab => {
            if (!tab) return;

            const isActive = tab.dataset.scope === activeScope;

            tab.classList.toggle("is-active", isActive);
            tab.setAttribute("aria-selected", String(isActive));
        });
    }
}

