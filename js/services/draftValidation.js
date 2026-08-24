// Shared, pure validation rules for what a draft needs before it's ready to
// publish. Used by the editor's readiness checklist now, and intended to
// be the same function Milestone 5's publish gate calls — one set of rules,
// not two that can drift apart.
export const MIN_TITLE_LENGTH = 3;
export const MAX_TITLE_LENGTH = 100;
export const MIN_DESCRIPTION_LENGTH = 20;

// Must match supabase/migrations/0042_build_progress_and_status.sql's
// canonical status CHECK constraint exactly — one list, not two that can
// drift apart. "building" is a legacy value some historical/read-side
// code defensively treats as a synonym for "in_progress" (see
// BlueprintCard.js's getStage()); it's deliberately not included here —
// nothing should ever be able to *write* it again.
export const CANONICAL_STATUSES = ["planning", "in_progress", "paused", "completed"];
export const MIN_PROGRESS = 0;
export const MAX_PROGRESS = 100;

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

export function isValidStatus(status) {
    return CANONICAL_STATUSES.includes(status);
}

// Used to reject a corrupted/tampered crash-recovery value before it's
// ever applied to the DOM or scheduled for save — the database's own
// CHECK constraint is the real gate, this just stops obviously-invalid
// local data from being trusted in the meantime. Rounds rather than
// rejecting a non-integer input (e.g. a stale fractional value from a
// future change to the control) so a merely-imprecise but in-range
// number still restores usefully.
export function normalizeProgress(value) {
    // Number(null) === 0 and Number("") === 0 in JS -- neither is a real
    // progress value, both must be rejected rather than silently coerced
    // to a valid-looking 0. Restricting to number/non-empty-string inputs
    // up front avoids that whole class of coercion surprise (also catches
    // booleans/arrays/objects, none of which are real progress values
    // either).
    if (typeof value !== "number" && typeof value !== "string") return null;
    if (typeof value === "string" && value.trim() === "") return null;

    const number = Number(value);

    if (!Number.isFinite(number)) return null;

    const rounded = Math.round(number);

    if (rounded < MIN_PROGRESS || rounded > MAX_PROGRESS) return null;

    return rounded;
}

export function isDraftReady(checks) {
    return checks.every(check => check.passed);
}
