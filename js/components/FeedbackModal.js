import { escapeHtml } from "../utils/escapeHtml.js";
import { submitFeedback } from "../repositories/communityRepository.js";
import { showToast } from "../core/toast.js";

// Milestone 22 §9 — same native-<dialog> construction as
// confirmDialog()/WelcomeDialog()/ReportButton.js's dialog. Loaded
// lazily (dynamic import from layout.js's footer button) rather than on
// every page load, since most page views never open it.
const CATEGORIES = [
    { value: "bug", label: "Bug" },
    { value: "confusing", label: "Confusing" },
    { value: "suggestion", label: "Suggestion" },
    { value: "feature_request", label: "Feature Request" }
];

export function showFeedbackModal() {
    const dialog = document.createElement("dialog");
    dialog.className = "modal";

    const previouslyFocused = document.activeElement;

    dialog.innerHTML = `
        <div class="modal-body">
            <h2 class="modal-title">Send Feedback</h2>
            <p class="modal-message">Help us improve Specbound.</p>

            <fieldset class="feedback-category-fieldset">
                <legend>Category</legend>
                <div class="feedback-category-options">
                    ${CATEGORIES.map((category, index) => `
                        <label class="feedback-category-option">
                            <input
                                type="radio"
                                name="feedbackCategory"
                                value="${escapeHtml(category.value)}"
                                ${index === 0 ? "checked" : ""}
                            >
                            ${escapeHtml(category.label)}
                        </label>
                    `).join("")}
                </div>
            </fieldset>

            <label for="feedbackMessageInput" class="sr-only">Message</label>
            <textarea
                id="feedbackMessageInput"
                rows="4"
                maxlength="2000"
                placeholder="What's on your mind?"
            ></textarea>

            <div class="modal-actions">
                <button type="button" class="btn btn-secondary" data-action="cancel">Cancel</button>
                <button type="button" class="btn btn-primary" data-action="submit">Send</button>
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
        const category = dialog.querySelector('input[name="feedbackCategory"]:checked')?.value;
        const message = dialog.querySelector("#feedbackMessageInput").value.trim();

        if (!message) {
            showToast("Please describe your feedback before sending.", "warning");
            return;
        }

        const submitBtn = dialog.querySelector('[data-action="submit"]');
        submitBtn.disabled = true;

        try {
            await submitFeedback(category, message, window.location.href);
            showToast("Feedback sent. Thank you.", "success");
            finish();
        } catch (error) {
            console.error("Submit feedback error:", error);
            showToast(error.message || "Could not send feedback.", "error");
            submitBtn.disabled = false;
        }
    });

    dialog.showModal();
    requestAnimationFrame(() => dialog.classList.add("is-open"));
}
