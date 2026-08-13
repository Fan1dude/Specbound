import { escapeHtml, escapeAttribute } from "../utils/escapeHtml.js";
import { formatDateTime } from "../utils/formatDate.js";
import { describeFeedbackCategory, describeFeedbackStatus } from "../repositories/feedbackRepository.js";
import { icon } from "../utils/icons.js";

// Milestone 26 — a dedicated card, not a ReportCard.js extension
// (explicit product decision): feedback's status shape (Open ->
// Reviewed -> Closed, with Reviewed itself still carrying one forward
// action) doesn't fit Reports' two-outcome, fully-terminal-history
// shape without contorting one component to serve two different state
// machines.

// Icon + color pairing reuses the exact tokens report-card-status-* already
// establishes (css/pages/moderation/moderation.css) — no new color token
// is introduced. open mirrors Reports' "open" (info); reviewed mirrors
// Reports' "reviewed" (warning-strong, an acknowledged-but-not-final
// state); closed mirrors Reports' "dismissed" (success-strong, a
// terminal outcome) — closest semantic match available without
// inventing a fourth status color.
const STATUS_ICONS = {
    open: "info",
    reviewed: "check",
    closed: "check"
};

// page_url is untrusted, unconstrained text (see
// supabase/migrations/0029_feedback_submissions.sql — no CHECK on this
// column, and submit_feedback() performs no server-side validation on
// it either). It is ALWAYS rendered as plain escaped text here, never
// interpolated into an href, script, or style context — the same rule
// ReportCard.js's renderTargetMarkup() already follows for any
// free-text/user-controlled value (only trusted, server-derived hrefs
// like a build slug or profile id ever become a link there). escapeHtml
// neutralizes markup but does not vet URL schemes, so the only safe
// design is to never let this value become clickable at all.
function renderPageContext(pageUrl) {
    if (!pageUrl) {
        return `<span class="feedback-card-page-context feedback-card-page-context-empty">Not recorded</span>`;
    }

    return `<span class="feedback-card-page-context" title="${escapeAttribute(pageUrl)}">${escapeHtml(pageUrl)}</span>`;
}

function renderSubmitter(row, submitterProfiles) {
    if (!row.user_id) {
        return `<span class="feedback-card-submitter-deleted">Deleted account</span>`;
    }

    const profile = submitterProfiles.get(row.user_id);

    if (!profile) {
        return `<span class="feedback-card-submitter-deleted">Profile unavailable</span>`;
    }

    const name = profile.display_name || profile.username || "A builder";

    return `<a href="../profile.html?user=${encodeURIComponent(profile.id)}" class="feedback-card-submitter-link">${escapeHtml(name)}</a>`;
}

function renderMetaRow(label, valueHtml) {
    return `
        <div class="feedback-card-meta-item">
            <dt>${escapeHtml(label)}</dt>
            <dd>${valueHtml}</dd>
        </div>
    `;
}

function renderActions(row) {
    if (row.status === "open") {
        return `
            <div class="feedback-card-actions">
                <button
                    type="button"
                    class="btn btn-secondary btn-small"
                    data-action="update-feedback-status"
                    data-feedback-id="${escapeAttribute(row.id)}"
                    data-expected-status="open"
                    data-new-status="reviewed"
                >
                    ${icon("check", 16)} Mark Reviewed
                </button>
                <button
                    type="button"
                    class="btn btn-danger btn-small"
                    data-action="update-feedback-status"
                    data-feedback-id="${escapeAttribute(row.id)}"
                    data-expected-status="open"
                    data-new-status="closed"
                >
                    ${icon("close", 16)} Mark Closed
                </button>
            </div>
        `;
    }

    if (row.status === "reviewed") {
        return `
            <div class="feedback-card-actions">
                <button
                    type="button"
                    class="btn btn-danger btn-small"
                    data-action="update-feedback-status"
                    data-feedback-id="${escapeAttribute(row.id)}"
                    data-expected-status="reviewed"
                    data-new-status="closed"
                >
                    ${icon("close", 16)} Mark Closed
                </button>
            </div>
        `;
    }

    return "";
}

// submitterProfiles: Map<userId, profile> from getFeedbackSubmitterProfiles().
export function renderFeedbackCard(row, { submitterProfiles }) {
    const categoryLabel = describeFeedbackCategory(row.category);
    const statusInfo = describeFeedbackStatus(row.status);
    const statusIconName = STATUS_ICONS[row.status] || "info";

    return `
        <article class="feedback-card" data-feedback-id="${escapeAttribute(row.id)}" data-status="${escapeAttribute(row.status)}">
            <header class="feedback-card-header">
                <div class="feedback-card-heading">
                    <span class="badge feedback-card-category-badge">${escapeHtml(categoryLabel)}</span>
                    ${renderSubmitter(row, submitterProfiles)}
                </div>

                <span class="feedback-card-status feedback-card-status-${escapeAttribute(row.status)}">
                    <span class="feedback-card-status-icon" aria-hidden="true">${icon(statusIconName, 16)}</span>
                    ${escapeHtml(statusInfo.label)}
                </span>
            </header>

            <p class="feedback-card-message">${escapeHtml(row.message)}</p>

            <dl class="feedback-card-meta">
                ${renderMetaRow("Page", renderPageContext(row.page_url))}
                ${renderMetaRow("Submitted", escapeHtml(formatDateTime(row.created_at)))}
                ${row.status_updated_at ? renderMetaRow("Last updated", escapeHtml(formatDateTime(row.status_updated_at))) : ""}
            </dl>

            <p class="feedback-card-status-description">${escapeHtml(statusInfo.description)}</p>

            ${renderActions(row)}
        </article>
    `;
}

export function renderFeedbackCardList(rows, options) {
    return rows.map(row => renderFeedbackCard(row, options)).join("");
}

// Delegated wiring, matching wireReportCardActions() (ReportCard.js) —
// re-bindable after a re-render without double-firing on an
// already-wired button.
export function wireFeedbackCardActions(container, onUpdateStatus) {
    container.querySelectorAll('[data-action="update-feedback-status"]').forEach(button => {
        if (button.dataset.statusWired) return;
        button.dataset.statusWired = "true";

        button.addEventListener("click", () => {
            const { feedbackId, expectedStatus, newStatus } = button.dataset;
            if (!feedbackId || !expectedStatus || !newStatus) return;
            onUpdateStatus(feedbackId, expectedStatus, newStatus, button);
        });
    });
}
