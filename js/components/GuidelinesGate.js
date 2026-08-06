import { hasAcceptedGuidelines, acceptGuidelines } from "../repositories/communityRepository.js";
import { showToast } from "../core/toast.js";

// Milestone 22 §7 — checked lazily at the first community-facing action
// (publish or comment), never wired into sign-up or the Milestone 21
// Welcome dialog. Blocks only the ONE action that triggered it, never
// the whole site, and is only ever asked once per account —
// guidelines_accepted_at is set the moment this resolves true and never
// checked again after.
export async function requireGuidelinesAcceptance(userId, pathPrefix = "") {
    let alreadyAccepted;

    try {
        alreadyAccepted = await hasAcceptedGuidelines(userId);
    } catch (error) {
        console.error("Guidelines acceptance check error:", error);
        // Fails open — a check that can't confirm acceptance must never
        // permanently block a real action (publishing/commenting) that
        // worked fine before this milestone existed.
        return true;
    }

    if (alreadyAccepted) return true;

    return new Promise(resolve => {
        const dialog = document.createElement("dialog");
        dialog.className = "modal";

        const previouslyFocused = document.activeElement;

        dialog.innerHTML = `
            <div class="modal-body">
                <h2 class="modal-title">Community Guidelines</h2>
                <p class="modal-message">
                    Before you publish or comment, please review and accept our
                    <a
                        href="${pathPrefix}pages/legal/community-guidelines.html"
                        target="_blank"
                        rel="noopener noreferrer"
                    >Community Guidelines</a>.
                </p>
                <label class="guidelines-accept-checkbox">
                    <input type="checkbox" id="guidelinesAcceptCheckbox">
                    I have read and agree to the Community Guidelines.
                </label>
                <div class="modal-actions">
                    <button type="button" class="btn btn-secondary" data-action="cancel">Cancel</button>
                    <button type="button" class="btn btn-primary" data-action="accept" disabled>Continue</button>
                </div>
            </div>
        `;

        document.body.appendChild(dialog);

        function finish(result) {
            dialog.classList.remove("is-open");

            setTimeout(() => {
                dialog.close();
                dialog.remove();
            }, 150);

            if (previouslyFocused && typeof previouslyFocused.focus === "function") {
                previouslyFocused.focus();
            }

            resolve(result);
        }

        const checkbox = dialog.querySelector("#guidelinesAcceptCheckbox");
        const acceptBtn = dialog.querySelector('[data-action="accept"]');

        // Same "disabled control with a visible reason, not a silent
        // no-op" convention as the editor's Publish button — here the
        // reason is simply that the checkbox above it is unchecked.
        checkbox.addEventListener("change", () => {
            acceptBtn.disabled = !checkbox.checked;
        });

        dialog.querySelector('[data-action="cancel"]').addEventListener("click", () => finish(false));
        dialog.addEventListener("cancel", () => finish(false));
        dialog.addEventListener("click", event => {
            if (event.target === dialog) finish(false);
        });

        acceptBtn.addEventListener("click", async () => {
            acceptBtn.disabled = true;

            try {
                await acceptGuidelines(userId);
                finish(true);
            } catch (error) {
                console.error("Accept guidelines error:", error);
                showToast(error.message || "Could not save your acceptance. Try again.", "error");
                acceptBtn.disabled = false;
            }
        });

        dialog.showModal();
        requestAnimationFrame(() => dialog.classList.add("is-open"));
    });
}
