// Shared by the navbar bell dropdown and the dedicated Notifications page
// — message text and destination are computed from the notification's
// type + its enriched actor/build (see notificationRepository.js's
// enrichNotifications()) at render time, not stored, so an actor's later
// username change or a build's later title edit is always reflected.

export function formatNotificationText(notification) {
    const actorName = notification.actor?.username || "Someone";
    const buildTitle = notification.build?.title || "your project";

    switch (notification.type) {
        case "comment":
            return `${actorName} commented on ${buildTitle}`;

        case "reply":
            return `${actorName} replied on ${buildTitle}`;

        case "like":
            return `${actorName} liked ${buildTitle}`;

        case "save":
            return `${actorName} saved ${buildTitle}`;

        default:
            return `${actorName} interacted with ${buildTitle}`;
    }
}

export function getNotificationUrl(notification, pathPrefix = "") {
    const slug = notification.build?.slug || "";
    const base = `${pathPrefix}pages/build/build.html?slug=${encodeURIComponent(slug)}`;

    return notification.type === "comment" || notification.type === "reply"
        ? `${base}#commentsList`
        : base;
}

export function formatRelativeTime(value) {
    if (!value) return "recently";

    const date = new Date(value);

    if (Number.isNaN(date.getTime())) return "recently";

    const seconds = Math.round((Date.now() - date.getTime()) / 1000);

    if (seconds < 60) return "just now";

    const minutes = Math.round(seconds / 60);
    if (minutes < 60) return `${minutes}m ago`;

    const hours = Math.round(minutes / 60);
    if (hours < 24) return `${hours}h ago`;

    const days = Math.round(hours / 24);
    if (days < 7) return `${days}d ago`;

    return date.toLocaleDateString(undefined, { month: "short", day: "numeric", year: "numeric" });
}
