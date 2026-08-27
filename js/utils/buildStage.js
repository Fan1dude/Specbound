// Single source of truth for build.status -> display label/color-class,
// extracted from BlueprintCard.js's own (previously private, unexported)
// getStage() so it can be shared with the Home Featured Spotlight
// (js/features/featured.js) without a second, independently-maintained
// copy of this mapping. Must stay in sync with
// js/services/draftValidation.js's CANONICAL_STATUSES (the four values a
// client can ever WRITE) — "building" is kept here only as a defensive,
// read-only legacy alias for "in_progress" (grouped as "Project", same as
// BlueprintCard has always done), for any not-yet-migrated historical
// revision snapshot; nothing should ever write it again (see
// draftValidation.js's own comment on this exact point).
export function getBuildStage(status) {
    switch (status) {
        case "planning":
            return {
                label: "Blueprint",
                className: "is-planning"
            };

        case "building":
        case "in_progress":
            return {
                label: "Project",
                className: "is-project"
            };

        case "completed":
            return {
                label: "Completed Build",
                className: "is-completed"
            };

        case "paused":
            return {
                label: "Paused",
                className: "is-paused"
            };

        default:
            return {
                label: "Blueprint",
                className: "is-planning"
            };
    }
}
