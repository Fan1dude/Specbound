import { escapeHtml } from "./escapeHtml.js";

// Shared confirmation modal — Milestone 10 brand refresh. Replaces this
// app's previous confirm() call sites (comment delete, gallery image
// delete, unpublish, restore revision) with a styled, on-brand <dialog>,
// per docs/milestones/MILESTONE_10_BRAND_REFRESH_ARCHITECTURE.md §7's Modals spec.
// Native <dialog> is used deliberately — accessible focus-trapping and
// Esc-to-close come from the browser for free, no custom JS needed for
// either.
//
// confirm() is synchronous; a <dialog> can't be, so every call site
// becomes `await confirmDialog(...)` instead of `confirm(...)` — the
// surrounding functions were already async, so this is a mechanical
// change, not a new pattern.
export function confirmDialog({ title, body, confirmLabel = "Confirm", cancelLabel = "Cancel", danger = false }) {
    return new Promise(resolve => {
        const dialog = document.createElement("dialog");
        dialog.className = "modal";

        dialog.innerHTML = `
            <div class="modal-body">
                <h2 class="modal-title">${escapeHtml(title)}</h2>
                <p class="modal-message">${escapeHtml(body)}</p>
                <div class="modal-actions">
                    <button type="button" class="btn btn-secondary" data-action="cancel">${escapeHtml(cancelLabel)}</button>
                    <button type="button" class="btn ${danger ? "btn-danger" : "btn-primary"}" data-action="confirm">${escapeHtml(confirmLabel)}</button>
                </div>
            </div>
        `;

        document.body.appendChild(dialog);

        let resolved = false;

        const finish = result => {
            if (resolved) return;
            resolved = true;

            dialog.classList.remove("is-open");
            // Matches --duration-fast (150ms) — close is always faster
            // than open, same asymmetry rule as every other
            // microinteraction in the design system.
            setTimeout(() => {
                dialog.close();
                dialog.remove();
            }, 150);

            resolve(result);
        };

        dialog.querySelector('[data-action="cancel"]').addEventListener("click", () => finish(false));
        dialog.querySelector('[data-action="confirm"]').addEventListener("click", () => finish(true));

        // Native Esc handling fires "cancel" before "close" — resolve
        // false there and let finish()'s `resolved` guard no-op the
        // "close" event that follows.
        dialog.addEventListener("cancel", () => finish(false));

        // Click on the ::backdrop (the dialog element itself, outside its
        // content) — <dialog> has no built-in "click outside to dismiss."
        dialog.addEventListener("click", event => {
            if (event.target === dialog) finish(false);
        });

        dialog.showModal();

        // Applied on the next frame so the opening transition (opacity +
        // scale, defined in modal.css) actually animates from its
        // starting state instead of the browser painting the open state
        // immediately.
        requestAnimationFrame(() => dialog.classList.add("is-open"));
    });
}
