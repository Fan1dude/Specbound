import { icon } from "../utils/icons.js";
import { markOnboardingWelcomed } from "../repositories/profileRepository.js";
import { createDraft } from "../repositories/draftRepository.js";
import { TECHNOLOGIES } from "../config/technologies/index.js";
import { TechnologyChooserButton } from "./TechnologyChooserButton.js";
import { hydrateTechnologyPickerCards } from "./technologyPickerShared.js";

// First-sign-in Welcome dialog (Milestone 21). Built on the same native
// <dialog> construction as confirmDialog() (utils/modal.js) — showModal()
// gives an accessible focus trap and Esc handling for free, close()
// automatically returns focus to whatever had focus before this opened.
// Two content shapes swapped within one dialog element (Welcome step,
// then a technology-chooser step), not two separate <dialog>s, so the
// focus-trap/backdrop wiring is written once.
//
// Must never trap the user: every exit path (the visible Skip control,
// Esc, backdrop click, or completing the chooser) closes the dialog
// immediately — none of them wait on the network write below.
export function showWelcomeDialog({ user, profile, pathPrefix = "" }) {
    const dialog = document.createElement("dialog");
    dialog.className = "modal modal-onboarding";

    // Captured before showModal() moves focus into the dialog. In the
    // normal case (this dialog opens automatically on page load, not
    // from a click) this is <body> and refocusing it is a no-op — but
    // the mechanism is real and general, not just assumed via the
    // browser's own implicit restore, per the explicit "focus
    // restoration" requirement for this dialog.
    const previouslyFocused = document.activeElement;

    dialog.innerHTML = welcomeStepMarkup();
    document.body.appendChild(dialog);

    // Exactly once, on whichever exit path happens first — see
    // markExited() below. A second call (e.g. closing the chooser step
    // after Continue already marked it) must not write or navigate twice.
    let exited = false;

    function markExited() {
        if (exited) return;
        exited = true;

        // Fire-and-forget: the dialog already closed synchronously in
        // finish() below by the time this runs. A failed save only means
        // this account may see the Welcome dialog again on a later
        // session (never this one — core/onboarding.js's sessionStorage
        // guard, already set before this dialog was even shown, handles
        // that) — it never blocks or reverses the fact that the user has
        // already exited it.
        markOnboardingWelcomed(profile.id).catch(error => {
            console.error("Could not save onboarding_welcomed_at:", error);
        });
    }

    function finish() {
        dialog.classList.remove("is-open");

        // Matches --duration-fast (150ms), same asymmetry as
        // confirmDialog() — close is always faster than open.
        setTimeout(() => {
            dialog.close();
            dialog.remove();
        }, 150);

        if (previouslyFocused && typeof previouslyFocused.focus === "function") {
            previouslyFocused.focus();
        }
    }

    function closeWelcome() {
        markExited();
        finish();
    }

    function goToChooser() {
        markExited();

        dialog.innerHTML = chooserStepMarkup();
        wireChooserStep();

        // The dialog itself is unchanged (still open, still focus-trapped)
        // — only its content swapped, so refocus the new step's first
        // control rather than leaving focus on a now-detached element.
        dialog.querySelector(".modal-onboarding-close")?.focus();
    }

    function wireWelcomeStep() {
        dialog.querySelector('[data-action="skip"]').addEventListener("click", closeWelcome);
        dialog.querySelector('[data-action="continue"]').addEventListener("click", goToChooser);
    }

    function wireChooserStep() {
        dialog.querySelector('[data-action="skip"]').addEventListener("click", closeWelcome);

        const grid = dialog.querySelector(".technology-picker-grid");
        if (!grid) return;

        hydrateTechnologyPickerCards(grid);

        grid.addEventListener("click", async event => {
            const button = event.target.closest("[data-category-id]");
            if (!button) return;

            grid.querySelectorAll("button").forEach(b => { b.disabled = true; });

            try {
                const draft = await createDraft({ userId: user.id, title: "", category: button.dataset.categoryId });
                finish();
                window.location.href = `${pathPrefix}pages/build/edit.html?draft=${draft.id}`;
            } catch (error) {
                console.error("Could not create draft from Welcome dialog:", error);
                grid.querySelectorAll("button").forEach(b => { b.disabled = false; });
            }
        });
    }

    // Esc fires the dialog's native "cancel" event before "close" — same
    // handling confirmDialog() already relies on. Never prevented, so
    // Esc always works regardless of which step is showing.
    dialog.addEventListener("cancel", () => {
        closeWelcome();
    });

    // Click on the ::backdrop (the dialog element itself, outside its
    // content) — <dialog> has no built-in "click outside to dismiss."
    dialog.addEventListener("click", event => {
        if (event.target === dialog) closeWelcome();
    });

    wireWelcomeStep();

    dialog.showModal();

    // Deferred to the next frame so the opening transition (modal.css)
    // actually animates from its starting state instead of the browser
    // painting the open state immediately — same pattern as
    // confirmDialog(). prefers-reduced-motion is handled globally
    // (base/animations.css collapses every transition's duration), not
    // reimplemented here.
    requestAnimationFrame(() => dialog.classList.add("is-open"));

    function welcomeStepMarkup() {
        return `
            <button type="button" class="modal-onboarding-close" data-action="skip" aria-label="Skip">
                ${icon("close", 16)}
            </button>
            <div class="modal-body">
                <h2 class="modal-title">Welcome to Specbound</h2>
                <p class="modal-message">Document each stage of what you build—from the first idea to the finished project.</p>
                <div class="modal-actions">
                    <button type="button" class="btn btn-primary" data-action="continue">Continue</button>
                </div>
            </div>
        `;
    }

    function chooserStepMarkup() {
        const grid = TECHNOLOGIES
            .map(technology => TechnologyChooserButton(technology, { pathPrefix }))
            .join("");

        return `
            <button type="button" class="modal-onboarding-close" data-action="skip" aria-label="Skip">
                ${icon("close", 16)}
            </button>
            <div class="modal-body">
                <h2 class="modal-title">What are you documenting?</h2>
                <div class="technology-picker-grid">${grid}</div>
            </div>
        `;
    }
}
