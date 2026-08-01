import { escapeHtml } from "../../utils/escapeHtml.js";
import { icon } from "../../utils/icons.js";
import { formatJoinDate } from "./formatJoinDate.js";

// Curated top-10 milestone timeline — see spec §3.3(d)/§17.4 for how
// `events` (already built by buildBuilderJourney()) is selected. No
// pagination/"full history" view in V1 — a fixed list, rendered once.
// The rail/node styling is decorative; the actual content is a real
// semantic <ol> (most-recent-first, matching true chronological order)
// so screen readers get a correctly ordered list, not a div soup (spec §9).
const TYPE_ICON = {
    published: "document",
    completed: "check",
    milestone: "milestone",
    "first-in-category": "milestone",
    "major-version": "arrow-up-right"
};

export function renderBuilderJourney(events, pathPrefix = "../") {
    const el = document.getElementById("profileJourney");

    if (!el) return;

    if (!events.length) {
        el.hidden = true;
        el.innerHTML = "";
        return;
    }

    el.hidden = false;
    el.innerHTML = `
        <div class="section-heading">
            <p class="hero-badge">Journey</p>
            <h2>Builder Journey</h2>
        </div>

        <ol class="builder-journey-list">
            ${events.map(event => renderEvent(event, pathPrefix)).join("")}
        </ol>
    `;
}

function renderEvent(event, pathPrefix) {
    const buildUrl = event.build?.slug
        ? `${pathPrefix}pages/build/build.html?slug=${encodeURIComponent(event.build.slug)}`
        : null;

    return `
        <li class="builder-journey-event">
            <span class="builder-journey-node" aria-hidden="true">${icon(TYPE_ICON[event.type] || "document", 16)}</span>

            <span class="builder-journey-date">${escapeHtml(formatJoinDate(event.date))}</span>

            <span class="builder-journey-label">
                ${buildUrl ? `<a href="${buildUrl}">${escapeHtml(event.label)}</a>` : escapeHtml(event.label)}
            </span>
        </li>
    `;
}
