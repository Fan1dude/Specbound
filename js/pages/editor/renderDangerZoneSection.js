import { deleteBuild } from "../../repositories/publishRepository.js";
import { deleteBuildStorageFiles } from "../../services/imageService.js";
import { confirmDialog } from "../../utils/modal.js";
import { showToast } from "../../core/toast.js";

// Launch Readiness Audit Finding 02 — published-build deletion only. A
// draft that has never been published has no builds row for
// delete_build() to operate on at all; deleting one of those is a
// separate, deliberately out-of-scope follow-up (see
// supabase/migrations/0043_delete_build.sql's own header). refresh()
// hides/disables this whole section for that case, both on initial load
// and after a delete succeeds (the draft becomes never-published again).
export function renderDangerZoneSection(draft, { onDeleted = () => {} } = {}) {
    const section = document.getElementById("editorDangerZone");
    const deleteBtn = document.getElementById("deletePublishedBuildBtn");

    if (!section || !deleteBtn) return { refresh() {} };

    let isDeleting = false;

    function refresh() {
        const isPublished = Boolean(draft.published_build_id);
        section.hidden = !isPublished;
        deleteBtn.disabled = !isPublished;
    }

    refresh();

    deleteBtn.addEventListener("click", async () => {
        if (isDeleting || !draft.published_build_id) return;

        const confirmed = await confirmDialog({
            title: "Delete this published build?",
            body:
                "Permanently removes the public build, its revisions, comments, likes, " +
                "and saves. This cannot be undone. Your editable draft and its images " +
                "will remain, and you can publish again later.",
            confirmLabel: "Delete Published Build",
            cancelLabel: "Cancel",
            danger: true
        });

        if (!confirmed) return;

        isDeleting = true;
        deleteBtn.disabled = true;
        deleteBtn.textContent = "Deleting...";

        const buildId = draft.published_build_id;

        try {
            const paths = await deleteBuild(buildId);

            // Best-effort second step -- the database deletion above has
            // already fully succeeded and committed. A failure here means
            // orphaned Storage files, never a reason to tell the owner
            // their deletion failed — see deleteBuildStorageFiles()'s own
            // comment in imageService.js.
            try {
                await deleteBuildStorageFiles(paths);
            } catch (storageError) {
                console.error(
                    "Delete build: Storage cleanup failed (the build itself was deleted successfully):",
                    storageError
                );
            }

            isDeleting = false;
            showToast("Build deleted. Your draft is unpublished and ready to edit.", "success");
            onDeleted();
        } catch (error) {
            // Deliberately a fixed message, never error.message — this
            // action's failure path must not surface raw internal/
            // Postgres error text to the user.
            console.error("Delete build error:", error);

            isDeleting = false;
            deleteBtn.disabled = false;
            deleteBtn.textContent = "Delete Published Build";
            deleteBtn.focus();

            showToast("Could not delete this build. Try again.", "error");
        }
    });

    return { refresh };
}
