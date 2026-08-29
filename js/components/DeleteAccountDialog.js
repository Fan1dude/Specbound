import { escapeHtml } from "../utils/escapeHtml.js";

// Confirmation dialog for self-service account deletion — Launch
// Readiness self-service account deletion. Built the same way
// GuidelinesGate.js's acceptance dialog is (a hand-built <dialog>, not
// confirmDialog() from js/utils/modal.js) because this needs two real
// text inputs with a gated submit, not a single yes/no choice.
//
// Requires the caller to type the exact phrase "DELETE MY ACCOUNT" —
// deliberately a fixed, product-decided phrase, not derived from the
// user's own username/email, so it can never be pre-filled or
// autocompleted by the browser and always requires a deliberate,
// attentive action. Password re-entry here is the FIRST half of
// reauthentication (client-side confirmation the user typed their
// current password correctly, verified via signInWithPassword() by the
// caller of this dialog) — the delete-account Edge Function separately,
// server-side, enforces that the resulting session is actually recent
// (see supabase/functions/delete-account/lib.ts's
// isRecentlyAuthenticated()), so this dialog's own password field is
// not, by itself, the security boundary.
export const DELETE_ACCOUNT_CONFIRMATION_PHRASE = "DELETE MY ACCOUNT";

export function deleteAccountDialog() {
    return new Promise(resolve => {
        const dialog = document.createElement("dialog");
        dialog.className = "modal modal-delete-account";

        const previouslyFocused = document.activeElement;

        dialog.innerHTML = `
            <div class="modal-body">
                <h2 class="modal-title">Delete your account?</h2>
                <p class="modal-message">
                    This permanently deletes your profile, published builds,
                    drafts, comments, likes, saves, and follows. Feedback you
                    submitted remains on record with your identity removed.
                    Any moderation record involving your account remains on
                    record the same way. This cannot be undone.
                </p>

                <div class="delete-account-field">
                    <label for="deleteAccountPassword">Current password</label>
                    <input
                        id="deleteAccountPassword"
                        type="password"
                        autocomplete="current-password"
                        required
                    >
                </div>

                <div class="delete-account-field">
                    <label for="deleteAccountPhrase">
                        Type <strong>${escapeHtml(DELETE_ACCOUNT_CONFIRMATION_PHRASE)}</strong> to confirm
                    </label>
                    <input
                        id="deleteAccountPhrase"
                        type="text"
                        autocomplete="off"
                        autocapitalize="off"
                        spellcheck="false"
                        required
                    >
                </div>

                <div class="modal-actions">
                    <button type="button" class="btn btn-secondary" data-action="cancel">Cancel</button>
                    <button type="button" class="btn btn-danger" data-action="confirm" disabled>Delete Account</button>
                </div>
            </div>
        `;

        document.body.appendChild(dialog);

        const passwordInput = dialog.querySelector("#deleteAccountPassword");
        const phraseInput = dialog.querySelector("#deleteAccountPhrase");
        const confirmBtn = dialog.querySelector('[data-action="confirm"]');

        function updateConfirmState() {
            const passwordFilled = passwordInput.value.length > 0;
            const phraseMatches = phraseInput.value === DELETE_ACCOUNT_CONFIRMATION_PHRASE;
            confirmBtn.disabled = !(passwordFilled && phraseMatches);
        }

        passwordInput.addEventListener("input", updateConfirmState);
        phraseInput.addEventListener("input", updateConfirmState);

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

        dialog.querySelector('[data-action="cancel"]').addEventListener("click", () => finish(null));
        dialog.addEventListener("cancel", () => finish(null));
        dialog.addEventListener("click", event => {
            if (event.target === dialog) finish(null);
        });

        confirmBtn.addEventListener("click", () => {
            if (confirmBtn.disabled) return;
            finish({ password: passwordInput.value });
        });

        dialog.showModal();
        requestAnimationFrame(() => dialog.classList.add("is-open"));
        passwordInput.focus();
    });
}
