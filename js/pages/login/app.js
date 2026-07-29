import { loadNavbar, loadFooter } from "../../core/layout.js";
import { supabase } from "../../core/supabase.js";
import { showToast } from "../../core/toast.js";
import { ensureProfile } from "../../repositories/profileRepository.js";

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

    window.location.href = "../index.html";
});