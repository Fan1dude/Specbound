import { loadNavbar, loadFooter } from "../../core/layout.js";
import { supabase } from "../../core/supabase.js";

loadNavbar("../");
loadFooter("../");

const form = document.getElementById("forgotPasswordForm");
const submitButton = document.getElementById("forgotPasswordSubmit");
const messageEl = document.getElementById("forgotPasswordMessage");

// Supabase's resetPasswordForEmail() already doesn't error for an email
// that has no matching account (that's a deliberate anti-enumeration
// behavior on their side) — but every response this page shows to the
// visitor is still written to say the same thing regardless of outcome,
// on purpose. The one exception is a rate-limit response, which is safe
// to name specifically: it's identical for every caller regardless of
// whether the email exists, so it reveals nothing account-specific.
const GENERIC_MESSAGE = "If an account exists for that email, we've sent a link to reset your password. Check your inbox.";
const RATE_LIMIT_MESSAGE = "You've requested this recently — check your inbox, or try again in a few minutes.";
const FALLBACK_ERROR_MESSAGE = "Something went wrong. Try again in a moment.";

form.addEventListener("submit", async (event) => {
    event.preventDefault();

    const email = document.getElementById("email").value.trim();

    submitButton.disabled = true;
    submitButton.textContent = "Sending...";

    const { error } = await supabase.auth.resetPasswordForEmail(email, {
        redirectTo: new URL("updatePassword.html", window.location.href).href
    });

    let message = GENERIC_MESSAGE;

    if (error) {
        console.error("Password reset request error:", { code: error.code, status: error.status, message: error.message });
        message = error.status === 429 ? RATE_LIMIT_MESSAGE : FALLBACK_ERROR_MESSAGE;
    }

    messageEl.textContent = message;
    messageEl.hidden = false;

    submitButton.disabled = false;
    submitButton.textContent = "Send Reset Link";
});
