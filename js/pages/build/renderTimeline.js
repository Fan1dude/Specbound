import { resolveImageUrl } from "../../repositories/mediaRepository.js";
import { escapeHtml } from "../../utils/escapeHtml.js";
import { formatDate } from "../../utils/formatDate.js";
import { icon } from "../../utils/icons.js";

const INITIAL_REVISION_COUNT = 3;

export async function renderTimeline(revisions, slug) {
    const container = document.getElementById("revisionTimeline");

    if (!container) return;

    if (!revisions?.length) {
        container.innerHTML = `
            <div class="empty-state">
                <div class="empty-state-icon">${icon("document", 32)}</div>
                <h3>Start Your Project Log</h3>
                <p>Document the first step of this project to begin recording its progress.</p>
            </div>
        `;
        return;
    }

    const newestFirst = [...revisions].sort(
        (a, b) => new Date(b.created_at) - new Date(a.created_at)
    );

    // Same path-vs-URL resolution as the cover image (see
    // mediaRepository.resolveImageUrl) — resolved for every revision up
    // front so the whole list is built in one innerHTML write, not
    // revision-by-revision.
    const imageUrls = await Promise.all(
        newestFirst.map(revision => resolveImageUrl(revision.image_url))
    );

    const hasMore = newestFirst.length > INITIAL_REVISION_COUNT;

    container.innerHTML = `
        <div
            id="revisionList"
            class="journal-list ${hasMore ? "journal-list-collapsed" : ""}"
        >
            ${newestFirst.map((revision, index) => renderJournalEntry(revision, imageUrls[index], slug)).join("")}
        </div>

        ${
            hasMore
                ? `
                    <div class="journal-toggle-area">
                        <p id="revisionSummary" class="journal-summary">
                            Showing ${INITIAL_REVISION_COUNT} of ${newestFirst.length} updates
                        </p>

                        <button
                            id="toggleRevisionsBtn"
                            class="btn btn-secondary revision-toggle"
                            type="button"
                            aria-expanded="false"
                        >
                            View Complete Journey (${newestFirst.length})
                        </button>
                    </div>
                `
                : ""
        }
    `;

    if (hasMore) {
        setupRevisionToggle(newestFirst.length);
    }
}

function renderJournalEntry(revision, image, slug) {
    const attachments = revision.attachments || {};
    const timeSpent = attachments.time_spent;
    const updateType = formatUpdateType(revision.update_type);
    const username = revision.profiles?.username;
    const revisionUrl = `build.html?slug=${encodeURIComponent(slug || "")}&revision=${encodeURIComponent(revision.id)}`;

    return `
        <article class="journal-entry card">
            <header class="journal-entry-header">
                <div>
                    <a class="journal-version" href="${revisionUrl}">
                        ${escapeHtml(revision.version || "v0.1")}
                        ${icon("arrow-right", 16)}
                    </a>

                    <span class="journal-type">
                        ${updateType}
                    </span>
                </div>

                <time
                    class="journal-date"
                    datetime="${revision.created_at || ""}"
                >
                    ${formatDate(revision.created_at)}
                </time>
            </header>

            <div class="journal-entry-body">
                <h3>${escapeHtml(revision.title || "Untitled Update")}</h3>

                ${
                    revision.description
                        ? `
                            <p class="journal-description">
                                ${escapeHtml(revision.description)}
                            </p>
                        `
                        : ""
                }

                ${
                    image
                        ? `
                            <img
                                class="journal-image"
                                src="${image}"
                                alt="${escapeHtml(
                                    revision.title || "Blueprint update"
                                )}"
                                loading="lazy"
                            >
                        `
                        : ""
                }
            </div>

            <footer class="journal-metadata">
                ${
                    updateType
                        ? `<span class="journal-chip">${updateType}</span>`
                        : ""
                }

                ${
                    timeSpent
                        ? `
                            <span class="journal-chip">
                                Time spent: ${escapeHtml(timeSpent)}
                            </span>
                        `
                        : ""
                }

                <span class="journal-chip">
                    Progress: ${Number(revision.progress || 0)}%
                </span>

                ${
                    username
                        ? `
                            <span class="journal-chip">
                                By ${escapeHtml(username)}
                            </span>
                        `
                        : ""
                }
            </footer>
        </article>
    `;
}

function setupRevisionToggle(totalRevisions) {
    const list = document.getElementById("revisionList");
    const button = document.getElementById("toggleRevisionsBtn");
    const summary = document.getElementById("revisionSummary");

    if (!list || !button || !summary) return;

    button.addEventListener("click", () => {
        const isExpanded =
            button.getAttribute("aria-expanded") === "true";

        list.classList.toggle("journal-list-collapsed", isExpanded);
        button.setAttribute("aria-expanded", String(!isExpanded));

        button.textContent = isExpanded
            ? `View Complete Journey (${totalRevisions})`
            : "Collapse Journey";

        summary.textContent = isExpanded
            ? `Showing ${INITIAL_REVISION_COUNT} of ${totalRevisions} updates`
            : `Showing all ${totalRevisions} updates`;
    });
}

function formatUpdateType(type) {
    switch (type) {
        case "hardware":
            return "Hardware Upgrade";
        case "software":
            return "Software";
        case "firmware":
            return "Firmware";
        case "testing":
            return "Testing";
        case "documentation":
            return "Documentation";
        case "milestone":
            return "Milestone";
        case "progress":
            return "Progress Update";
        default:
            return "General Update";
    }
}


