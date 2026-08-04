import { icon } from "../utils/icons.js";
import { escapeHtml, escapeAttribute } from "../utils/escapeHtml.js";
import { reportContent } from "../repositories/communityRepository.js";
import { showToast } from "../core/toast.js";

// Milestone 22 §8.3 — a small, reusable report entry point wired into
// comments and build pages. Reuses the same native-<dialog> construction
// as confirmDialog()/WelcomeDialog()/FirstPublishDialog() (focus
// handling, Esc, backdrop dismiss, correct centering per the Milestone
// 21 modal.css fix) rather than a bespoke prompt.
const REPORT_TARGET_LABELS = {
    build: "project",
    comment: "comment",
    profile: "profile"
};

export function ReportButton({ targetType, targetId }) {
    const label = REPORT_TARGET_LABELS[targetType] || "content";

    return `
        <button
            type="button"
            class="btn btn-ghost btn-small report-content-btn"
            data-target-type="${escapeAttribute(targetType)}"
            data-target-id="${escapeAttribute(targetId)}"
            aria-label="Report this ${escapeAttribute(label)}"
        >
            ${icon("warning", 16)} Report
        </button>
    `;
}

// Call once after inserting ReportButton markup into a container —
// delegated per-button wiring, matching renderComments.js's own
// bindDeleteButtons() convention. Safe to call again after a container's
// content is re-rendered (e.g. renderComments.js's full-rebuild
// renderList()) — already-wired buttons are skipped, not double-bound.
export function wireReportButtons(root) {
    root.querySelectorAll(".report-content-btn").forEach(button => {
        if (button.dataset.reportWired) return;
        button.dataset.reportWired = "true";

        button.addEventListener("click", () => {
            showReportDialog(button.dataset.targetType, button.dataset.targetId);
        });
    });
}

function showReportDialog(targetType, targetId) {
    const label = REPORT_TARGET_LABELS[targetType] || "content";
    const dialog = document.createElement("dialog");
    dialog.className = "modal";

    const previouslyFocused = document.activeElement;

    dialog.innerHTML = `
        <div class="modal-body">
            <h2 class="modal-title">Report this ${escapeHtml(label)}</h2>
            <p class="modal-message">Tell us what's wrong. A moderator will review it.</p>
            <label for="reportReasonInput" class="sr-only">Reason</label>
            <textarea id="reportReasonInput" rows="4" maxlength="500" placeholder="What's the issue?"></textarea>
            <div class="modal-actions">
                <button type="button" class="btn btn-secondary" data-action="cancel">Cancel</button>
                <button type="button" class="btn btn-primary" data-action="submit">Submit Report</button>
            </div>
        </div>
    `;

    document.body.appendChild(dialog);

    function finish() {
        dialog.classList.remove("is-open");

        setTimeout(() => {
            dialog.close();
            dialog.remove();
        }, 150);

        if (previouslyFocused && typeof previouslyFocused.focus === "function") {
            previouslyFocused.focus();
        }
    }

    dialog.querySelector('[data-action="cancel"]').addEventListener("click", finish);
    dialog.addEventListener("cancel", finish);
    dialog.addEventListener("click", event => {
        if (event.target === dialog) finish();
    });

    dialog.querySelector('[data-action="submit"]').addEventListener("click", async () => {
        const textarea = dialog.querySelector("#reportReasonInput");
        const reason = textarea.value.trim();

        if (!reason) {
            showToast("Please describe the issue before submitting.", "warning");
            return;
        }

        const submitBtn = dialog.querySelector('[data-action="submit"]');
        submitBtn.disabled = true;

        try {
            await reportContent(targetType, targetId, reason);
            showToast("Report submitted. Thank you.", "success");
            finish();
        } catch (error) {
            console.error("Report content error:", error);
            showToast(error.message || "Could not submit report.", "error");
            submitBtn.disabled = false;
        }
    });

    dialog.showModal();
    requestAnimationFrame(() => dialog.classList.add("is-open"));
}
