import { getNewestBuilds } from "../repositories/buildRepository.js";
import { getProfilesByIds } from "../repositories/profileRepository.js";
import { resolveBuildImageUrls } from "../repositories/mediaRepository.js";
import { escapeAttribute } from "../utils/escapeHtml.js";
import { formatCategory } from "../utils/formatCategory.js";

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
