import { loadNavbar, loadFooter } from "../../core/layout.js";
import { searchBuilds } from "../../repositories/buildRepository.js";
import { resolveBuildImageUrls } from "../../repositories/mediaRepository.js";
import { getProfilesByIds } from "../../repositories/profileRepository.js";
import { BlueprintFeed } from "../../components/BlueprintFeed.js";

const DEBOUNCE_MS = 300;
const MIN_QUERY_LENGTH = 2;

loadNavbar("../");
loadFooter("../");

const input = document.getElementById("searchPageInput");

let debounceTimer = null;

// Incremented on every search actually issued; a response is only applied
// if it's still the latest one by the time it resolves. Debouncing alone
// doesn't guarantee response *order* — two requests can still race and
// resolve out of order (e.g. a fast connection answering a later,
// shorter query before a slower one for an earlier, longer query
// finishes) — this is what actually prevents a stale response from
// clobbering a newer one on screen.
let latestRequestId = 0;

const params = new URLSearchParams(window.location.search);
const initialQuery = params.get("q") || "";

input.value = initialQuery;
runQuery(initialQuery, { updateUrl: false });

input.addEventListener("input", () => {
    clearTimeout(debounceTimer);

    debounceTimer = setTimeout(() => {
        runQuery(input.value, { updateUrl: true });
    }, DEBOUNCE_MS);
});

function isActiveQuery(value) {
    return value.trim().length >= MIN_QUERY_LENGTH;
}

function updateUrlQuery(trimmed) {
    const url = new URL(window.location.href);

    if (trimmed) {
        url.searchParams.set("q", trimmed);
    } else {
        url.searchParams.delete("q");
    }

    // replaceState, not pushState — every keystroke shouldn't add a
    // browser-history entry; the URL should just reflect current state,
    // reproducible on refresh or share.
    history.replaceState(null, "", url);
}

async function runQuery(rawValue, { updateUrl }) {
    const trimmed = rawValue.trim();

    if (updateUrl) {
        updateUrlQuery(trimmed);
    }

    if (!isActiveQuery(trimmed)) {
        latestRequestId += 1;
        showPrompt();
        return;
    }

    const requestId = ++latestRequestId;

    showState("Searching...", "Looking for matching projects.");

    let results = [];

    try {
        results = await searchBuilds(trimmed);
    } catch (error) {
        if (requestId !== latestRequestId) return;

        console.error("Search error:", error);
        showState("Search Unavailable", "Something went wrong while searching. Try again.", "warning");
        return;
    }

    if (requestId !== latestRequestId) return;

    try {
        results = await attachCreators(await resolveBuildImageUrls(results));
    } catch (error) {
        if (requestId !== latestRequestId) return;

        console.error("Search result loading error:", error);
        showState("Search Unavailable", "Something went wrong while searching. Try again.", "warning");
        return;
    }

    if (requestId !== latestRequestId) return;

    BlueprintFeed({
        container: "#searchResults",
        builds: results,
        pathPrefix: "../",
        layout: "grid",
        emptyTitle: "Nothing matches yet",
        emptyDescription: `Nothing matched "${trimmed}" — try a different term or browse by category.`,
        emptyIcon: "search"
    });
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

function showPrompt() {
    showState("Search Specbound.", "Type something to search projects, builders, or categories.", "search");
}

function showState(title, description, icon = "search") {
    BlueprintFeed({
        container: "#searchResults",
        builds: [],
        pathPrefix: "../",
        layout: "grid",
        emptyTitle: title,
        emptyDescription: description,
        emptyIcon: icon
    });
}
