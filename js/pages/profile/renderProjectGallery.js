import { BlueprintCard } from "../../components/BlueprintCard.js";
import { hydrateProgressBars } from "../../utils/progressBar.js";
import { escapeHtml, escapeAttribute } from "../../utils/escapeHtml.js";
import { getTechnology } from "../../config/technologies/index.js";

// The rest of a builder's published work, below Featured Project — see
// spec §4/§12. A user-initiated "Load more" button, not infinite scroll:
// the brand explicitly avoids engagement-feed framing ("not Instagram"),
// so more content only appears on a deliberate click, never
// auto-loading. `builds` is already fully fetched by the caller
// (getProfileBuilds) — filtering/sorting/paging here is entirely
// client-side over data already in memory, no extra queries.
const PAGE_SIZE = 9;

const SORT_OPTIONS = [
    { value: "newest", label: "Newest" },
    { value: "oldest", label: "Oldest" },
    { value: "views", label: "Most Viewed" },
    { value: "likes", label: "Most Liked" }
];

export function renderProjectGallery(builds, pathPrefix = "../") {
    const section = document.getElementById("profileGallery");

    if (!section) return;

    if (!builds.length) {
        section.hidden = true;
        return;
    }

    section.hidden = false;

    const categories = [...new Set(builds.map(build => build.category))]
        .map(id => getTechnology(id))
        .filter(Boolean);

    const state = { category: "all", sort: "newest", visibleCount: PAGE_SIZE };

    // Declared before the first rerenderGrid() call below — rerenderGrid
    // is a hoisted function declaration, but it still can't reference
    // these `const` bindings before this line actually runs (temporal
    // dead zone), so the lookups must happen first, not after.
    const filtersEl = document.getElementById("profileGalleryFilters");
    const sortEl = document.getElementById("profileGallerySort");
    const loadMoreEl = document.getElementById("profileGalleryLoadMore");

    renderFilters(categories, state);
    renderSort(state);
    rerenderGrid();

    if (filtersEl) {
        filtersEl.addEventListener("click", event => {
            const pill = event.target.closest(".gallery-filter-pill");
            if (!pill) return;

            state.category = pill.dataset.category;
            state.visibleCount = PAGE_SIZE;
            renderFilters(categories, state);
            rerenderGrid();
        });
    }

    if (sortEl) {
        sortEl.addEventListener("change", () => {
            state.sort = sortEl.value;
            state.visibleCount = PAGE_SIZE;
            rerenderGrid();
        });
    }

    if (loadMoreEl) {
        loadMoreEl.addEventListener("click", () => {
            state.visibleCount += PAGE_SIZE;
            rerenderGrid();
        });
    }

    function rerenderGrid() {
        const filtered = state.category === "all"
            ? builds
            : builds.filter(build => build.category === state.category);
        const sorted = sortBuilds(filtered, state.sort);
        const visible = sorted.slice(0, state.visibleCount);

        const grid = document.getElementById("profileBuilds");
        if (grid) {
            grid.innerHTML = visible.map(build => BlueprintCard(build, pathPrefix)).join("");
            hydrateProgressBars(grid);
        }

        if (loadMoreEl) {
            loadMoreEl.hidden = visible.length >= sorted.length;
        }
    }
}

function renderFilters(categories, state) {
    const el = document.getElementById("profileGalleryFilters");

    if (!el || categories.length < 2) {
        if (el) el.innerHTML = "";
        return;
    }

    const pills = [{ id: "all", title: "All" }, ...categories.map(t => ({ id: t.id, title: t.title }))];

    el.innerHTML = pills
        .map(technology => `
            <button
                type="button"
                class="gallery-filter-pill${state.category === technology.id ? " active" : ""}"
                data-category="${escapeAttribute(technology.id)}"
                aria-pressed="${state.category === technology.id}"
            >
                ${escapeHtml(technology.title)}
            </button>
        `)
        .join("");
}

function renderSort(state) {
    const el = document.getElementById("profileGallerySort");

    if (!el) return;

    el.innerHTML = SORT_OPTIONS
        .map(option => `<option value="${option.value}"${option.value === state.sort ? " selected" : ""}>${escapeHtml(option.label)}</option>`)
        .join("");
}

function sortBuilds(builds, sort) {
    const sorted = builds.slice();

    switch (sort) {
        case "oldest":
            return sorted.sort((a, b) => new Date(a.created_at) - new Date(b.created_at));
        case "views":
            return sorted.sort((a, b) => Number(b.views || 0) - Number(a.views || 0));
        case "likes":
            return sorted.sort((a, b) => Number(b.likes_count || 0) - Number(a.likes_count || 0));
        case "newest":
        default:
            return sorted.sort((a, b) => new Date(b.created_at) - new Date(a.created_at));
    }
}
