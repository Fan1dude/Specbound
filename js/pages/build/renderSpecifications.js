import { escapeHtml } from "../../utils/escapeHtml.js";

// specifications === null means "not recorded for this revision" (a
// revision published before Milestone 5C captured per-revision snapshots)
// — distinct from {} / undefined, which means "recorded, and there just
// weren't any." See renderBuild.js's renderRevisionView for how the
// distinction is made.
export function renderSpecifications(specifications) {
    const container = document.getElementById("buildSpecifications");

    if (!container) return;

    if (specifications === null) {
        container.innerHTML = `<p>Specifications were not recorded for this revision.</p>`;
        return;
    }

    if (!specifications || Object.keys(specifications).length === 0) {
        container.innerHTML = `<p>No specifications added yet.</p>`;
        return;
    }

    container.innerHTML = Object.entries(specifications)
        .filter(([_, value]) => value)
        .map(([key, value]) => `
            <div class="spec-item">
                <h3>${escapeHtml(formatSpecName(key))}</h3>
                <p>${escapeHtml(value)}</p>
            </div>
        `)
        .join("");
}

function formatSpecName(key) {
    return key
        .replaceAll("_", " ")
        .replace(/\b\w/g, letter => letter.toUpperCase());
}