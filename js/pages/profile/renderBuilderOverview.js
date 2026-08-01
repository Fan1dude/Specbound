import { escapeHtml } from "../../utils/escapeHtml.js";
import { getTechnology } from "../../config/technologies/index.js";
import { formatJoinDate } from "./formatJoinDate.js";

// Quiet stat strip — deliberately NOT the old .profile-stat's 2.5rem
// bordered tiles (approved deviation, spec §11): a slim text-only row,
// closer to GitHub's "12 repositories · 340 followers" line, so it
// doesn't visually compete with Featured Project below it. Same four
// numbers as before (Published Projects, Comments Received, Total Views,
// Member Since) plus a new technology-focus chip row summarizing which
// categories this builder works in, ahead of the fuller Technology
// Breakdown section further down the page.
export function renderBuilderOverview(profile, builds, commentCount) {
    renderStats(profile, builds, commentCount);
    renderTechFocus(builds);
}

function renderStats(profile, builds, commentCount) {
    const el = document.getElementById("profileStats");

    if (!el) return;

    const totalViews = builds.reduce((sum, build) => sum + Number(build.views || 0), 0);

    const stats = [
        { value: builds.length.toLocaleString(), label: "Projects" },
        { value: Number(commentCount || 0).toLocaleString(), label: "Comments Received" },
        { value: totalViews.toLocaleString(), label: "Total Views" },
        { value: formatJoinDate(profile?.created_at, { yearOnly: true }), label: "Member Since" }
    ];

    el.innerHTML = stats
        .map(stat => `
            <span class="overview-stat">
                <strong>${escapeHtml(stat.value)}</strong> ${escapeHtml(stat.label)}
            </span>
        `)
        .join(`<span class="overview-stat-sep" aria-hidden="true">&middot;</span>`);
}

function renderTechFocus(builds) {
    const el = document.getElementById("profileTechFocus");

    if (!el) return;

    const counts = new Map();
    for (const build of builds) {
        counts.set(build.category, (counts.get(build.category) || 0) + 1);
    }

    const categories = [...counts.entries()]
        .sort((a, b) => b[1] - a[1])
        .map(([category]) => getTechnology(category))
        .filter(Boolean);

    if (!categories.length) {
        el.innerHTML = "";
        el.hidden = true;
        return;
    }

    el.hidden = false;
    el.innerHTML = `
        <span class="tech-focus-label">Primarily building</span>
        ${categories.map(technology => `<span class="badge">${escapeHtml(technology.title)}</span>`).join("")}
    `;
}
