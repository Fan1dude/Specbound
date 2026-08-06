import { loadNavbar, loadFooter } from "../../core/layout.js";
import { showToast } from "../../core/toast.js";
import { requireAuth } from "../../core/auth.js";
import { createDraft } from "../../repositories/draftRepository.js";
import { TECHNOLOGIES } from "../../config/technologies/index.js";
import { TechnologyRadioCard } from "../../components/TechnologyRadioCard.js";
import { hydrateTechnologyPickerCards } from "../../components/technologyPickerShared.js";

loadNavbar("../");
loadFooter("../");

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
        .map(technology => TechnologyRadioCard(technology, { pathPrefix: "../" }))
        .join("");

    hydrateTechnologyPickerCards(technologyGrid);
}

const form = document.getElementById("createDraftForm");
const submitButton = document.getElementById("createDraftSubmit");

form.addEventListener("submit", async event => {
    event.preventDefault();

    const user = await requireAuth("login.html");
    if (!user) return;

    const title = document.getElementById("title").value.trim();
    const category = document.querySelector('input[name="category"]:checked')?.value || "";

    if (!category) {
        showToast("Choose a technology before continuing.", "warning");
        return;
    }

    submitButton.disabled = true;
    submitButton.textContent = "Creating...";

    try {
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
    }
});
