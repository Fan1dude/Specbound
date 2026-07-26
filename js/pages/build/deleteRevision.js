import { supabase } from "../../core/supabase.js";
import { showToast } from "../../core/toast.js";

export function setupDeleteRevision() {

    document.addEventListener("click", async (e) => {

        const button = e.target.closest(".delete-revision-btn");

        if (!button) return;

        const confirmed = confirm("Delete this revision?");

        if (!confirmed) return;

        const revisionId = button.dataset.id;

        const { error } = await supabase
            .from("build_revisions")
            .delete()
            .eq("id", revisionId);

        if (error) {
            showToast(error.message, "error");
            return;
        }

        button.closest(".revision-card").remove();

        showToast("Revision deleted.", "success");

    });

}