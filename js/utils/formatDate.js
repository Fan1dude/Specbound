export function formatDate(value) {
    if (!value) return "Recently";

    return new Date(value).toLocaleDateString(undefined, {
        year: "numeric",
        month: "long",
        day: "numeric"
    });
}
