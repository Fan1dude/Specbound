import { showWelcomeDialog } from "../components/WelcomeDialog.js";
import { hasSeenWelcomeThisSession, markWelcomeSeenThisSession } from "../utils/onboardingLocalState.js";

// Called from layout.js's loadNavbar() — the one place in the app that
// already runs on every authenticated page load and already resolves the
// session/profile, so this fires "on the first authenticated page load
// anywhere in the application," not just Home. layout.js stays thin and
// delegates here rather than growing dialog logic inline.
//
// Never causes layout shift or page-load flicker: the dialog element is
// only ever created (and only ever affects layout as an overlay — native
// <dialog> is never part of document flow) once eligibility below is
// already known — there is no placeholder/skeleton state to flash before
// or after it.
//
// One-time/promise guard: loadNavbar() is only expected to run once per
// page, but a second call (e.g. some future caller invoking it twice)
// must not evaluate onboarding state twice or risk opening a second
// dialog. Mirrors core/auth.js's getCurrentUser() cachedUserPromise
// pattern — never reset once set, since a page's onboarding eligibility
// doesn't change mid-page-load.
let onboardingCheckPromise = null;

export function maybeShowWelcome(user, profile, pathPrefix = "") {
    if (onboardingCheckPromise) return onboardingCheckPromise;

    onboardingCheckPromise = Promise.resolve().then(() => {
        if (!profile || profile.onboarding_welcomed_at) return;

        // A failed save in WelcomeDialog.js's exit handler means
        // onboarding_welcomed_at can still be null on a later page load
        // within the same browser session — this sessionStorage guard is
        // what actually prevents a second popup in that case, independent
        // of whether the DB write ever reached the server. Marked here,
        // before the dialog is even shown, so no code path can show it
        // twice in one session regardless of how it's eventually exited.
        if (hasSeenWelcomeThisSession()) return;

        markWelcomeSeenThisSession();
        showWelcomeDialog({ user, profile, pathPrefix });
    });

    return onboardingCheckPromise;
}
