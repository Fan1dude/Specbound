import { escapeHtml } from "../../utils/escapeHtml.js";
import { getTechnology } from "../../config/technologies/index.js";

// GitHub-language-bar-style breakdown of what this builder works in — a
// pure client-side reduce over builds already fetched for Project
// Gallery, no separate query (spec §17.5). Reuses each technology's own
// existing accent color (js/config/technologies/*.js) — already a
// shipped, approved part of the system (category pages), not a new
// palette introduction (spec §3.3c).
export function renderTechnologyBreakdown(builds) {
    const el = document.getElementById("profileTechBreakdown");

    if (!el) return;

    const counts = new Map();
    for (const build of builds) {
        counts.set(build.category, (counts.get(build.category) || 0) + 1);
    }

    const total = builds.length;

    if (!total) {
        el.hidden = true;
        el.innerHTML = "";
        return;
    }

    const segments = [...counts.entries()]
        .map(([category, count]) => ({ technology: getTechnology(category), category, count }))
        .filter(entry => entry.technology)
        .sort((a, b) => b.count - a.count);

    if (!segments.length) {
        el.hidden = true;
        el.innerHTML = "";
        return;
    }

    el.hidden = false;
    el.innerHTML = `
        <div class="section-heading">
            <p class="hero-badge">Focus</p>
            <h2>Technology Breakdown</h2>
        </div>

        <div class="tech-breakdown-bar" role="img" aria-label="${escapeHtml(buildBarDescription(segments, total))}">
            ${segments
                .map(entry => `
                    <span
                        class="tech-breakdown-segment"
                        style="width: ${((entry.count / total) * 100).toFixed(2)}%; background: ${entry.technology.accent};"
                        title="${escapeHtml(entry.technology.title)} — ${Math.round((entry.count / total) * 100)}%"
                    ></span>
                `)
                .join("")}
        </div>

        <ul class="tech-breakdown-legend">
            ${segments
                .map(entry => `
                    <li>
                        <span class="tech-breakdown-swatch" style="background: ${entry.technology.accent};" aria-hidden="true"></span>
                        <span class="tech-breakdown-title">${escapeHtml(entry.technology.title)}</span>
                        <span class="tech-breakdown-count">${entry.count} ${entry.count === 1 ? "project" : "projects"}</span>
                    </li>
                `)
                .join("")}
        </ul>
    `;
}

function buildBarDescription(segments, total) {
    return segments
        .map(entry => `${entry.technology.title} ${Math.round((entry.count / total) * 100)}%, ${entry.count} projects`)
        .join("; ");
}
