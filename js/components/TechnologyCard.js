import { icon } from "../utils/icons.js";

// CSP compatibility: --category-accent/--category-icon used to be set via
// an inline style="..." attribute in the returned markup. A strict
// Content-Security-Policy with no 'unsafe-inline' in style-src silently
// blocks that (confirmed live during Milestone 10 implementation — the
// attribute renders in the DOM but the browser never applies it, so the
// custom properties resolved to nothing and every card lost its accent
// color and icon mask). Per-category values are carried as data
// attributes instead and applied via the CSSOM (element.style.setProperty,
// which style-src does not restrict — only the HTML style attribute and
// .cssText are) by hydrateTechnologyCards() below, which every caller
// must run once after inserting this markup.
export function TechnologyCard(category, pathPrefix = "") {
    const iconPath = new URL(
        `${pathPrefix}assets/icons/categories/${category.icon}`,
        document.baseURI
    ).href;

    return `
        <a
            class="technology-card card"
            href="${pathPrefix}pages/categories/${category.slug}.html"
            data-category-accent="${category.accent}"
            data-category-icon="${iconPath}"
        >
            <div class="technology-card-icon" aria-hidden="true">
                <span class="technology-card-symbol"></span>
            </div>

            <div class="technology-card-body">
                <h3>${category.title}</h3>
                <p>${category.subtitle}</p>
            </div>

            <div class="technology-card-footer">
                <span>Explore</span>
                ${icon("arrow-right", 16)}
            </div>
        </a>
    `;
}

// Call once after inserting TechnologyCard markup into the DOM (e.g. right
// after an innerHTML assignment) — applies the per-category custom
// properties that can no longer be embedded inline.
export function hydrateTechnologyCards(container) {
    container.querySelectorAll("[data-category-accent]").forEach(el => {
        el.style.setProperty("--category-accent", el.dataset.categoryAccent);
        el.style.setProperty("--category-icon", `url('${el.dataset.categoryIcon}')`);
    });
}
