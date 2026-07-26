// Shared, pure validation rules for what a draft needs before it's ready to
// publish. Used by the editor's readiness checklist now, and intended to
// be the same function Milestone 5's publish gate calls — one set of rules,
// not two that can drift apart.
const MIN_TITLE_LENGTH = 3;
const MAX_TITLE_LENGTH = 100;
const MIN_DESCRIPTION_LENGTH = 20;

export function getReadinessChecks({ title, description, category, hasCoverImage }) {
    return [
        {
            key: "title",
            label: "Title",
            passed: isValidTitle(title)
        },
        {
            key: "description",
            label: "Description",
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
