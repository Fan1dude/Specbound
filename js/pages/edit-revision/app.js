import { loadNavbar, loadFooter } from "../../core/layout.js";
import { supabase } from "../../core/supabase.js";
import { showToast } from "../../core/toast.js";

loadNavbar("../");
loadFooter("../");

const form = document.getElementById("revisionForm");
const progress = document.getElementById("progress");
const progressValue = document.getElementById("progressValue");

const params = new URLSearchParams(window.location.search);
const revisionId = params.get("revision");

if (progress && progressValue) {
    progress.addEventListener("input", () => {
        progressValue.textContent = `${progress.value}%`;
    });
}

// Retired: this form used to update an existing build_revisions row
// directly, which now directly contradicts the platform's immutability
// rule for published revisions (see supabase/migrations/0002_publish_draft_and_visibility.sql
// — build_revisions has no update policy at all). The fields below still
// load for reference, but saving is no longer possible; there's no
// replacement "correct a past update" flow yet.
async function loadRevision() {
    const { data: revision, error } = await supabase
        .from("build_revisions")
        .select("*")
        .eq("id", revisionId)
        .single();

    if (error || !revision) {
        showToast("Could not load revision.", "error");
        return;
    }

    document.getElementById("title").value = revision.title || "";
    document.getElementById("description").value = revision.description || "";
    document.getElementById("version").value = revision.version || "v0.1";
    document.getElementById("progress").value = revision.progress || 0;
    document.getElementById("progressValue").textContent = `${revision.progress || 0}%`;
    document.getElementById("timeSpent").value = revision.attachments?.time_spent || "";
}

const submitButton = form?.querySelector("button[type=submit]");

if (submitButton) {
    submitButton.disabled = true;
    submitButton.textContent = "Unavailable";
}

form?.addEventListener("submit", event => {
    event.preventDefault();

    showToast(
        "Published revisions can no longer be edited.",
        "warning"
    );
});

loadRevision();
