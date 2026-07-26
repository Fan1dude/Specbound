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

    // Covers the case where the profiles row couldn't be created at signup
    // time (email confirmation was pending, so there was no authenticated
    // session yet to satisfy RLS). Safe to call on every login: it only
    // inserts when no row exists yet, never overwrites one.
    try {
        await ensureProfile({
            id: data.user.id,
            username: data.user.user_metadata?.username || data.user.email.split("@")[0]
        });
    } catch (profileError) {
        console.error("Profile setup error:", profileError);
    }

    window.location.href = "../index.html";
});