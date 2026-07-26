import { loadNavbar, loadFooter } from "../../core/layout.js";
import { showToast } from "../../core/toast.js";

loadNavbar("../");
loadFooter("../");

const form = document.getElementById("revisionForm");
const progress = document.getElementById("progress");
const progressValue = document.getElementById("progressValue");

if (progress && progressValue) {
    progress.addEventListener("input", () => {
        progressValue.textContent = `${progress.value}%`;
    });
}

// Retired: this form used to insert directly into build_revisions. All
// published updates now go through a project draft and the
// publish_draft() transaction (see supabase/migrations/0002_publish_draft_and_visibility.sql),
// which locked down direct client writes to that table. There's no
// replacement UI yet for adding a standalone progress update — that's
// future scope.
const submitButton = form?.querySelector("button[type=submit]");

if (submitButton) {
    submitButton.disabled = true;
    submitButton.textContent = "Unavailable";
}

form?.addEventListener("submit", event => {
    event.preventDefault();

    showToast(
        "Adding revisions has moved into the project editor and isn't available here yet.",
        "warning"
    );
});
