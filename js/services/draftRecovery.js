const STORAGE_PREFIX = "specbound:draft:";

// Local safety net for autosave: mirrors in-progress field changes to
// localStorage immediately (not debounced) so a crashed tab or closed
// browser doesn't lose an edit that hadn't reached the server yet. Cleared
// once the server confirms it has the same data.
export function saveLocalBuffer(draftId, fields) {
    const existing = readLocalBuffer(draftId);
    const mergedFields = { ...(existing?.fields || {}), ...fields };

    localStorage.setItem(
        STORAGE_PREFIX + draftId,
        JSON.stringify({ updatedAt: new Date().toISOString(), fields: mergedFields })
    );
}

export function readLocalBuffer(draftId) {
    try {
        const raw = localStorage.getItem(STORAGE_PREFIX + draftId);
        return raw ? JSON.parse(raw) : null;
    } catch {
        return null;
    }
}

export function clearLocalBuffer(draftId) {
    localStorage.removeItem(STORAGE_PREFIX + draftId);
}

export function hasNewerLocalBuffer(draftId, serverUpdatedAt) {
    const buffer = readLocalBuffer(draftId);

    if (!buffer) return false;
    if (!serverUpdatedAt) return true;

    return new Date(buffer.updatedAt) > new Date(serverUpdatedAt);
}
