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

        // Milestone 24 — resolve_report() (supabase/migrations/0028_
        // moderation.sql, shipped in Milestone 22 but never actually
        // triggered until this milestone wired up a caller) has always
        // notified the reporter with this type once their report is
        // resolved. build_id is intentionally never set for it (a report
        // isn't necessarily about a build at all — see that migration's
        // own comment), so this deliberately never names the actor or a
        // build, and never states the outcome: this milestone's own
        // resolution flow explicitly doesn't add reporter-facing outcome
        // disclosure, only that a decision was made.
        case "report_resolved":
            return "A moderator reviewed a report you submitted.";

        default:
            return `${actorName} interacted with ${buildTitle}`;
    }
}

export function getNotificationUrl(notification, pathPrefix = "") {
    // report_resolved never carries a build (see formatNotificationText()
    // above) — routing it through the build-link fallback below would
    // build a URL with an empty slug, a dead link. Notifications.html
    // itself is always a safe destination for a notification that has
    // nothing more specific to point at.
    if (notification.type === "report_resolved") {
        return `${pathPrefix}pages/notifications.html`;
    }

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
