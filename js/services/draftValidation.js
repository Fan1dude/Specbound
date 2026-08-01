// Shared, pure validation rules for what a draft needs before it's ready to
// publish. Used by the editor's readiness checklist now, and intended to
// be the same function Milestone 5's publish gate calls — one set of rules,
// not two that can drift apart.
export const MIN_TITLE_LENGTH = 3;
export const MAX_TITLE_LENGTH = 100;
export const MIN_DESCRIPTION_LENGTH = 20;

export function getReadinessChecks({ title, description, category, hasCoverImage }) {
    return [
        {
            key: "title",
            label: "Title",
            passed: isValidTitle(title)
        },
        {
            key: "description",
            // States the actual requirement in the one place a builder is
            // already looking when trying to figure out why this item
            // won't complete — previously just "Description," with no
            // indication anywhere in the editor that a minimum length
            // applies at all, which reads as a bug (real, non-trivial
            // text rejected with zero explanation) rather than validation
            // working as intended. Sourced from MIN_DESCRIPTION_LENGTH
            // itself, not a second hardcoded "20," so the two can't drift.
            label: `Description (${MIN_DESCRIPTION_LENGTH}+ characters)`,
            passed: isValidDescription(description)
        },
        {
            key: "category",
            label: "Technology",
            passed: Boolean(category)
        },
        {
            key: "cover",
            label: "Cover image",
            passed: Boolean(hasCoverImage)
        }
    ];
}

export function isValidTitle(title) {
    const trimmed = (title || "").trim();
    return trimmed.length >= MIN_TITLE_LENGTH && trimmed.length <= MAX_TITLE_LENGTH;
}

export function isValidDescription(description) {
    return (description || "").trim().length >= MIN_DESCRIPTION_LENGTH;
}

export function isDraftReady(checks) {
    return checks.every(check => check.passed);
}
