// Human-readable labels for every community role, automatic and manual —
// the single source of truth both the automatic-role computation below
// and js/components/RoleBadge.js render from, so the two never drift.
export const ROLE_LABELS = {
    new_builder: "New Builder",
    active_builder: "Active Builder",
    long_term_builder: "Long-Term Builder",
    community_builder: "Community Builder",
    project_mentor: "Project Mentor",
    moderator: "Moderator",
    staff: "Staff"
};

const MS_PER_DAY = 24 * 60 * 60 * 1000;
const ACTIVE_WINDOW_DAYS = 30;
const LONG_TERM_ACCOUNT_AGE_DAYS = 182; // ~6 months — day-based, not
// calendar-month arithmetic, deliberately: this is a qualitative
// long-tenure signal, not a legal/billing threshold, so avoiding
// calendar edge cases (Feb 30th, variable month lengths) is worth more
// than exact "6 calendar months" precision.

function daysSince(isoDate) {
    if (!isoDate) return Infinity;
    return (Date.now() - new Date(isoDate).getTime()) / MS_PER_DAY;
}

// Pure, computed, no storage — mirrors draftValidation.js's/
// profileCompletion.js's "pure function, re-run on every render"
// contract exactly. A builder has exactly one automatic role at a time
// (spec §5.1/§5.4) — a status, not a badge collection, and never stored
// anywhere (see supabase/migrations/0027_profile_roles.sql's own header
// for why automatic roles have no table row at all).
export function getAutomaticRole(profile, builds = []) {
    const hasRecentActivity = builds.some(build => daysSince(build?.updated_at) < ACTIVE_WINDOW_DAYS);
    const isLongTermAccount = daysSince(profile?.created_at) >= LONG_TERM_ACCOUNT_AGE_DAYS;

    if (isLongTermAccount && hasRecentActivity) return "long_term_builder";
    if (hasRecentActivity) return "active_builder";
    return "new_builder";
}
