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
                        title="${escapeHtml(entry.technology.title)} — ${Math.round((entry.count / total) * 100)}%"
                    ></span>
                `)
                .join("")}
        </div>

        <ul class="tech-breakdown-legend">
            ${segments
                .map(entry => `
                    <li>
                        <span class="tech-breakdown-swatch" aria-hidden="true"></span>
                        <span class="tech-breakdown-title">${escapeHtml(entry.technology.title)}</span>
                        <span class="tech-breakdown-count">${entry.count} ${entry.count === 1 ? "project" : "projects"}</span>
                    </li>
                `)
                .join("")}
        </ul>
    `;

    // CSP compatibility: was inline style="width:...; background:..."/
    // style="background:..." attributes — style-src with no
    // 'unsafe-inline' blocks those (same class of issue as
    // renderCategoryPage.js's --technology-accent note and
    // renderSpecificationsSection.js's identical one).
    //
    // Verified empirically, not assumed: under this app's exact
    // production CSP served as a real HTTP Content-Security-Policy
    // response header (not a meta tag) to a real Chromium instance via
    // Playwright, `element.style.setProperty(...)` and
    // `element.style.<property> = value` produced ZERO
    // securitypolicyviolation events and rendered correctly, while
    // `element.setAttribute("style", ...)` and a static `style="..."`
    // HTML attribute were both blocked (both are governed by CSP's
    // `style-src-attr` sub-directive; direct CSSOM property assignment
    // is not — this is the deliberate reason CSP doesn't restrict it:
    // by the time first-party JS can run at all, it already passed
    // script-src, so restricting its CSSOM calls adds no security
    // value, whereas an attacker-controlled `style=""` string reaching
    // innerHTML — even from otherwise-trusted code — still needs
    // blocking). See tools/ci/check-csp-bootstrap.js section 6 and
    // tests/technologyBreakdownCsp.test.html for the corresponding
    // static and behavioral regression coverage.
    //
    // Both node lists below are built from the same `segments` array in
    // the same order above, so index-matching against `segments` is
    // safe.
    [...el.querySelectorAll(".tech-breakdown-segment")].forEach((node, i) => {
        const entry = segments[i];
        node.style.setProperty("--breakdown-width", `${((entry.count / total) * 100).toFixed(2)}%`);
        node.style.setProperty("--breakdown-color", entry.technology.accent);
    });

    [...el.querySelectorAll(".tech-breakdown-swatch")].forEach((node, i) => {
        node.style.setProperty("--breakdown-color", segments[i].technology.accent);
    });
}

function buildBarDescription(segments, total) {
    return segments
        .map(entry => `${entry.technology.title} ${Math.round((entry.count / total) * 100)}%, ${entry.count} projects`)
        .join("; ");
}
