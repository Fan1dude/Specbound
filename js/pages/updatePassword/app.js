import { loadNavbar, loadFooter } from "../../core/layout.js";
import { supabase } from "../../core/supabase.js";
import { showToast } from "../../core/toast.js";

loadNavbar("../");
loadFooter("../");

const intro = document.getElementById("updatePasswordIntro");
const form = document.getElementById("updatePasswordForm");
const invalidLinkMessage = document.getElementById("updatePasswordInvalidLink");
const submitButton = document.getElementById("updatePasswordSubmit");

let recoveryResolved = false;

function showForm() {
    if (recoveryResolved) return;
    recoveryResolved = true;

    intro.textContent = "Enter a new password for your account.";
    form.hidden = false;
}

function showInvalidLink() {
    if (recoveryResolved) return;
    recoveryResolved = true;

    intro.textContent = "This reset link is invalid or has expired.";
    invalidLinkMessage.hidden = false;
}

// Supabase's client parses the recovery token out of the URL on load and
// fires PASSWORD_RECOVERY once it's established a session from it — this
// is the documented, specific signal for "a real reset link brought this
// visitor here," not just "some session exists." A visitor who lands on
// this page any other way (no token, an already-used link, an expired
// one) never gets this event.
supabase.auth.onAuthStateChange((event) => {
    if (event === "PASSWORD_RECOVERY") {
        showForm();
    }
});

// If no recovery token was present at all, the event above never fires —
// this is what actually surfaces that case instead of leaving "Checking
// your reset link..." up indefinitely.
setTimeout(() => {
    if (!recoveryResolved) showInvalidLink();
}, 3000);

form.addEventListener("submit", async (event) => {
    event.preventDefault();

    const newPassword = document.getElementById("newPassword").value;
    const confirmPassword = document.getElementById("confirmPassword").value;

    if (newPassword !== confirmPassword) {
        showToast("Those passwords don't match.", "warning");
        return;
    }

    submitButton.disabled = true;
    submitButton.textContent = "Updating...";

    const { error } = await supabase.auth.updateUser({ password: newPassword });

    if (error) {
        console.error("Password update error:", { code: error.code, message: error.message });
        showToast(error.message || "Could not update your password. Try requesting a new link.", "error");
        submitButton.disabled = false;
        submitButton.textContent = "Set New Password";
        return;
    }

    showToast("Password updated.", "success");

    // updateUser() succeeding leaves the visitor signed in on the
    // recovery session, so this goes to the signed-in home experience,
    // not back to login.
    setTimeout(() => {
        window.location.href = "../index.html";
    }, 1200);
});
