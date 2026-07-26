import { loadNavbar, loadFooter } from "../../core/layout.js";
import { showToast } from "../../core/toast.js";
import { requireAuth } from "../../core/auth.js";
import { createDraft } from "../../repositories/draftRepository.js";

loadNavbar("../");
loadFooter("../");

const form = document.getElementById("createDraftForm");
const submitButton = document.getElementById("createDraftSubmit");

form.addEventListener("submit", async event => {
    event.preventDefault();

    const user = await requireAuth("login.html");
    if (!user) return;

    const title = document.getElementById("title").value.trim();
    const category = document.getElementById("category").value;

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
