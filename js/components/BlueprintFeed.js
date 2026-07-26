import { BlueprintCard } from "./BlueprintCard.js";

export function BlueprintFeed({
    container,
    builds = [],
    pathPrefix = "",
    layout = "grid",
    emptyTitle = "No Blueprints Found",
    emptyDescription = "There are no Blueprints to display yet."
}) {
    const target =
        typeof container === "string"
            ? document.querySelector(container)
            : container;

    if (!target) {
        console.error("BlueprintFeed: container was not found.");
        return;
    }

    target.classList.add("blueprint-feed");
    target.classList.add(`blueprint-feed-${layout}`);

    if (!Array.isArray(builds) || builds.length === 0) {
        target.innerHTML = `
            <div class="empty-state blueprint-feed-empty">
                <h3>${escapeHtml(emptyTitle)}</h3>
                <p>${escapeHtml(emptyDescription)}</p>
            </div>
        `;
        return;
    }

    target.innerHTML = builds
        .map(build => BlueprintCard(build, pathPrefix))
        .join("");
}

function escapeHtml(value) {
    return String(value)
        .replaceAll("&", "&amp;")
        .replaceAll("<", "&lt;")
        .replaceAll(">", "&gt;")
        .replaceAll('"', "&quot;")
        .replaceAll("'", "&#039;");
}