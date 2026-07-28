import { BlueprintCard } from "../../components/BlueprintCard.js";
import { DraftCard } from "../../components/DraftCard.js";
import { setBuildSaved } from "../../repositories/savedRepository.js";
import { showToast } from "../../core/toast.js";
import { escapeHtml, escapeAttribute } from "../../utils/escapeHtml.js";
import { hydrateProgressBars } from "../../utils/progressBar.js";
import { icon } from "../../utils/icons.js";

export function renderWorkshop({ user, profile, builds, revisionCount, drafts, latestBuild, latestRevision, savedBuilds }) {
    const username = profile?.username || "Builder";

    document.getElementById("workshopGreeting").textContent = `Welcome back, ${username}.`;

    // Built once from the drafts already fetched by loadWorkshop.js — not
    // an extra query per project. continue.html's direct-write flow is
    // retired (Milestone 5A); "Continue Building"/"Continue Editing" now
    // open the linked draft in the real editor instead of a dead page.
    const draftIdByBuildId = new Map(
        (drafts || [])
            .filter(draft => draft.published_build_id)
            .map(draft => [draft.published_build_id, draft.id])
    );

    renderContinueSection(latestBuild, latestRevision, draftIdByBuildId);
    // Once a draft is published, it's the backing state for its Project
    // card (which already has its own "Continue Editing" link) — showing
    // it a second time here as if it were still an unfinished, never-
    // published draft duplicated the same project in two sections.
    renderDraftsSection(drafts.filter(draft => !draft.published_build_id));
    renderProjectsSection(builds, draftIdByBuildId);
    renderSavedSection(savedBuilds);

    const profileLink = document.getElementById("workshopProfileLink");

    if (profileLink) {
        profileLink.href = `profile.html?user=${encodeURIComponent(user.id)}`;
    }
}

function renderContinueSection(latestBuild, latestRevision, draftIdByBuildId) {
    const container = document.getElementById("workshopContinue");

    if (!latestBuild) {
        container.innerHTML = `
            <div class="empty-state">
                <div class="empty-state-icon">${icon("document", 32)}</div>
                <h3>Start your first project</h3>
                <p>
                    Document what you're building from day one — specifications,
                    progress, and everything you learn along the way.
                </p>

                <a href="upload.html" class="btn btn-primary">
                    Create Your First Project
                </a>
            </div>
        `;
        return;
    }

    const progress = clampProgress(latestRevision?.progress);
    const linkedDraftId = draftIdByBuildId.get(latestBuild.id);

    // Falls back to the public project page in the unusual case where no
    // draft is linked (see the same fallback/reasoning in BlueprintCard.js)
    // rather than a dead link.
    const continueUrl = linkedDraftId
        ? `build/edit.html?draft=${encodeURIComponent(linkedDraftId)}`
        : `build/build.html?slug=${encodeURIComponent(latestBuild.slug || "")}`;

    container.innerHTML = `
        <div class="card card-padding workshop-continue-card">
            <p class="hero-badge">Continue Building</p>

            <h2>${escapeHtml(latestBuild.title || "Untitled Project")}</h2>

            <p class="text-secondary">
                ${escapeHtml(formatUpdatedDate(latestBuild.updated_at || latestBuild.created_at))}
            </p>

            <div class="progress">
                <div class="progress-header">
                    <span>Progress</span>
                    <span>${progress}%</span>
                </div>

                <div
                    class="progress-track"
                    role="progressbar"
                    aria-label="Project progress"
                    aria-valuemin="0"
                    aria-valuemax="100"
                    aria-valuenow="${progress}"
                >
                    <div class="progress-fill" data-progress="${progress}"></div>
                </div>
            </div>

            <a href="${continueUrl}" class="btn btn-primary">
                Continue Building
            </a>
        </div>
    `;

    hydrateProgressBars(container);
}

function renderDraftsSection(drafts) {
    const section = document.getElementById("workshopDraftsSection");

    if (!drafts?.length) {
        section.hidden = true;
        return;
    }

    section.hidden = false;

    document.getElementById("workshopDrafts").innerHTML = drafts
        .map(draft => DraftCard(draft, "../"))
        .join("");
}

function renderProjectsSection(builds, draftIdByBuildId) {
    document.getElementById("workshopProjectCount").textContent =
        builds.length === 1 ? "1 project" : `${builds.length} projects`;

    const container = document.getElementById("workshopProjects");

    if (!builds.length) {
        container.innerHTML = `
            <div class="empty-state">
                <div class="empty-state-icon">${icon("document", 32)}</div>
                <h3>Your workshop is empty</h3>
                <p>Start documenting your first build.</p>
                <a class="btn btn-primary" href="upload.html">Create Project</a>
            </div>
        `;
        return;
    }

    container.innerHTML = builds
        .map(build => BlueprintCard(
            { ...build, draftId: draftIdByBuildId.get(build.id) },
            "../",
            { variant: "workspace" }
        ))
        .join("");

    hydrateProgressBars(container);
}

// A thin wrapper around the unmodified BlueprintCard, per the approved
// Milestone 6E proposal — the card itself never changes; "Remove from
// Saved" lives in a sibling element around it instead.
function renderSavedSection(savedBuilds) {
    const countHeading = document.getElementById("workshopSavedCount");
    const container = document.getElementById("workshopSaved");

    if (!container || !countHeading) return;

    if (savedBuilds === null) {
        countHeading.textContent = "Saved Projects";
        container.innerHTML = `<p class="text-secondary">Could not load your saved projects. Try refreshing the page.</p>`;
        return;
    }

    // A local mutable copy — removing a save re-renders this list from
    // here, same "re-render the whole list on any mutation" convention as
    // renderComments.js's comment array.
    let saved = [...savedBuilds];

    renderList();

    function renderList() {
        countHeading.textContent = saved.length === 1 ? "1 saved project" : `${saved.length} saved projects`;

        if (!saved.length) {
            container.innerHTML = `
                <div class="empty-state">
                    <div class="empty-state-icon">${icon("document", 32)}</div>
                    <h3>You haven't saved any projects yet.</h3>
                    <p>Save a project from its page to revisit it here later.</p>
                    <a class="btn btn-primary" href="explore.html">Explore Projects</a>
                </div>
            `;
            return;
        }

        container.innerHTML = saved
            .map(build => `
                <div class="saved-project-card">
                    ${BlueprintCard(build, "../")}

                    <button
                        type="button"
                        class="btn btn-ghost btn-small saved-remove-btn"
                        data-build-id="${escapeAttribute(build.id)}"
                    >
                        Remove from Saved
                    </button>
                </div>
            `)
            .join("");

        hydrateProgressBars(container);

        container.querySelectorAll(".saved-remove-btn").forEach(button => {
            button.addEventListener("click", async () => {
                const buildId = button.dataset.buildId;
                const index = saved.findIndex(build => build.id === buildId);

                if (index === -1) return;

                // Optimistic — the card disappears immediately, restored
                // at its original position only if the request fails.
                const [removedBuild] = saved.splice(index, 1);
                renderList();

                try {
                    await setBuildSaved(buildId, false);
                    showToast("Removed from your saved projects.", "success");
                } catch (error) {
                    console.error("Remove saved project error:", error);

                    saved.splice(index, 0, removedBuild);
                    renderList();

                    showToast(error.message || "Could not remove this project.", "error");
                }
            });
        });
    }
}

function clampProgress(value) {
    const number = Number(value || 0);

    if (!Number.isFinite(number)) return 0;

    return Math.min(100, Math.max(0, Math.round(number)));
}

function formatUpdatedDate(value) {
    if (!value) return "Updated recently";

    const date = new Date(value);

    if (Number.isNaN(date.getTime())) {
        return "Updated recently";
    }

    return `Updated ${date.toLocaleDateString(undefined, {
        month: "short",
        day: "numeric",
        year: "numeric"
    })}`;
}

