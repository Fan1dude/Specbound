// Shared by renderProfileHero.js, renderBuilderOverview.js, and
// renderAboutBuilder.js — all three surface the same profile.created_at
// value in a slightly different phrasing, previously duplicated once
// (renderProfile.js) before the Builder Portfolio redesign split it
// across sections.
export function formatJoinDate(value, { yearOnly = false } = {}) {
    if (!value) return yearOnly ? "—" : "recently";

    const date = new Date(value);

    if (Number.isNaN(date.getTime())) return yearOnly ? "—" : "recently";

    if (yearOnly) {
        return String(date.getFullYear());
    }

    return date.toLocaleDateString(undefined, { month: "long", year: "numeric" });
}
