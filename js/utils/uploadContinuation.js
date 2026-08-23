// Carries Create Blueprint's pre-auth form state (title + technology)
// across the login/signup redirect. Deliberately NOT sessionStorage: the
// realistic path here is signup's "check your email to confirm" branch
// (see js/pages/signup/app.js), and Supabase's confirmation link is
// opened from an external mail client with no code-level guarantee it
// lands back in the same browser tab — sessionStorage's per-tab scoping
// would silently fail to restore anything on exactly that path.
// localStorage survives across tabs within the same browser, at the cost
// of needing its own expiry (below) since nothing clears it on tab close.
//
// Only title + technology are handled here because those are the only
// two fields pages/upload.html exposes before requireAuth() runs — see
// that file's <form id="createDraftForm">.
//
// MAX_TITLE_LENGTH is imported, not redefined, so restoration can never
// place a title into the field that the app's own domain rule (used at
// publish-readiness time, js/services/draftValidation.js) would already
// consider too long — one canonical limit, not a second, more permissive
// one that quietly disagrees with it.
import { MAX_TITLE_LENGTH } from "../services/draftValidation.js";

const STORAGE_KEY = "specbound:createDraftContinuation";
const SCHEMA_VERSION = 1;

// Long enough that a visitor who leaves to go find a confirmation email
// and comes back doesn't lose their draft over normal delay; short enough
// that an abandoned attempt doesn't sit in localStorage indefinitely.
const EXPIRATION_MS = 30 * 60 * 1000;

// Called right before a signed-out submit redirects to login.html — the
// one moment this state would otherwise be lost outright. Written
// unconditionally (even when the user turns out to already be
// authenticated, since that's only known after this point) rather than
// trying to predict auth state ahead of requireAuth() itself; see
// clearContinuationState()'s call on the authenticated-success path in
// upload/app.js for the corresponding cleanup.
export function saveContinuationState({ technology, title }) {
    try {
        localStorage.setItem(STORAGE_KEY, JSON.stringify({
            version: SCHEMA_VERSION,
            technology,
            title,
            savedAt: Date.now()
        }));
    } catch {
        // Quota exceeded, storage disabled, private-mode restrictions --
        // this is a convenience restore, never load-bearing for the
        // redirect itself, so a write failure is silently ignored.
    }
}

// Returns { technology, title } only when a stored record exists, is
// well-formed, hasn't expired, and matches expectedTechnology -- the
// current page's own already-validated ?technology= id (see
// js/pages/upload/app.js). That match requirement is what stops a stale
// record from a different, unrelated attempt from ever overwriting
// whatever the user is looking at right now: restoration only runs at
// all when the URL already carries the matching ?technology=, which is
// itself only ever present immediately after completing this exact
// continuation flow, never on an ordinary direct visit.
export function readContinuationState(expectedTechnology) {
    let raw;

    try {
        raw = localStorage.getItem(STORAGE_KEY);
    } catch {
        return null;
    }

    if (!raw) return null;

    let parsed;

    try {
        parsed = JSON.parse(raw);
    } catch {
        clearContinuationState();
        return null;
    }

    const hasValidShape = (
        parsed &&
        typeof parsed === "object" &&
        parsed.version === SCHEMA_VERSION &&
        typeof parsed.savedAt === "number" &&
        typeof parsed.technology === "string" &&
        typeof parsed.title === "string"
    );

    if (!hasValidShape) {
        clearContinuationState();
        return null;
    }

    // Normalized once, here, and this same normalized value is what gets
    // both validated below and returned at the end -- never the raw
    // stored string. Validating a trimmed copy but returning parsed.title
    // itself would let a title padded with enough whitespace pass the
    // length check while still handing back a raw string longer than
    // MAX_TITLE_LENGTH once restored into the DOM, defeating the entire
    // point of bounding it against the app's own domain rule. Trimming
    // here also matches draftValidation.js's own isValidTitle(), and
    // matches upload/app.js's own submit-time
    // `document.getElementById("title").value.trim()` -- so a
    // whitespace-only snapshot normalizes to "", restoring the same empty
    // state the create form itself would end up with.
    const normalizedTitle = parsed.title.trim();

    if (normalizedTitle.length > MAX_TITLE_LENGTH) {
        clearContinuationState();
        return null;
    }

    if (Date.now() - parsed.savedAt > EXPIRATION_MS) {
        clearContinuationState();
        return null;
    }

    if (!expectedTechnology || parsed.technology !== expectedTechnology) {
        // Not corrupt, just not a match for what's being restored right
        // now -- left in place rather than cleared, since a mismatch here
        // says nothing about whether the record is still good for its own
        // original technology.
        return null;
    }

    return { technology: parsed.technology, title: normalizedTitle };
}

// Called once restoration has actually been applied to the DOM (the
// "consumed successfully" moment), and also as a tidy-up on the
// already-authenticated success path where this state was written but
// never needed. Never called on an authentication failure -- that path
// never reaches upload.html at all, so the record is simply untouched
// and available for the next attempt.
export function clearContinuationState() {
    try {
        localStorage.removeItem(STORAGE_KEY);
    } catch {
        // ignore
    }
}
