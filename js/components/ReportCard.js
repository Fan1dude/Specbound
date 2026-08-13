import { escapeHtml, escapeAttribute } from "../utils/escapeHtml.js";
import { formatDateTime } from "../utils/formatDate.js";
import { describeReportStatus, RESOLUTION_OUTCOMES } from "../repositories/moderationRepository.js";
import { icon } from "../utils/icons.js";

// Milestone 24 — one shared card renderer for both the Open queue and the
// Resolved history, parameterized by `mode` rather than two near-
// duplicate templates that would drift apart over time (the same
// reasoning renderSetupInventory.js/renderSetupInventorySection.js's
// separate-but-related renderers already follow elsewhere in this app —
// here the two views are close enough that one shared component, not two
// siblings, is the better fit).

const TARGET_TYPE_LABELS = {
    build: "Project",
    comment: "Comment",
    profile: "Profile"
};

// Never color alone — every status also carries a distinct icon, matching
// the exact convention already established by
// renderSetupInventorySection.js's metadata-fetch status (role="alert"/
// "status" + icon + text, never a bare colored dot).
const STATUS_ICONS = {
    open: "info",
    dismissed: "check",
    reviewed: "warning"
};

function targetKey(report) {
    return `${report.target_type}:${report.target_id}`;
}

function renderTargetMarkup(report, targetContext) {
    const typeLabel = TARGET_TYPE_LABELS[report.target_type] || "Content";
    const target = targetContext.get(targetKey(report));

    if (!target || !target.available) {
        return `
            <span class="report-card-target-unavailable">
                ${escapeHtml(typeLabel)} unavailable — it may have been deleted, unpublished, or made private.
                <span class="report-card-target-id">Reference id: ${escapeHtml(report.target_id)}</span>
            </span>
        `;
    }

    const label = target.label || typeLabel;

    return target.href
        ? `<a href="${escapeAttribute(target.href)}" class="report-card-target-link" target="_blank" rel="noopener noreferrer">${escapeHtml(label)}</a>`
        : `<span class="report-card-target-label">${escapeHtml(label)}</span>`;
}

function renderMetaRow(label, value) {
    return `
        <div class="report-card-meta-item">
            <dt>${escapeHtml(label)}</dt>
            <dd>${escapeHtml(value)}</dd>
        </div>
    `;
}

// mode: "open" | "resolved". actorProfiles: Map<userId, profile> from
// getReportActorProfiles(). targetContext: Map from
// getReportTargetContext().
export function renderReportCard(report, { mode, targetContext, actorProfiles }) {
    const typeLabel = TARGET_TYPE_LABELS[report.target_type] || "Content";
    const statusInfo = describeReportStatus(report.status);
    const statusIconName = STATUS_ICONS[report.status] || "info";

    const reporter = actorProfiles.get(report.reporter_id);
    const reporterName = reporter?.display_name || reporter?.username || "A builder";

    const resolver = report.reviewed_by ? actorProfiles.get(report.reviewed_by) : null;
    const resolverName = report.reviewed_by
        ? (resolver?.display_name || resolver?.username || "A moderator")
        : null;

    return `
        <article class="report-card" data-report-id="${escapeAttribute(report.id)}" data-status="${escapeAttribute(report.status)}">
            <header class="report-card-header">
                <div class="report-card-target">
                    <span class="badge report-card-type-badge">${escapeHtml(typeLabel)}</span>
                    ${renderTargetMarkup(report, targetContext)}
                </div>

                <span class="report-card-status report-card-status-${escapeAttribute(report.status)}">
                    <span class="report-card-status-icon" aria-hidden="true">${icon(statusIconName, 16)}</span>
                    ${escapeHtml(statusInfo.label)}
                </span>
            </header>

            <p class="report-card-reason">${escapeHtml(report.reason)}</p>

            <dl class="report-card-meta">
                ${renderMetaRow("Reported by", reporterName)}
                ${renderMetaRow("Submitted", formatDateTime(report.created_at))}
                ${mode === "resolved" ? renderMetaRow("Resolved", formatDateTime(report.reviewed_at)) : ""}
                ${mode === "resolved" && resolverName ? renderMetaRow("Resolved by", resolverName) : ""}
            </dl>

            ${mode === "open" ? `
                <p class="report-card-note">
                    Resolving records a decision only — it does not remove content, suspend the reported user, or take any other action.
                </p>
                <div class="report-card-actions">
                    <button
                        type="button"
                        class="btn btn-secondary btn-small"
                        data-action="resolve-report"
                        data-outcome="no_violation"
                        data-report-id="${escapeAttribute(report.id)}"
                        aria-label="Mark this ${escapeAttribute(typeLabel.toLowerCase())} report as no violation"
                    >
                        ${icon("check", 16)} No violation
                    </button>
                    <button
                        type="button"
                        class="btn btn-danger btn-small"
                        data-action="resolve-report"
                        data-outcome="violation_confirmed"
                        data-report-id="${escapeAttribute(report.id)}"
                        aria-label="Mark this ${escapeAttribute(typeLabel.toLowerCase())} report as violation confirmed"
                    >
                        ${icon("warning", 16)} Violation confirmed
                    </button>
                </div>
            ` : ""}
        </article>
    `;
}

export function renderReportCardList(reports, options) {
    return reports.map(report => renderReportCard(report, options)).join("");
}

// Delegated wiring, matching wireReportButtons() (ReportButton.js) and
// wireEvents() (renderSetupInventorySection.js)'s exact convention —
// re-bindable after a re-render without double-firing on an already-
// wired button.
export function wireReportCardActions(container, onResolve) {
    container.querySelectorAll('[data-action="resolve-report"]').forEach(button => {
        if (button.dataset.resolveWired) return;
        button.dataset.resolveWired = "true";

        button.addEventListener("click", () => {
            const { reportId, outcome } = button.dataset;
            if (!reportId || !RESOLUTION_OUTCOMES[outcome]) return;
            onResolve(reportId, outcome, button);
        });
    });
}
