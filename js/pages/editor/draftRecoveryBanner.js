import { readLocalBuffer, clearLocalBuffer, hasNewerLocalBuffer } from "../../services/draftRecovery.js";
import { showToast } from "../../core/toast.js";

// Offers to restore locally-buffered edits that never reached the server
// (closed tab, crash, dropped connection). Non-blocking — the form already
// renders with server data; this just offers a better copy if one exists.
export function maybeShowRecoveryBanner(draft, autosave, applyFields) {
    const banner = document.getElementById("draftRecoveryBanner");
    const restoreBtn = document.getElementById("recoveryRestoreBtn");
    const discardBtn = document.getElementById("recoveryDiscardBtn");

    if (!banner) return;

    // Explicit on both paths rather than relying solely on the HTML's
    // default `hidden` attribute — a CSS rule with matching specificity
    // silently defeated that default previously, so this no longer
    // assumes the element starts in the right state.
    if (!hasNewerLocalBuffer(draft.id, draft.updated_at)) {
        banner.hidden = true;
        return;
    }

    banner.hidden = false;

    restoreBtn.addEventListener("click", async () => {
        const buffer = readLocalBuffer(draft.id);

        if (!buffer) {
            banner.hidden = true;
            return;
        }

        restoreBtn.disabled = true;
        discardBtn.disabled = true;
        restoreBtn.textContent = "Restoring...";

        applyFields(buffer.fields);
        autosave.scheduleSave(buffer.fields);

        try {
            // Must wait for the save (and the clearLocalBuffer inside it) to
            // actually finish before treating this as resolved — otherwise
            // navigating away or reloading right after clicking Restore
            // leaves the buffer stuck, and the banner reappears on every
            // future load even though nothing is actually unsaved anymore.
            await autosave.flushNow();
            banner.hidden = true;
        } catch (error) {
            console.error("Recovery save error:", error);

            showToast(
                "Could not save the restored changes. They're still safe locally — try again.",
                "error"
            );

            restoreBtn.disabled = false;
            discardBtn.disabled = false;
            restoreBtn.textContent = "Restore";
        }
    });

    discardBtn.addEventListener("click", () => {
        clearLocalBuffer(draft.id);
        banner.hidden = true;
    }, { once: true });
}
