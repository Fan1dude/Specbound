import { supabase } from "../../core/supabase.js";
import { deleteAccountDialog } from "../../components/DeleteAccountDialog.js";
import { deleteAccount, DELETE_ACCOUNT_REAUTH_REQUIRED } from "../../repositories/accountRepository.js";
import { showToast } from "../../core/toast.js";

// Launch Readiness self-service account deletion — Settings' Danger
// Zone section. Same "disabled control, loading label, fixed generic
// failure message, restored focus on failure" shape
// js/pages/editor/renderDangerZoneSection.js already establishes for
// per-build deletion, extended for the higher-stakes, account-wide
// action: password reauthentication and a typed confirmation phrase
// (DeleteAccountDialog.js) before anything is sent, and a full local
// sign-out + redirect on success rather than an in-page state update.
const GENERIC_FAILURE_MESSAGE = "Your request could not be completed. Try again, or contact support@specboundapp.com.";

// The default redirect is a real navigation — injectable so
// tests/renderDeleteAccountSection.test.html can drive the real success
// path without actually navigating the test page away mid-suite.
// Production callers never pass this; it exists solely for testability,
// same reason renderDangerZoneSection.js's own `onDeleted` callback
// exists.
export function renderDeleteAccountSection(user, { redirectTo = url => { window.location.href = url; } } = {}) {
    const deleteBtn = document.getElementById("deleteAccountBtn");
    if (!deleteBtn) return;

    let isDeleting = false;

    deleteBtn.addEventListener("click", async () => {
        if (isDeleting) return;

        const result = await deleteAccountDialog();
        if (!result) return;

        isDeleting = true;
        deleteBtn.disabled = true;
        deleteBtn.textContent = "Verifying password...";

        try {
            // Supabase has no direct "verify current password" call —
            // signing in again with it is the standard way to confirm
            // it's correct, the exact same mechanism (and exact same
            // "a specific wrong-password message here is fine, since
            // there's no other account whose existence this could
            // leak" reasoning) js/pages/settings/app.js's own password-
            // change flow already uses. This also mints a genuinely
            // fresh session/access token, which is what lets the
            // delete-account Edge Function's own server-side
            // recent-authentication check (never a client-side-only
            // gate) succeed next.
            const { error: reauthError } = await supabase.auth.signInWithPassword({
                email: user.email,
                password: result.password
            });

            if (reauthError) {
                showToast("Current password is incorrect.", "error");
                return;
            }

            deleteBtn.textContent = "Deleting your account...";

            await deleteAccount();

            // Local session cleanup — the Auth session is already
            // invalidated server-side by this point (the account no
            // longer exists), but local session state/tokens must still
            // be cleared before navigating away, so a cached, now-stale
            // session never lingers in this tab.
            await supabase.auth.signOut();

            redirectTo("account-deleted.html");
            return;
        } catch (error) {
            console.error("Delete account error:", error);

            if (error?.code === DELETE_ACCOUNT_REAUTH_REQUIRED) {
                showToast("Please try again — your session needs to be recently verified.", "error");
            } else {
                // Deliberately a fixed message, never error.message —
                // this action's failure path must never surface raw
                // internal/Postgres/Auth/Storage error text to the user,
                // and must never distinguish a legal-hold rejection from
                // any other failure (see supabase/migrations/
                // 0049_account_deletion_challenge.sql's self_delete_account(),
                // which carries this same posture forward from 0048).
                showToast(GENERIC_FAILURE_MESSAGE, "error");
            }
        } finally {
            isDeleting = false;
            deleteBtn.disabled = false;
            deleteBtn.textContent = "Delete Account";
            deleteBtn.focus();
        }
    });
}
