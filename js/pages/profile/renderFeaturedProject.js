import { escapeHtml, escapeAttribute } from "../../utils/escapeHtml.js";
import { formatCategory } from "../../utils/formatCategory.js";
import { icon } from "../../utils/icons.js";

// Behance-style hero treatment for one project — see spec §4.1/§10.2. A
// larger-format sibling of BlueprintCard, not a variant prop on it: the
// layout (big image, more copy visible, a "Featured" badge) is different
// enough that overloading BlueprintCard would complicate its simpler job.
// `build` is the result of resolveFeaturedBuild() — the caller decides
// whether to call this at all (the section is omitted entirely, not
// rendered empty, when there's no eligible build — spec §7).
export function renderFeaturedProject(build, pathPrefix = "../") {
    const el = document.getElementById("profileFeatured");

    if (!el) return;

    const buildUrl = `${pathPrefix}pages/build/build.html?slug=${encodeURIComponent(build.slug || "")}`;
    const fallbackImage = new URL(`${pathPrefix}assets/placeholders/default-cover.svg`, document.baseURI).href;
    const imageUrl = build.image_url || fallbackImage;

    el.innerHTML = `
        <div class="section-heading">
            <p class="hero-badge">Featured</p>
            <h2>Featured Project</h2>
        </div>

        <a class="featured-project-image" href="${buildUrl}" aria-label="View ${escapeHtml(build.title || "Untitled project")}">
            <img src="${escapeAttribute(imageUrl)}" alt="${escapeAttribute(build.title || "Featured project cover")}" loading="eager">
        </a>

        <div class="featured-project-body">
            <span class="badge">${escapeHtml(formatCategory(build.category))}</span>

            <h3 class="featured-project-title">
                <a href="${buildUrl}">${escapeHtml(build.title || "Untitled project")}</a>
            </h3>

            <p class="featured-project-summary">
                ${escapeHtml(build.description || "No project summary has been added yet.")}
            </p>

            <a href="${buildUrl}" class="btn btn-secondary featured-project-cta">
                View Project ${icon("arrow-right", 16)}
            </a>
        </div>
    `;
}
