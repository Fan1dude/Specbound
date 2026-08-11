import { loadNavbar, loadFooter } from "../../core/layout.js";
import { searchBuilds, searchBuildsByTitle, searchBuildsByCategoryIds } from "../../repositories/buildRepository.js";
import { searchProfiles, getProfilesByIds } from "../../repositories/profileRepository.js";
import { resolveBuildImageUrls, resolveAvatarUrls } from "../../repositories/mediaRepository.js";
import { searchTechnologies } from "../../config/technologies/index.js";
import { BlueprintFeed } from "../../components/BlueprintFeed.js";
import { CreatorResult } from "../../components/CreatorResult.js";
import { escapeHtml } from "../../utils/escapeHtml.js";

const DEBOUNCE_MS = 300;
const MIN_QUERY_LENGTH = 2;
const VALID_SCOPES = new Set(["all", "build", "creator", "category"]);

loadNavbar("../");
loadFooter("../");

const input = document.getElementById("searchPageInput");
const scopeSelect = document.getElementById("searchPageScope");
const buildersSection = document.getElementById("searchResultsBuilders");
const buildersList = document.getElementById("searchResultsBuildersList");
const blueprintsSection = document.getElementById("searchResultsBlueprints");
const blueprintsList = document.getElementById("searchResultsBlueprintsList");

let debounceTimer = null;

// Incremented on every search actually issued; a response is only applied
// if it's still the latest one by the time it resolves. Debouncing alone
// doesn't guarantee response *order* — two requests can still race and
// resolve out of order — this is what actually prevents a stale response
// from clobbering a newer one on screen. Shared across both the Builders
// and Blueprints sections (a single query attempt, not two independent
// counters) so a scope change or new keystroke invalidates both at once.
let latestRequestId = 0;

const params = new URLSearchParams(window.location.search);
const initialQuery = params.get("q") || "";
const initialScope = normalizeScope(params.get("scope"));

input.value = initialQuery;
scopeSelect.value = initialScope;
runQuery(initialQuery, initialScope, { updateUrl: false });

input.addEventListener("input", () => {
    clearTimeout(debounceTimer);

    debounceTimer = setTimeout(() => {
        runQuery(input.value, scopeSelect.value, { updateUrl: true });
    }, DEBOUNCE_MS);
});

// Changing scope reruns the current query immediately — no debounce,
// since this is a single deliberate action, not a stream of keystrokes.
scopeSelect.addEventListener("change", () => {
    clearTimeout(debounceTimer);
    runQuery(input.value, scopeSelect.value, { updateUrl: true });
});

function normalizeScope(value) {
    return VALID_SCOPES.has(value) ? value : "all";
}

function isActiveQuery(value) {
    return value.trim().length >= MIN_QUERY_LENGTH;
}

function updateUrlParams(trimmed, scope) {
    const url = new URL(window.location.href);

    if (trimmed) {
        url.searchParams.set("q", trimmed);
    } else {
        url.searchParams.delete("q");
    }

    url.searchParams.set("scope", scope);

    // replaceState, not pushState — every keystroke (or scope change)
    // shouldn't add a browser-history entry; the URL should just reflect
    // current state, reproducible on refresh or share.
    history.replaceState(null, "", url);
}

function runQuery(rawValue, rawScope, { updateUrl }) {
    const trimmed = rawValue.trim();
    const scope = normalizeScope(rawScope);

    if (updateUrl) {
        updateUrlParams(trimmed, scope);
    }

    // "All" shows two distinct sections (Builders, Blueprints) — never
    // mixed into one ambiguous list. Every other scope shows exactly one.
    const showBuilders = scope === "all" || scope === "creator";
    const showBlueprints = scope === "all" || scope === "build" || scope === "category";

    buildersSection.hidden = !showBuilders;
    blueprintsSection.hidden = !showBlueprints;

    if (!isActiveQuery(trimmed)) {
        latestRequestId += 1;

        if (showBuilders) showMessage(buildersList, "Type at least 2 characters to search for builders.");
        if (showBlueprints) showBlueprintsMessage("Type at least 2 characters to search.");
        return;
    }

    const requestId = ++latestRequestId;

    if (showBuilders) {
        showMessage(buildersList, "Searching...");
        loadBuilders(trimmed, requestId);
    }

    if (showBlueprints) {
        showBlueprintsMessage("Searching...");
        loadBlueprints(trimmed, scope, requestId);
    }
}

async function loadBuilders(query, requestId) {
    let results = [];

    try {
        results = await searchProfiles(query);
    } catch (error) {
        if (requestId !== latestRequestId) return;

        console.error("Creator search error:", error);
        showMessage(buildersList, "Something went wrong while searching for builders. Try again.");
        return;
    }

    if (requestId !== latestRequestId) return;

    if (!results.length) {
        showMessage(buildersList, "No matching builders.");
        return;
    }

    // Avatars are a nice-to-have, not a reason to fail the whole section —
    // a resolution failure degrades to initials instead.
    let avatarByProfileId = new Map();

    try {
        avatarByProfileId = await resolveAvatarUrls(results);
    } catch (error) {
        console.error("Creator avatar resolution error:", error);
    }

    if (requestId !== latestRequestId) return;

    buildersList.innerHTML = results
        .map(profile => CreatorResult(
            { ...profile, avatarResolvedUrl: avatarByProfileId.get(profile.id) || "" },
            "../"
        ))
        .join("");
}

async function loadBlueprints(query, scope, requestId) {
    let results = [];

    try {
        if (scope === "build") {
            results = await searchBuildsByTitle(query);
        } else if (scope === "category") {
            const matchedTechnologyIds = searchTechnologies(query).map(technology => technology.id);
            results = await searchBuildsByCategoryIds(matchedTechnologyIds);
        } else {
            results = await searchBuilds(query);
        }
    } catch (error) {
        if (requestId !== latestRequestId) return;

        console.error("Blueprint search error:", error);
        renderBlueprintFeed([], "Search Unavailable", "Something went wrong while searching. Try again.", "warning");
        return;
    }

    if (requestId !== latestRequestId) return;

    try {
        results = await attachCreators(await resolveBuildImageUrls(results));
    } catch (error) {
        if (requestId !== latestRequestId) return;

        console.error("Search result loading error:", error);
        renderBlueprintFeed([], "Search Unavailable", "Something went wrong while searching. Try again.", "warning");
        return;
    }

    if (requestId !== latestRequestId) return;

    renderBlueprintFeed(
        results,
        "Nothing matches yet",
        `Nothing matched "${query}" — try a different term or browse by category.`,
        "search"
    );
}

// Every user_id across the *result* builds needs a profile attached for
// the card (creator name/avatar) — not just the ones that matched via
// username, since a build can match on title/description/category with
// a completely different author. One batch lookup, not N+1.
async function attachCreators(builds) {
    if (!builds.length) return builds;

    const uniqueUserIds = [...new Set(builds.map(build => build.user_id).filter(Boolean))];
    const profiles = await getProfilesByIds(uniqueUserIds);
    const profilesById = new Map(profiles.map(profile => [profile.id, profile]));

    return builds.map(build => ({
        ...build,
        profiles: profilesById.get(build.user_id) || null
    }));
}

function renderBlueprintFeed(builds, emptyTitle, emptyDescription, emptyIcon) {
    BlueprintFeed({
        container: blueprintsList,
        builds,
        pathPrefix: "../",
        layout: "grid",
        emptyTitle,
        emptyDescription,
        emptyIcon
    });
}

function showMessage(container, message) {
    container.innerHTML = `<p class="search-status-message">${escapeHtml(message)}</p>`;
}

// BlueprintFeed's empty-state visual (icon + heading) already does the
// job for a plain "type more"/"searching" message in the Blueprints
// section — reused here instead of a second, differently-styled message
// element, so a scope switch between e.g. "build" and "all" doesn't
// visibly flash between two different empty-state treatments.
function showBlueprintsMessage(description) {
    renderBlueprintFeed([], "Search Specbound.", description, "search");
}
