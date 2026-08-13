import { getMyFeedback, describeFeedbackCategory, describeFeedbackStatus } from "../../repositories/feedbackRepository.js";
import { escapeHtml, escapeAttribute } from "../../utils/escapeHtml.js";
import { formatDateTime } from "../../utils/formatDate.js";
import { listSkeleton } from "../../utils/skeletons.js";
import { icon } from "../../utils/icons.js";

// Milestone 26 — fully read-only, self-only list. RLS ("Users can view
// their own feedback", 0029_feedback_submissions.sql, unchanged by
// 0039) is the actual scope; getMyFeedback() passes no client-supplied
// user id at all, so there is nothing here that could be manipulated
// into showing another user's submissions.

// page_url is untrusted, unconstrained text — same rule as
// FeedbackCard.js's renderPageContext(): always plain escaped text,
// never a link, never interpolated into an href/script/style context.
function renderPageContext(pageUrl) {
    if (!pageUrl) {
        return `<span class="my-feedback-page-context my-feedback-page-context-empty">Not recorded</span>`;
    }

    return `<span class="my-feedback-page-context" title="${escapeAttribute(pageUrl)}">${escapeHtml(pageUrl)}</span>`;
}

function renderRow(row) {
    const categoryLabel = describeFeedbackCategory(row.category);
    const statusInfo = describeFeedbackStatus(row.status);

    return `
        <article class="my-feedback-item" data-status="${escapeAttribute(row.status)}">
            <header class="my-feedback-item-header">
                <span class="badge my-feedback-category-badge">${escapeHtml(categoryLabel)}</span>
                <span class="my-feedback-item-status my-feedback-item-status-${escapeAttribute(row.status)}">${escapeHtml(statusInfo.label)}</span>
            </header>

            <p class="my-feedback-item-message">${escapeHtml(row.message)}</p>

            <dl class="my-feedback-item-meta">
                <div class="my-feedback-item-meta-item">
                    <dt>Page</dt>
                    <dd>${renderPageContext(row.page_url)}</dd>
                </div>
                <div class="my-feedback-item-meta-item">
                    <dt>Submitted</dt>
                    <dd>${escapeHtml(formatDateTime(row.created_at))}</dd>
                </div>
                ${row.status_updated_at ? `
                    <div class="my-feedback-item-meta-item">
                        <dt>Status updated</dt>
                        <dd>${escapeHtml(formatDateTime(row.status_updated_at))}</dd>
                    </div>
                ` : ""}
            </dl>

            <p class="my-feedback-item-status-description">${escapeHtml(statusInfo.description)}</p>
        </article>
    `;
}

export async function renderMyFeedback() {
    const listEl = document.getElementById("myFeedbackList");
    const errorEl = document.getElementById("myFeedbackError");
    const bodyEl = document.getElementById("myFeedbackBody");
    const retryBtn = document.getElementById("myFeedbackRetryBtn");

    if (!listEl) return;

    retryBtn?.addEventListener("click", load);

    await load();

    async function load() {
        if (errorEl) errorEl.hidden = true;
        if (bodyEl) bodyEl.hidden = false;

        listEl.innerHTML = listSkeleton(3);

        let rows = [];

        try {
            rows = await getMyFeedback();
        } catch (error) {
            console.error("My Feedback load error:", error);

            if (bodyEl) bodyEl.hidden = true;
            if (errorEl) errorEl.hidden = false;
            return;
        }

        if (!rows.length) {
            listEl.innerHTML = `
                <div class="empty-state">
                    <div class="empty-state-icon">${icon("document", 32)}</div>
                    <h3>You haven't submitted any feedback yet</h3>
                    <p>Use the Feedback link in the footer any time you have a bug, question, or idea.</p>
                </div>
            `;
            return;
        }

        listEl.innerHTML = rows.map(renderRow).join("");
    }
}
