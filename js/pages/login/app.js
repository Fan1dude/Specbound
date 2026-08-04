import { loadNavbar, loadFooter } from "../../core/layout.js";
import { supabase } from "../../core/supabase.js";
import { showToast } from "../../core/toast.js";
import { ensureProfile } from "../../repositories/profileRepository.js";
import { redeemBetaInvite } from "../../repositories/communityRepository.js";

loadNavbar("../");
loadFooter("../");

const loginForm = document.getElementById("loginForm");
const loginSubmit = document.getElementById("loginSubmit");

loginForm.addEventListener("submit", async (e) => {
    e.preventDefault();

    const email = document.getElementById("email").value.trim();
    const password = document.getElementById("password").value;

    loginSubmit.disabled = true;
    loginSubmit.textContent = "Signing in...";

    const { data, error } = await supabase.auth.signInWithPassword({
        email,
        password
    });

    if (error) {
        showToast(error.message, "error");
        loginSubmit.disabled = false;
        loginSubmit.textContent = "Sign In";
        return;
    }

    // Confirms the auth.users trigger actually created a profiles row for
    // this account (see profileRepository.js's ensureProfile()) — cheap,
    // safe to call on every login, and the only way this page would ever
    // learn that something went wrong with an account's profile setup.
    try {
        await ensureProfile({ id: data.user.id });
    } catch (profileError) {
        console.error("Profile setup error:", profileError);
    }

    // Milestone 22 §10 — the realistic path this actually redeems
    // through: signup couldn't do it directly (no session exists yet
    // when email confirmation is required, see signup/app.js), so the
    // code captured in user_metadata at signup is redeemed here, on
    // first login, once a real session exists. Silently logged, never
    // toasted or blocking navigation: on every login AFTER the first,
    // this is an expected no-op (the code is already used by this same
    // account), not a real failure worth alarming a returning user
    // about.
    const inviteCode = data.user.user_metadata?.invite_code;

    if (inviteCode) {
        try {
            await redeemBetaInvite(inviteCode);
        } catch (inviteError) {
            console.error("Invite code redemption error (expected on repeat logins):", inviteError);
        }
    }

    window.location.href = "../index.html";
});