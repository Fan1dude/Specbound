import { escapeHtml, escapeAttribute } from "../../utils/escapeHtml.js";
import { getSpecDisplayName, isSpecEntryFilled, isValidHttpUrl } from "../../utils/specifications.js";

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
        .filter(([, value]) => isSpecEntryFilled(value))
        .map(([key, value]) => `
            <div class="spec-item">
                <h3>${escapeHtml(formatSpecName(key))}</h3>
                ${renderSpecValue(value)}
            </div>
        `)
        .join("");
}

// A spec value is free text — nothing stops a builder from pasting a
// full retailer link into a plain field (live testing found exactly
// this: a long IKEA product URL, tracking parameters and all, stored
// as a "Desk" value on the older per-technology specification fields —
// a separate data structure from the newer Setup Inventory section,
// confirmed by reading both save paths and the publish/restore SQL:
// neither ever copies between `specifications` and `setup_inventory`).
// If the value parses as a genuine http(s) URL, it's never shown as
// raw text — same "concise link, full URL preserved as the target"
// treatment renderSetupInventory.js already uses for product links.
function renderSpecValue(value) {
    const displayName = getSpecDisplayName(value);

    if (isValidHttpUrl(displayName)) {
        return `<a class="spec-item-link" href="${escapeAttribute(displayName)}" target="_blank" rel="noopener noreferrer">View product</a>`;
    }

    return `<p>${escapeHtml(displayName)}</p>`;
}

function formatSpecName(key) {
    return key
        .replaceAll("_", " ")
        .replace(/\b\w/g, letter => letter.toUpperCase());
}