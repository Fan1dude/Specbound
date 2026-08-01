import { CATEGORIES } from "../../config/categories.js";
import { getBuildsByCategory } from "../../repositories/buildRepository.js";
import { attachBuildProfiles } from "../../repositories/profileRepository.js";
import { resolveBuildImageUrls } from "../../repositories/mediaRepository.js";
import { BlueprintFeed } from "../../components/BlueprintFeed.js";
import { escapeHtml } from "../../utils/escapeHtml.js";

// One shared renderer for all 6 category landing pages (previously 6
// byte-for-byte identical bespoke templates — confirmed during the
// architecture research pass). Each HTML file only needs its unique
// <title>/meta (kept for SEO) plus <main id="main" data-category="...">;
// everything inside main is built here from js/config/categories.js.
export async function renderCategoryPage(pathPrefix = "../../") {
    const main = document.getElementById("main");
    if (!main) return;

    const categoryId = main.dataset.category;
    const category = CATEGORIES.find(entry => entry.id === categoryId);

    if (!category) {
        console.error(`renderCategoryPage: unknown category "${categoryId}"`);
        return;
    }

    renderShell(main, category, pathPrefix);

    try {
        const builds = await resolveBuildImageUrls(
            await attachBuildProfiles(await getBuildsByCategory(category.id, 6))
        );

        BlueprintFeed({
            container: "#categoryFeaturedGrid",
            builds,
            pathPrefix,
            layout: "grid",
            emptyTitle: `No ${category.title} Blueprints Yet`,
            // Phrased to sidestep the "a" vs "an" agreement problem a
            // template literal can't solve generically — "Arduino" needs
            // "an", every other category title needs "a".
            emptyDescription: `Publish the first ${category.title} project on Specbound.`,
            emptyIcon: "document"
        });
    } catch (error) {
        console.error("Category featured builds error:", error);

        BlueprintFeed({
            container: "#categoryFeaturedGrid",
            builds: [],
            pathPrefix,
            layout: "grid",
            emptyTitle: "Unable to Load Blueprints",
            emptyDescription: "Something went wrong while loading featured projects.",
            emptyIcon: "warning"
        });
    }
}

function renderShell(main, category, pathPrefix) {
    main.classList.add("category-page");

    const exploreUrl =
        `${pathPrefix}pages/explore.html?category=${encodeURIComponent(category.id)}`;

    main.innerHTML = `
        <header class="category-hero">
            <p class="hero-badge">TECHNOLOGY</p>
            <h1>${escapeHtml(category.title)}</h1>
            <p class="category-hero-subtitle">${escapeHtml(category.subtitle)}</p>
            <p class="category-hero-description">${escapeHtml(category.description || "")}</p>
        </header>

        ${category.highlights?.length ? `
            <ul class="category-highlights">
                ${category.highlights.map(item => `<li>${escapeHtml(item)}</li>`).join("")}
            </ul>
        ` : ""}

        <section class="category-featured">
            <div class="category-section-heading">
                <h2>Featured ${escapeHtml(category.title)} Blueprints</h2>
            </div>

            <div id="categoryFeaturedGrid"></div>
        </section>

        <div class="category-cta">
            <a class="btn btn-primary" href="${exploreUrl}">
                Explore ${escapeHtml(category.title)}
            </a>
        </div>
    `;

    // CSP compatibility: CSSOM property assignment, not an inline style=
    // attribute — see renderSpecificationsSection.js's identical note. A
    // strict style-src with no 'unsafe-inline' silently blocks the latter.
    main.querySelector(".category-hero")
        ?.style.setProperty("--technology-accent", category.accent);
}
