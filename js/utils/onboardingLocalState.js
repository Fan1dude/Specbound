// Namespaced, versioned onboarding dismiss/session state (Milestone 21).
// The "v1" suffix means a future change to what a key means can bump to
// "v2" and every prior value is naturally, harmlessly abandoned — no
// migration/cleanup code needed for that case.
//
// Every read/write is wrapped so a throwing storage (private browsing,
// quota exceeded, disabled entirely) never breaks the caller — even
// resolving the `localStorage`/`sessionStorage` global itself happens
// inside the try, not just the .getItem/.setItem call, since some
// hardened contexts throw on the property access itself, not just on use.
//
// Deliberately narrow: profile completion (services/profileCompletion.js)
// and first-publish detection (editor/app.js) never call into this file
// at all — both must be correct with storage fully unavailable, by
// construction, not just by convention.
const NAMESPACE = "specbound:onboarding:v1";

function safeStorageGet(kind, key) {
    try {
        const storage = kind === "session" ? sessionStorage : localStorage;
        return storage.getItem(key);
    } catch {
        return null;
    }
}

function safeStorageSet(kind, key) {
    try {
        const storage = kind === "session" ? sessionStorage : localStorage;
        storage.setItem(key, "1");
    } catch {
        // Best-effort only — the flag simply won't persist if storage is
        // unavailable. Never throws, never blocks the UI action that
        // triggered it.
    }
}

// Persistent (localStorage), cross-session dismiss flags — profile
// checklist card, editor hints. Device-local re-appearance on a new
// device/browser is an accepted, low-stakes outcome, unlike the
// Welcome dialog below.
export function isOnboardingFlagSet(key) {
    return safeStorageGet("local", `${NAMESPACE}:${key}`) === "1";
}

export function setOnboardingFlag(key) {
    safeStorageSet("local", `${NAMESPACE}:${key}`);
}

// Session-scoped (sessionStorage) — guards against the Welcome dialog
// reopening on a later page within the SAME browser session even when
// saving onboarding_welcomed_at to the server failed (see
// core/onboarding.js). Deliberately separate from the persistent flags
// above: this must clear when the tab/browser closes, not persist
// indefinitely, since a failed save should only suppress re-showing for
// the rest of the current session, not forever.
export function hasSeenWelcomeThisSession() {
    return safeStorageGet("session", `${NAMESPACE}:welcomeShownThisSession`) === "1";
}

export function markWelcomeSeenThisSession() {
    safeStorageSet("session", `${NAMESPACE}:welcomeShownThisSession`);
}
