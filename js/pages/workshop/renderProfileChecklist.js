import { getProfileCompletionChecks, isProfileComplete } from "../../services/profileCompletion.js";
import { isOnboardingFlagSet, setOnboardingFlag } from "../../utils/onboardingLocalState.js";
import { escapeHtml } from "../../utils/escapeHtml.js";
import { icon } from "../../utils/icons.js";

// Deep-links each incomplete item straight to the relevant Settings
// field — Settings is a single flat form, so a plain #id fragment is
// enough; no bespoke deep-linking mechanism needed.
const SETTINGS_FIELD_IDS = {
    username: "username",
    display_name: "displayName",
    avatar: "avatar",
    headline: "headline",
    bio: "bio"
};

// Every onboarding phase, this one included, stays optional — nothing
// here is a publish gate. The checklist only reflects existing Settings
// fields back at the builder; it never blocks or requires anything
// beyond what publishing already required before Milestone 21.
//
// Only ever rendered from workshop.html, which lives in the same
// directory as settings.html — links below are plain siblings
// ("settings.html#field"), not pathPrefix-relative like the technology
// picker (which is shared across pages at different directory depths).
export function renderProfileChecklist(profile) {
    const card = document.getElementById("profileChecklistCard");
    if (!card || !profile) return;

    const dismissKey = `profileChecklistDismissed:${profile.id}`;

    if (isOnboardingFlagSet(dismissKey)) {
        card.hidden = true;
        return;
    }

    const checks = getProfileCompletionChecks(profile);

    if (isProfileComplete(checks)) {
        card.hidden = true;
        return;
    }

    card.hidden = false;

    const completeCount = checks.filter(check => check.passed).length;

    card.innerHTML = `
        <div class="profile-checklist-header">
            <div>
                <h2>Finish setting up your profile</h2>
                <p>${completeCount} of ${checks.length} complete — visible on your public profile once filled in.</p>
            </div>
            <button type="button" class="profile-checklist-dismiss" id="profileChecklistDismiss" aria-label="Dismiss">
                ${icon("close", 16)}
            </button>
        </div>
        <div class="profile-checklist-list" aria-label="Profile completion: ${completeCount} of ${checks.length} complete">
            ${checks.map(check => `
                <span class="profile-checklist-item${check.passed ? " is-complete" : ""}">
                    <span aria-hidden="true">${icon(check.passed ? "check" : "circle", 16)}</span>
                    ${check.passed
                        ? escapeHtml(check.label)
                        : `<a href="settings.html#${SETTINGS_FIELD_IDS[check.key]}">${escapeHtml(check.label)}</a>`}
                </span>
            `).join("")}
        </div>
    `;

    document.getElementById("profileChecklistDismiss")?.addEventListener("click", () => {
        setOnboardingFlag(dismissKey);
        card.hidden = true;
    });
}
