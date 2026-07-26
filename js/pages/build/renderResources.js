// resources === null means "not recorded for this revision" (a revision
// published before Milestone 5C captured per-revision snapshots) —
// distinct from [] / undefined, which means "recorded, and there just
// weren't any." See renderBuild.js's renderRevisionView.
export function renderResources(resources) {
    const container = document.getElementById("buildResources");

    if (!container) return;

    if (resources === null) {
        container.innerHTML = `<p>Resources were not recorded for this revision.</p>`;
        return;
    }

    const items = (Array.isArray(resources) ? resources : []).filter(resource => resource?.url);

    if (!items.length) {
        container.innerHTML = `<p>No resources added yet.</p>`;
        return;
    }

    container.innerHTML = items
        .map(resource => `
            <a class="resource-link" href="${escapeAttribute(resource.url)}" target="_blank" rel="noopener noreferrer">
                ${escapeHtml(resource.label?.trim() || resource.url)}
            </a>
        `)
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

function escapeAttribute(value) {
    return escapeHtml(value);
}
