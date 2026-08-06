import { getMyPublishedBuildCount } from "../../repositories/dashboardRepository.js";
import { isOnboardingFlagSet, setOnboardingFlag } from "../../utils/onboardingLocalState.js";
import { icon } from "../../utils/icons.js";

// No hint for Description — the readiness checklist's own
// "Description (20+ characters)" label (services/draftValidation.js,
// Milestone 20) already carries that signal; a duplicate hint here would
// be redundant UI.
const HINTS = [
    { id: "title", elementId: "hintTitle", text: "A clear, specific title helps people find your build." },
    { id: "gallery", elementId: "hintGallery", text: "Your first image becomes the cover photo shown across the site." }
];

// Every onboarding phase remains optional, this one included — these are
// informational only, never a publish gate; dismissing a hint (or simply
// ignoring it) has no effect on whether the draft can be published.
//
// Gated by two things, neither of which needs a schema change: whether
// this account has ever published (computed live, every call — see
// dashboardRepository.getMyPublishedBuildCount's own comment on why it's
// not visibility-filtered) and whether the hint was already dismissed
// locally (namespaced, versioned localStorage — utils/onboardingLocalState.js).
export async function renderContextualHints(userId) {
    let publishedCount;

    try {
        publishedCount = await getMyPublishedBuildCount(userId);
    } catch (error) {
        // Fail closed: if we can't confirm this account has never
        // published, don't show hints meant only for first-timers.
        console.error("Contextual hints: could not check publish history:", error);
        return;
    }

    if (publishedCount > 0) return;

    for (const hint of HINTS) {
        const el = document.getElementById(hint.elementId);
        if (!el) continue;

        const dismissKey = `hint:${hint.id}:${userId}:dismissed`;
        if (isOnboardingFlagSet(dismissKey)) continue;

        el.hidden = false;
        el.innerHTML = `
            <span>${hint.text}</span>
            <button type="button" class="field-hint-dismiss" aria-label="Dismiss hint">${icon("close", 16)}</button>
        `;

        el.querySelector(".field-hint-dismiss").addEventListener("click", () => {
            setOnboardingFlag(dismissKey);
            el.hidden = true;
        });
    }
}
