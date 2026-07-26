import { hasSavedBuild, setBuildSaved } from "../../repositories/savedRepository.js";
import { showToast } from "../../core/toast.js";

// Saves belong to the build, not a revision (see
// supabase/migrations/0009_saved_builds.sql) — called with the same
// `build` object from both renderBuild() (latest) and renderRevisionView()
// (historical revision), same as renderLike()/renderCreator().
export async function renderSave(build, currentUser) {
    const button = document.getElementById("saveBtn");
    const hint = document.getElementById("saveHint");

    if (!button) return;

    const isPublic = build.visibility === "public";

    let saved = false;

    if (currentUser) {
        try {
            saved = await hasSavedBuild(build.id);
        } catch (error) {
            // Fail soft, same reasoning as renderLike.js — a failed status
            // check shouldn't block the rest of the page. The button just
            // starts in the unsaved visual state.
            console.error("Save status load error:", error);
        }
    }

    setButtonState(saved);

    if (!currentUser) {
        button.disabled = true;
        setHint(`<a href="../login.html">Sign in</a> to save this project.`);
    } else if (!isPublic && !saved) {
        // A private project can't be newly saved (see set_build_saved()),
        // but it CAN still be unsaved if it was saved before going
        // private — so this disabled state only applies to the not-yet-
        // saved case, not to removing an existing save.
        button.disabled = true;
        setHint("Saving is only available while this project is public.");
    } else {
        button.disabled = false;
        setHint(null);
    }

    button.onclick = async () => {
        if (button.disabled) return;

        const nextSaved = !saved;
        const previousSaved = saved;

        saved = nextSaved;
        setButtonState(saved);
        button.disabled = true;

        try {
            const result = await setBuildSaved(build.id, nextSaved);

            saved = result;
            setButtonState(saved);

            showToast(saved ? "Saved to your Workshop." : "Removed from your saved projects.", "success");
        } catch (error) {
            console.error("Save update error:", error);

            saved = previousSaved;
            setButtonState(saved);

            showToast(error.message || "Could not update your saved projects.", "error");
        } finally {
            // Unsaving a since-privated project should stay clickable
            // afterward (still allowed); only "not public and not saved"
            // should end up disabled again.
            button.disabled = !currentUser || (!isPublic && !saved);
        }
    };

    function setButtonState(isSaved) {
        button.classList.toggle("is-saved", isSaved);
        button.setAttribute("aria-pressed", String(isSaved));
        button.textContent = isSaved ? "Saved" : "Save";
    }

    function setHint(html) {
        if (!hint) return;

        if (!html) {
            hint.hidden = true;
            hint.innerHTML = "";
            return;
        }

        hint.hidden = false;
        hint.innerHTML = html;
    }
}
