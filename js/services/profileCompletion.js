// Pure, no-I/O, re-run-on-every-render — mirrors draftValidation.js's
// getReadinessChecks() contract exactly, the same pattern already proven
// for the editor's readiness checklist. Takes only `profile` and touches
// no storage of any kind: this must produce a correct result identically
// whether or not localStorage exists, is disabled, or is full. The
// dismiss affordance on the card wrapping this (renderProfileChecklist.js)
// is the only part of the feature that touches storage — never this.
export function getProfileCompletionChecks(profile) {
    return [
        { key: "username", label: "Username", passed: Boolean(profile.username) },
        { key: "display_name", label: "Display name", passed: Boolean((profile.display_name || "").trim()) },
        { key: "avatar", label: "Avatar", passed: Boolean(profile.avatar_path || profile.avatar_url) },
        { key: "headline", label: "Headline", passed: Boolean((profile.headline || "").trim()) },
        { key: "bio", label: "Bio", passed: Boolean((profile.bio || "").trim()) }
    ];
}

export function isProfileComplete(checks) {
    return checks.every(check => check.passed);
}
