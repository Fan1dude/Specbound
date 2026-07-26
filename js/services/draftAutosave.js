import { saveLocalBuffer, clearLocalBuffer } from "./draftRecovery.js";

const DEBOUNCE_MS = 1500;

// Debounced autosave for a single draft. One controller per draft, shared
// across every editor section (not one per section), so there is exactly
// one save pipeline and one status indicator no matter how many sections
// exist. `save(fields)` is called with only the fields that changed since
// the last flush. `onStatusChange(status, savedAt)` fires with
// "unsaved" | "saving" | "saved" | "error".
export function createAutosaveController({ draftId, save, onStatusChange }) {
    let timer = null;
    let pendingFields = {};

    function scheduleSave(fields) {
        pendingFields = { ...pendingFields, ...fields };
        saveLocalBuffer(draftId, pendingFields);
        onStatusChange("unsaved");

        clearTimeout(timer);
        timer = setTimeout(flush, DEBOUNCE_MS);
    }

    async function flush() {
        clearTimeout(timer);

        if (Object.keys(pendingFields).length === 0) return;

        const fieldsToSave = pendingFields;
        pendingFields = {};

        onStatusChange("saving");

        try {
            const saved = await save(fieldsToSave);
            clearLocalBuffer(draftId);
            onStatusChange("saved", saved?.updated_at || new Date().toISOString());
        } catch (error) {
            // Put the fields back so the next flush (retry or manual) still
            // includes them — a failed save must never silently drop input.
            // The local buffer already has them either way.
            pendingFields = { ...fieldsToSave, ...pendingFields };
            onStatusChange("error");
            throw error;
        }
    }

    function hasPendingChanges() {
        return Object.keys(pendingFields).length > 0;
    }

    return { scheduleSave, flushNow: flush, hasPendingChanges };
}
