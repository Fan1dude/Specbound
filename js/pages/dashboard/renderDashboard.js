import { escapeHtml, escapeAttribute } from "../../utils/escapeHtml.js";

export function renderDashboard({ profile, builds, revisionCount }) {
    document.getElementById("dashboardGreeting").textContent =
        `Welcome back, ${profile?.username || "Creator"}.`;

    renderStats(builds, revisionCount);
    renderBuilds(builds);
}

function renderStats(builds, revisionCount) {
    const completed = builds.filter(build => build.status === "completed").length;

    document.getElementById("dashboardStats").innerHTML = `
        <div class="dashboard-stat">
            <span>${builds.length}</span>
            <p>Builds</p>
        </div>

        <div class="dashboard-stat">
            <span>${revisionCount}</span>
            <p>Build Logs</p>
        </div>

        <div class="dashboard-stat">
            <span>${completed}</span>
            <p>Completed</p>
        </div>
    `;
}

function renderBuilds(builds) {
    const container = document.getElementById("dashboardBuilds");

    if (!builds.length) {
        container.innerHTML = `
            <div class="empty-state">
                <h3>No builds yet.</h3>
                <p>Create your first build and start documenting your journey.</p>
                <a class="btn btn-primary" href="../pages/upload.html">Create Build</a>
            </div>
        `;
        return;
    }

    container.innerHTML = builds.map(build => `
        <article class="dashboard-build-card">
            ${build.image_url
                ? `<img src="${escapeAttribute(build.image_url)}" alt="${escapeAttribute(build.title)}" loading="lazy" decoding="async">`
                : ""
            }

            <div>
                <p class="hero-badge">${escapeHtml(formatStatus(build.status))}</p>
                <h3>${escapeHtml(build.title)}</h3>
                <p>${escapeHtml(build.description || "")}</p>

                <a class="btn btn-primary btn-small" href="../pages/build/build.html?slug=${encodeURIComponent(build.slug)}">
                    Continue
                </a>
            </div>
        </article>
    `).join("");
}

function formatStatus(status) {
    return status || "building";
}