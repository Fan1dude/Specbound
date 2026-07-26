export function setEditorStatus(statusEl, status, savedAt) {
    switch (status) {
        case "unsaved":
            statusEl.textContent = "Unsaved changes";
            return;

        case "saving":
            statusEl.textContent = "Saving...";
            return;

        case "error":
            statusEl.textContent = "Couldn't save — retrying";
            return;

        default:
            statusEl.textContent = savedAt
                ? `Last saved ${formatTime(savedAt)}`
                : "Saved";
    }
}

function formatTime(value) {
    const date = new Date(value);

    if (Number.isNaN(date.getTime())) return "just now";

    return date.toLocaleTimeString(undefined, {
        hour: "numeric",
        minute: "2-digit"
    });
}
