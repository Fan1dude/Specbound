import { loadNavbar, loadFooter } from "../../core/layout.js";
import { supabase } from "../../core/supabase.js";
import { showToast } from "../../core/toast.js";
import { ensureProfile } from "../../repositories/profileRepository.js";
import { redeemBetaInvite } from "../../repositories/communityRepository.js";

loadNavbar("../");
loadFooter("../");

// Milestone 22 §10 — the one gate closed-beta signup needs, kept as a
// single local flag rather than a schema-level requirement: the
// database never forces a code (beta_invites/redeem_beta_invite() are
// agnostic to whether the gate is "on"), so turning this off for public
// launch is a one-line code change, not a migration.
const BETA_INVITE_REQUIRED = true;

const signupForm = document.getElementById("signupForm");
const signupSubmit = document.getElementById("signupSubmit");
const inviteCodeGroup = document.getElementById("inviteCodeGroup");
const inviteCodeInput = document.getElementById("inviteCode");

if (BETA_INVITE_REQUIRED && inviteCodeGroup && inviteCodeInput) {
    inviteCodeGroup.hidden = false;
    inviteCodeInput.required = true;
}

signupForm.addEventListener("submit", async (e) => {
    e.preventDefault();

    const username = document.getElementById("username").value.trim();
    const email = document.getElementById("email").value.trim();
    const password = document.getElementById("password").value;
    const inviteCode = inviteCodeInput?.value.trim() || "";

    if (!/^[a-zA-Z0-9_]{3,30}$/.test(username)) {
        showToast(
            "Usernames must be 3-30 characters and can only contain letters, numbers, and underscores.",
            "warning"
        );
        return;
    }

    if (BETA_INVITE_REQUIRED && !inviteCode) {
        showToast("An invite code is required during closed beta.", "warning");
        return;
    }

    signupSubmit.disabled = true;
    signupSubmit.textContent = "Creating account...";

    // invite_code rides in user_metadata the same way username already
    // does — redemption itself needs a real session (redeem_beta_invite()
    // requires auth.uid()), which doesn't exist yet here in the normal
    // email-confirmation-required case (see the !data.session branch
    // below), so it's read back and redeemed at first login instead
    // (login/app.js), mirroring ensureProfile()'s exact "created on
    // first login" pattern.
    const { data, error } = await supabase.auth.signUp({
        email,
        password,
        options: {
            data: { username, invite_code: inviteCode || null }
        }
    });

    if (error) {
        showToast(error.message, "error");
        signupSubmit.disabled = false;
        signupSubmit.textContent = "Create Account";
        return;
    }

    if (!data.session) {
        // Email confirmation is required before a session exists, so we
        // can't create the profiles row yet (no authenticated request would
        // satisfy row-level security). It gets created on first login instead.
        showToast(
            "Account created. Check your email to confirm before signing in.",
            "success",
            6000
        );

        setTimeout(() => {
            window.location.href = "login.html";
        }, 1500);

        return;
    }

    if (inviteCode) {
        try {
            await redeemBetaInvite(inviteCode);
        } catch (inviteError) {
            console.error("Invite code redemption error:", inviteError);
            showToast(inviteError.message || "Could not redeem invite code.", "error");
            signupSubmit.disabled = false;
            signupSubmit.textContent = "Create Account";
            return;
        }
    }

    try {
        await ensureProfile({ id: data.user.id });
    } catch (profileError) {
        console.error("Profile setup error:", profileError);

        const message = String(profileError.message || "");

        showToast(
            message.toLowerCase().includes("username")
                ? "That username is already taken. You can change it later in Settings."
                : "Account created, but your profile couldn't be set up yet. Try Settings after signing in.",
            "warning",
            6000
        );

        window.location.href = "../index.html";
        return;
    }

    showToast("Account created.", "success");

    setTimeout(() => {
        window.location.href = "../index.html";
    }, 800);
});
