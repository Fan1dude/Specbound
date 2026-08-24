import { loadNavbar, loadFooter } from "../../core/layout.js";
import { showToast } from "../../core/toast.js";
import { requireAuth } from "../../core/auth.js";
import { createDraft } from "../../repositories/draftRepository.js";
import { TECHNOLOGIES, getTechnology } from "../../config/technologies/index.js";
import { TechnologyRadioCard } from "../../components/TechnologyRadioCard.js";
import { hydrateTechnologyPickerCards } from "../../components/technologyPickerShared.js";
import {
    saveContinuationState,
    readContinuationState,
    clearContinuationState
} from "../../utils/uploadContinuation.js";

loadNavbar("../");
loadFooter("../");

// A signed-out visitor can pick a technology and start typing a title,
// then get auth-gated at submit (see the submit handler below) — without
// this, they'd land back here after login with everything reset. The
// technology id travels in ?technology= (short, known-safe, fine in a
// URL); the title is free text, so it never goes in the URL and instead
// rides in localStorage (see js/utils/uploadContinuation.js for why
// localStorage over sessionStorage). Validated against the same
// TECHNOLOGIES list the grid itself renders from (getTechnology()
// returns null for anything unrecognized — a stale, tampered, or
// just-plain-wrong ?technology= value is silently ignored, same as if
// none were present) rather than trusting the query string's shape on
// its own.
const restoredTechnology = getTechnology(
    new URLSearchParams(window.location.search).get("technology")
);

// Only consulted when the URL already carries a matching ?technology= --
// i.e. only right after actually completing the auth continuation, never
// on an ordinary direct visit to this page. See readContinuationState()'s
// own doc comment for why that's what keeps a stale record from ever
// overwriting fresh user input.
const restoredContinuation = restoredTechnology
    ? readContinuationState(restoredTechnology.id)
    : null;

if (restoredContinuation) {
    const titleInput = document.getElementById("title");
    if (titleInput) titleInput.value = restoredContinuation.title;

    // Consumed successfully -- restoration has been applied to the DOM,
    // so the temporary record has served its purpose.
    clearContinuationState();
}

// Milestone 21: replaces the old hardcoded <select id="category"
// required> with a card grid generated from TECHNOLOGIES — the same
// config the editor's specifications/filters already treat as the
// single source of truth, instead of a second, separately-maintained
// list of options. See js/components/TechnologyRadioCard.js for why a
// real <input type="radio" required> (not a custom widget) preserves the
// exact validation/stored-value contract the old <select> had.
const technologyGrid = document.getElementById("technologyPickerGrid");

if (technologyGrid) {
    technologyGrid.innerHTML = TECHNOLOGIES
        .map(technology => TechnologyRadioCard(technology, {
            pathPrefix: "../",
            checked: technology.id === restoredTechnology?.id
        }))
        .join("");

    hydrateTechnologyPickerCards(technologyGrid);
}

// Once the restored selection has been applied to the DOM above, drop
// ?technology= from the visible URL — it's served its purpose, and
// leaving it in place would silently re-apply a now-stale selection on
// every future refresh/bookmark of this exact URL.
if (restoredTechnology) {
    const url = new URL(window.location.href);
    url.searchParams.delete("technology");
    window.history.replaceState(null, "", url.pathname + url.search + url.hash);
}

const form = document.getElementById("createDraftForm");
const submitButton = document.getElementById("createDraftSubmit");

// Synchronous, checked before any await — a disabled <button> stops a
// second real click, but a rapid double-Enter/double-click pair can both
// dispatch "submit" before the first await (requireAuth's own auth
// round-trip) resolves and the disabled state actually applies. This
// flag closes that gap the same way editor/app.js's isPublishing does.
let isSubmitting = false;

form.addEventListener("submit", async event => {
    event.preventDefault();

    if (isSubmitting) return;
    isSubmitting = true;

    try {
        const category = document.querySelector('input[name="category"]:checked')?.value || "";

        if (!category) {
            showToast("Choose a technology before continuing.", "warning");
            return;
        }

        submitButton.disabled = true;
        submitButton.textContent = "Creating...";

        const title = document.getElementById("title").value.trim();

        // Both fields are already known here, before the auth check —
        // snapshotted so a signed-out visitor's title and technology pick
        // survive the redirect instead of just vanishing. Written
        // unconditionally: at this point it isn't yet known whether
        // requireAuth() will find a user or redirect away, and by the
        // time it returns null the navigation may already be under way.
        // If the user turns out to already be authenticated, the
        // now-unneeded record is cleared right below instead.
        saveContinuationState({ technology: category, title });

        // requireAuth() only navigates away when there's no user; on that
        // path this function's own state doesn't matter anymore (the
        // page is leaving), so nothing past this point needs to run.
        const user = await requireAuth(buildLoginContinuationPath(category));
        if (!user) return;

        // Already authenticated -- the continuation record written above
        // was never needed for this attempt, so it's cleared here rather
        // than left to expire on its own.
        clearContinuationState();

        const draft = await createDraft({ userId: user.id, title, category });

        window.location.href = `build/edit.html?draft=${draft.id}`;
    } catch (error) {
        console.error("Draft creation error:", error);

        showToast(
            error.message?.includes("relation") || error.message?.includes("table")
                ? "The project editor isn't fully set up yet. Try again shortly."
                : error.message || "Could not create project.",
            "error"
        );

        submitButton.disabled = false;
        submitButton.textContent = "Continue to Editor";
    } finally {
        isSubmitting = false;
    }
});

// login.html's own ?redirect= reads this back through
// getSafeRedirectTarget() (js/utils/safeRedirect.js) before ever
// navigating anywhere with it — building it here only has to produce a
// same-directory, application-relative string; it doesn't have to (and
// shouldn't need to) re-implement that validation itself.
function buildLoginContinuationPath(category) {
    const continueTo = `upload.html?technology=${encodeURIComponent(category)}`;

    return `login.html?redirect=${encodeURIComponent(continueTo)}`;
}
