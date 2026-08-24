import { escapeHtml, escapeAttribute } from "../../utils/escapeHtml.js";
import { isSafeHttpUrl } from "../../utils/safeUrl.js";

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

    container.innerHTML = items.map(renderResource).join("");
}

// A resource's url is user-controlled free text -- the editor's own
// <input type="url"> (renderResourcesSection.js) doesn't stop a builder
// from pasting a javascript:/data: scheme there, and HTML-attribute
// escaping alone (escapeAttribute()) only stops markup injection, not a
// syntactically-valid dangerous scheme from becoming a live href. Only a
// genuine http(s) URL (isSafeHttpUrl(), js/utils/safeUrl.js -- the same
// canonical check renderSpecifications.js already routes its own
// link-shaped values through) becomes a clickable link.
//
// An unsafe url still has a real label worth showing, so it renders as
// plain text instead of the whole resource silently disappearing -- the
// same "keep what's useful, drop only the dangerous part" treatment
// renderSetupInventory.js already gives an unsafe product link.
function renderResource(resource) {
    const displayText = resource.label?.trim() || resource.url;

    if (isSafeHttpUrl(resource.url)) {
        return `
            <a class="resource-link" href="${escapeAttribute(resource.url)}" target="_blank" rel="noopener noreferrer">
                ${escapeHtml(displayText)}
            </a>
        `;
    }

    return `<p class="resource-link resource-link-unsafe">${escapeHtml(displayText)}</p>`;
}

