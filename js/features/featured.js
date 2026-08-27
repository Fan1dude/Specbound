import { getNewestBuilds } from "../repositories/buildRepository.js";
import { getProfilesByIds } from "../repositories/profileRepository.js";
import { resolveBuildImageUrls } from "../repositories/mediaRepository.js";
import { escapeAttribute } from "../utils/escapeHtml.js";
import { formatCategory } from "../utils/formatCategory.js";
import { getBuildStage } from "../utils/buildStage.js";
import { hydrateProgressBars } from "../utils/progressBar.js";

let featuredBuilds = [];
// Every builder name this carousel will ever need is already known once
// featuredBuilds loads (it only ever cycles through the same 5 builds) —
// resolved once, up front, and reused for the carousel's whole lifetime
// instead of re-fetching a profile on every slide change (previously:
// every 6-second auto-advance and every manual prev/next click, forever,
// for as long as the tab stayed open). Scoped to this module/carousel
// only — not a general-purpose or cross-page cache.
let builderNameById = new Map();
let currentIndex = 0;
let slideInterval = null;

async function loadFeaturedBuilds() {
    try {
        const builds = await getNewestBuilds(5);

        if (!builds || builds.length === 0) return;

        featuredBuilds = await resolveBuildImageUrls(builds);

        const uniqueUserIds = [...new Set(featuredBuilds.map(build => build.user_id).filter(Boolean))];
        const profiles = await getProfilesByIds(uniqueUserIds);

        builderNameById = new Map(profiles.map(profile => [profile.id, profile.username || "Unknown Builder"]));

        showBuild(0);
        startCarousel();
    } catch (error) {
        console.error("Featured Error:", error.message);
    }
}

function getBuilderName(userId) {
    if (!userId) return "Unknown Builder";

    return builderNameById.get(userId) || "Unknown Builder";
}

function showBuild(index) {
    const build = featuredBuilds[index];
    const builderName = getBuilderName(build.user_id);

    document.getElementById("featuredTitle").textContent = build.title;
    document.getElementById("featuredCategory").textContent = formatCategory(build.category);
    const creatorLink = document.getElementById("featuredCreator");

    creatorLink.textContent = `Built by ${builderName}`;
    creatorLink.href = `pages/profile.html?user=${build.user_id}`;
    document.getElementById("featuredUpdated").textContent = "Recently Updated";

    document.getElementById("featuredLink").href =
        `pages/build/build.html?slug=${build.slug}`;

    document.getElementById("featuredImage").innerHTML = build.image_url
        ? `<img src="${escapeAttribute(build.image_url)}" alt="${escapeAttribute(build.title)}" loading="lazy" decoding="async">`
        : `<div class="featured-placeholder">No Image Uploaded</div>`;

    // Lifecycle badge -- same shared helper BlueprintCard.js uses, so this
    // carousel's label/color never drifts from what every card surface
    // already shows for the same build.status value.
    const stage = getBuildStage(build.status);
    const stageEl = document.getElementById("featuredStage");

    if (stageEl) {
        stageEl.textContent = stage.label;
        stageEl.className = `featured-label ${stage.className}`;
    }

    // Progress -- standard CSP-safe data-progress/hydrateProgressBars
    // pattern (js/utils/progressBar.js), not an inline style mutation.
    // Clamped the same way BlueprintCard.js's own clampProgress() does.
    const progress = clampProgress(build.progress);

    document.getElementById("featuredProgress").textContent = `${progress}%`;

    const progressTrack = document.getElementById("featuredProgressBar");
    const progressFill = document.getElementById("featuredProgressFill");

    if (progressTrack && progressFill) {
        progressTrack.setAttribute("aria-valuenow", String(progress));
        progressFill.dataset.progress = String(progress);
        hydrateProgressBars(progressTrack);
    }

    document.getElementById("featuredVersion").textContent =
        `Current Version ${normalizeVersion(build.version)}`;
}

// Mirrors BlueprintCard.js's own clampProgress()/normalizeVersion() —
// small, pure, single-purpose helpers already duplicated per-file
// throughout this codebase (renderBuild.js has its own equivalents too),
// not extracted here since only the status LABEL mapping was called out
// for sharing.
function clampProgress(value) {
    const number = Number(value || 0);

    if (!Number.isFinite(number)) return 0;

    return Math.min(100, Math.max(0, Math.round(number)));
}

function normalizeVersion(version) {
    if (!version) return "v1.0";

    const value = String(version);
    return value.toLowerCase().startsWith("v")
        ? value
        : `v${value}`;
}

function nextBuild() {
    currentIndex = (currentIndex + 1) % featuredBuilds.length;
    showBuild(currentIndex);
}

function previousBuild() {
    currentIndex = (currentIndex - 1 + featuredBuilds.length) % featuredBuilds.length;
    showBuild(currentIndex);
}

function startCarousel() {
    if (slideInterval) clearInterval(slideInterval);
    slideInterval = setInterval(nextBuild, 6000);
}

const left = document.getElementById("prevFeatured");
const right = document.getElementById("nextFeatured");

if (left && right) {
    left.onclick = () => {
        previousBuild();
        startCarousel();
    };

    right.onclick = () => {
        nextBuild();
        startCarousel();
    };

    loadFeaturedBuilds();
}
