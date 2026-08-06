import { getTechnology } from "../../config/technologies/index.js";

// Builder Journey — curated milestones, not a raw revision feed. See
// docs/milestones/MILESTONE_20_BUILDER_PORTFOLIO_SPECIFICATION.md §3.3(d),
// §17.4. Five event sources, all derived from data that already exists:
//   - "published": one per public build, dated builds.created_at (the
//     moment publish_draft() inserts the row — the closest available
//     proxy to a true "published at" timestamp).
//   - "completed": one per build with status "completed", dated
//     builds.updated_at (best available proxy — there is no dedicated
//     completed_at column or a status-change history log).
//   - "milestone": any revision with milestone = true — reuses a flag
//     builders already set themselves, the most direct "this was a big
//     deal" signal available.
//   - "first-in-category": the earliest public build per distinct
//     category.
//   - "major-version": a revision whose freeform `version` text matches
//     MAJOR_VERSION_PATTERN. Deliberately conservative — version is not a
//     structured field, so an ambiguous value ("1.0.1", "Update 2", "v1")
//     is skipped rather than guessed at. Getting this under- or
//     over-inclusive only affects what surfaces in a highlight list, never
//     what gets written, so an occasional miss is low-stakes.
//
// No de-duplication: a single build legitimately contributing multiple
// events (published + completed + first-in-category, say) is a feature —
// a builder's biggest project earning more than one journey entry — not a
// bug to suppress.
const MAJOR_VERSION_PATTERN = /^v?\d+\.0$/i;

export function buildBuilderJourney(builds, revisions, { limit = 10 } = {}) {
    const events = [];

    for (const build of builds) {
        events.push({
            type: "published",
            date: build.created_at,
            build,
            label: `Published ${build.title}`
        });

        if (build.status === "completed") {
            events.push({
                type: "completed",
                date: build.updated_at,
                build,
                label: `Completed ${build.title}`
            });
        }
    }

    for (const build of firstBuildPerCategory(builds)) {
        const technology = getTechnology(build.category);
        events.push({
            type: "first-in-category",
            date: build.created_at,
            build,
            label: `First ${technology ? technology.title : build.category} project: ${build.title}`
        });
    }

    for (const revision of revisions) {
        const isMajorVersion = MAJOR_VERSION_PATTERN.test((revision.version || "").trim());
        if (!revision.milestone && !isMajorVersion) continue;

        events.push({
            type: revision.milestone ? "milestone" : "major-version",
            date: revision.created_at,
            build: revision.builds,
            label: revision.milestone
                ? (revision.snapshot_title || revision.title || "Milestone update")
                : `${revision.builds.title} reached ${revision.version}`
        });
    }

    return events
        .sort((a, b) => new Date(b.date) - new Date(a.date))
        .slice(0, limit);
}

function firstBuildPerCategory(builds) {
    const firstByCategory = new Map();
    for (const build of builds) {
        const existing = firstByCategory.get(build.category);
        if (!existing || new Date(build.created_at) < new Date(existing.created_at)) {
            firstByCategory.set(build.category, build);
        }
    }
    return firstByCategory.values();
}
