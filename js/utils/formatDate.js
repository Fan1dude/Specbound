export function formatDate(value) {
    if (!value) return "Recently";

    return new Date(value).toLocaleDateString(undefined, {
        year: "numeric",
        month: "long",
        day: "numeric"
    });
}

// Milestone 24 — the moderation queue needs a precise submitted/resolved
// timestamp (not just a date), unlike every existing formatDate() caller.
// Additive sibling export, not a change to formatDate()'s own contract —
// every other call site keeps its current date-only output.
export function formatDateTime(value) {
    if (!value) return "Unknown time";

    return new Date(value).toLocaleString(undefined, {
        year: "numeric",
        month: "short",
        day: "numeric",
        hour: "numeric",
        minute: "2-digit"
    });
}
