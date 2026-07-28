import { loadNavbar, loadFooter } from "../../core/layout.js";
import { getNewestBuilds } from "../../repositories/buildRepository.js";
import { attachBuildProfiles } from "../../repositories/profileRepository.js";
import { resolveBuildImageUrls } from "../../repositories/mediaRepository.js";
import { BlueprintFeed } from "../../components/BlueprintFeed.js";
import {
    getTechnology,
    getTechnologyFilters
} from "../../config/technologies/index.js";
import { escapeHtml, escapeAttribute } from "../../utils/escapeHtml.js";

import {
    fuzzyMatches,
    findClosestSuggestions
} from "../../utils/fuzzySearch.js";

loadNavbar("../");
loadFooter("../");

const resultCount = document.getElementById("resultCount");
const searchInput = document.getElementById("exploreSearch");
const statusFilter = document.getElementById("statusFilter");
const sortFilter = document.getElementById("sortFilter");
const clearFilters = document.getElementById("clearFilters");
const technologyFilters =
    document.getElementById("technologyFilters");

const categoryButtons =
    document.querySelectorAll(".filter-pill");

const lifecycleButtons =
    document.querySelectorAll(".lifecycle-filter");

const searchSuggestions =
    document.getElementById("searchSuggestions");

let allBuilds = [];
let activeCategory = "all";
let activeLifecycle = "all";
let activeTechnologyFilterValues = {};

async function initExplore() {
    try {
        allBuilds = await resolveBuildImageUrls(
            await attachBuildProfiles(await getNewestBuilds(100) || [])
        );
        renderTechnologyFilters();
        render();
    } catch (error) {
        console.error("Explore page error:", error);

        BlueprintFeed({
            container: "#exploreGrid",
            builds: [],
            pathPrefix: "../",
            layout: "grid",
            emptyTitle: "Unable to Load Blueprints",
            emptyDescription:
                "Something went wrong while loading the discovery feed.",
            emptyIcon: "warning"
        });

        resultCount.textContent = "Unable to load results";
    }
}

function renderTechnologyFilters() {
    activeTechnologyFilterValues = {};

    if (activeCategory === "all") {
        technologyFilters.innerHTML = `
            <div class="filter-section technology-filter-message">
                <p>
                    Choose a technology to see its specific filters.
                </p>
            </div>
        `;
        return;
    }

    const technology = getTechnology(activeCategory);
    const filters = getTechnologyFilters(activeCategory);

    if (!technology || filters.length === 0) {
        technologyFilters.innerHTML = `
            <div class="filter-section technology-filter-message">
                <p>
                    No additional filters are available for this technology.
                </p>
            </div>
        `;
        return;
    }

    technologyFilters.innerHTML = `
        <div class="filter-section technology-filter-heading">
            <p class="filter-eyebrow">
                ${escapeHtml(technology.title)}
            </p>

            <h3>Technology Filters</h3>
        </div>

        ${filters.map(renderFilterField).join("")}
    `;

    technologyFilters
        .querySelectorAll("[data-technology-filter]")
        .forEach(input => {
            input.addEventListener("input", event => {
                const key = event.currentTarget.dataset.technologyFilter;

                activeTechnologyFilterValues[key] =
                    event.currentTarget.value;

                render();
            });
        });
}

function renderFilterField(filter) {
    if (filter.type === "select") {
        return `
            <div class="filter-section">
                <label for="technologyFilter-${filter.key}">
                    ${escapeHtml(filter.label)}
                </label>

                <select
                    id="technologyFilter-${filter.key}"
                    data-technology-filter="${escapeAttribute(filter.key)}"
                >
                    <option value="">All</option>

                    ${(filter.options || [])
                        .map(option => `
                            <option value="${escapeAttribute(option.value)}">
                                ${escapeHtml(option.label)}
                            </option>
                        `)
                        .join("")}
                </select>
            </div>
        `;
    }

    return `
        <div class="filter-section">
            <label for="technologyFilter-${filter.key}">
                ${escapeHtml(filter.label)}
            </label>

            <input
                id="technologyFilter-${filter.key}"
                type="text"
                data-technology-filter="${escapeAttribute(filter.key)}"
                placeholder="${escapeAttribute(
                    filter.placeholder || `Search ${filter.label}...`
                )}"
            >
        </div>
    `;
}

function render() {
    let builds = [...allBuilds];

    const search = searchInput.value.toLowerCase().trim();
    const status = statusFilter.value;

    if (activeCategory !== "all") {
        builds = builds.filter(
            build => build.category === activeCategory
        );
    }

    if (activeLifecycle !== "all") {
        builds = builds.filter(build =>
            matchesLifecycle(build.status, activeLifecycle)
        );
    }

    if (status !== "all") {
        builds = builds.filter(
            build => build.status === status
        );
    }

    if (search) {
    builds = rankBuildsBySearch(builds, search);
    }

    builds = builds.filter(matchesTechnologyFilters);

    if (!search) {
        sortBuilds(builds);
    }
    updateResultCount(builds.length);
    updateSearchSuggestions(search, builds.length);

    BlueprintFeed({
        container: "#exploreGrid",
        builds,
        pathPrefix: "../",
        layout: "grid",
        emptyTitle: "Nothing matches yet",
        emptyDescription:
            "Try changing or clearing some of your filters.",
        emptyIcon: "search"
    });
}

function matchesTechnologyFilters(build) {
    const specs = build.specifications || {};

    return Object.entries(activeTechnologyFilterValues)
        .every(([key, filterValue]) => {
            if (!String(filterValue || "").trim()) {
                return true;
            }

            return fuzzyMatches(
                specs[key] || "",
                filterValue
            );
        });
}

function matchesLifecycle(status, lifecycle) {
    if (lifecycle === "planning") {
        return status === "planning";
    }

    if (lifecycle === "project") {
        return (
            status === "building" ||
            status === "in_progress" ||
            status === "paused"
        );
    }

    if (lifecycle === "completed") {
        return status === "completed";
    }

    return true;
}

function sortBuilds(builds) {
    switch (sortFilter.value) {
        case "oldest":
            builds.sort(
                (a, b) =>
                    new Date(a.created_at) -
                    new Date(b.created_at)
            );
            break;

        case "az":
            builds.sort(
                (a, b) =>
                    String(a.title || "").localeCompare(
                        String(b.title || "")
                    )
            );
            break;

        case "completed":
            builds.sort(
                (a, b) =>
                    Number(b.status === "completed") -
                    Number(a.status === "completed")
            );
            break;

        case "progress":
            builds.sort(
                (a, b) =>
                    Number(b.progress || 0) -
                    Number(a.progress || 0)
            );
            break;

        case "newest":
        default:
            builds.sort(
                (a, b) =>
                    new Date(b.created_at) -
                    new Date(a.created_at)
            );
            break;
    }
}

function updateResultCount(count) {
    resultCount.textContent =
        `${count} ${count === 1 ? "Result" : "Results"}`;
}

function setActiveButton(buttons, selectedButton) {
    buttons.forEach(button => {
        const isActive = button === selectedButton;

        button.classList.toggle("active", isActive);
        button.setAttribute("aria-pressed", String(isActive));
    });
}

categoryButtons.forEach(button => {
    button.addEventListener("click", () => {
        activeCategory = button.dataset.category;

        setActiveButton(categoryButtons, button);
        renderTechnologyFilters();
        render();
    });
});

lifecycleButtons.forEach(button => {
    button.addEventListener("click", () => {
        activeLifecycle = button.dataset.lifecycle;

        setActiveButton(lifecycleButtons, button);
        render();
    });
});

[
    searchInput,
    statusFilter,
    sortFilter
].forEach(input => {
    input.addEventListener("input", render);
});

clearFilters.addEventListener("click", () => {
    activeCategory = "all";
    activeLifecycle = "all";
    activeTechnologyFilterValues = {};

    searchInput.value = "";
    statusFilter.value = "all";
    sortFilter.value = "newest";

    const allCategoryButton =
        document.querySelector(
            '.filter-pill[data-category="all"]'
        );

    const allLifecycleButton =
        document.querySelector(
            '.lifecycle-filter[data-lifecycle="all"]'
        );

    setActiveButton(categoryButtons, allCategoryButton);
    setActiveButton(lifecycleButtons, allLifecycleButton);

    renderTechnologyFilters();
    render();
});

initExplore();

function updateSearchSuggestions(query, resultTotal) {
    if (!query || resultTotal > 0) {
        hideSearchSuggestions();
        return;
    }

    const choices = collectSearchChoices();

    const suggestions = findClosestSuggestions(
        query,
        choices,
        5
    );

    if (!suggestions.length) {
        hideSearchSuggestions();
        return;
    }

    searchSuggestions.innerHTML = `
        <p>Did you mean:</p>

        <div class="search-suggestion-list">
            ${suggestions
                .map(
                    suggestion => `
                        <button
                            type="button"
                            class="search-suggestion"
                            data-suggestion="${escapeAttribute(suggestion)}"
                        >
                            ${escapeHtml(suggestion)}
                        </button>
                    `
                )
                .join("")}
        </div>
    `;

    searchSuggestions.hidden = false;

    searchSuggestions
        .querySelectorAll(".search-suggestion")
        .forEach(button => {
            button.addEventListener("click", () => {
                searchInput.value =
                    button.dataset.suggestion;

                hideSearchSuggestions();
                render();
            });
        });
}

function rankBuildsBySearch(builds, query) {
    return builds
        .map(build => ({
            build,
            score: getBuildSearchScore(build, query)
        }))
        .filter(result => result.score > 0)
        .sort((a, b) => {
            if (b.score !== a.score) {
                return b.score - a.score;
            }

            return (
                new Date(b.build.updated_at || b.build.created_at) -
                new Date(a.build.updated_at || a.build.created_at)
            );
        })
        .map(result => result.build);
}

function getBuildSearchScore(build, query) {
    const specs = build.specifications || {};

    const titleScore =
        getRelevanceScore(build.title, query) * 1.4;

    const descriptionScore =
        getRelevanceScore(build.description, query) * 0.65;

    const creatorScore =
        getRelevanceScore(
            build.profiles?.username,
            query
        ) * 0.8;

    const categoryScore =
        getRelevanceScore(build.category, query) * 0.75;

    const specificationScores = Object.values(specs)
        .filter(Boolean)
        .map(value =>
            getRelevanceScore(value, query) * 1.6
        );

    return Math.max(
        titleScore,
        descriptionScore,
        creatorScore,
        categoryScore,
        ...specificationScores,
        0
    );
}

function collectSearchChoices() {
    const values = [];

    allBuilds.forEach(build => {
        values.push(
            build.title,
            build.category,
            build.profiles?.username
        );

        Object.values(build.specifications || {})
            .forEach(value => values.push(value));
    });

    return values
        .filter(value => typeof value === "string")
        .map(value => value.trim())
        .filter(Boolean);
}

function hideSearchSuggestions() {
    searchSuggestions.hidden = true;
    searchSuggestions.innerHTML = "";
}