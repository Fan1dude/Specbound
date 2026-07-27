import { escapeHtml } from "../utils/escapeHtml.js";

const CATEGORY_LABELS = {
    pc_build: "PC Build",
    setup: "Desk Setup",
    arduino: "Arduino",
    robotics: "Robotics",
    "3d_printer": "3D Printing",
    homelab: "Home Lab"
};

export function DraftCard(draft, pathPrefix = "") {
    const editUrl = `${pathPrefix}pages/build/edit.html?draft=${encodeURIComponent(draft.id)}`;
    const title = draft.title?.trim() || "Untitled project";
    const categoryLabel = CATEGORY_LABELS[draft.category] || "Project";

    return `
        <article class="draft-card card card-padding">
            <div class="draft-card-body">
                <span class="badge">${escapeHtml(categoryLabel)}</span>

                <h3>
                    <a href="${editUrl}">${escapeHtml(title)}</a>
                </h3>

                <p class="text-secondary">
                    ${escapeHtml(formatUpdatedDate(draft.updated_at || draft.created_at))}
                </p>
            </div>

            <a href="${editUrl}" class="btn btn-secondary btn-small">
                Continue Editing
            </a>
        </article>
    `;
}

function formatUpdatedDate(value) {
    if (!value) return "Updated recently";

    const date = new Date(value);

    if (Number.isNaN(date.getTime())) return "Updated recently";

    return `Updated ${date.toLocaleDateString(undefined, {
        month: "short",
        day: "numeric",
        year: "numeric"
    })}`;
}

