import { icon } from "../utils/icons.js";

// Shown once, ever, per account — the moment editor/app.js's publish
// handler detects a build count of 0 immediately before the publish call
// (see its own comment for the exact before/after ordering this depends
// on). Same native-<dialog> construction as WelcomeDialog/confirmDialog:
// showModal()'s built-in focus trap and Esc handling, close() restoring
// focus automatically. No state to persist on exit — the precondition
// that triggered this (zero prior published builds) can never be true
// again for this account once it's published once.
export function showFirstPublishDialog({ buildUrl, pathPrefix = "" }) {
    const dialog = document.createElement("dialog");
    dialog.className = "modal modal-onboarding";

    const previouslyFocused = document.activeElement;

    dialog.innerHTML = `
        <button type="button" class="modal-onboarding-close" data-action="close" aria-label="Close">
            ${icon("close", 16)}
        </button>
        <div class="modal-body">
            <h2 class="modal-title">Your first project is live</h2>
            <p class="modal-message">You can keep updating it as the build changes.</p>
            <div class="modal-actions">
                <a class="btn btn-secondary" href="${pathPrefix}pages/workshop.html">Return to Workshop</a>
                <a class="btn btn-primary" href="${buildUrl}">View Project</a>
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

    dialog.querySelector('[data-action="close"]').addEventListener("click", finish);
    dialog.addEventListener("cancel", finish);
    dialog.addEventListener("click", event => {
        if (event.target === dialog) finish();
    });

    dialog.showModal();
    requestAnimationFrame(() => dialog.classList.add("is-open"));
}
