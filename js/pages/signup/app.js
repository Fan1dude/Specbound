import { loadNavbar, loadFooter } from "../../core/layout.js";
import { supabase } from "../../core/supabase.js";
import { showToast } from "../../core/toast.js";
import { ensureProfile } from "../../repositories/profileRepository.js";

loadNavbar("../");
loadFooter("../");

const signupForm = document.getElementById("signupForm");
const signupSubmit = document.getElementById("signupSubmit");

signupForm.addEventListener("submit", async (e) => {
    e.preventDefault();

    const username = document.getElementById("username").value.trim();
    const email = document.getElementById("email").value.trim();
    const password = document.getElementById("password").value;

    if (!/^[a-zA-Z0-9_]{3,30}$/.test(username)) {
        showToast(
            "Usernames must be 3-30 characters and can only contain letters, numbers, and underscores.",
            "warning"
        );
        return;
    }

    signupSubmit.disabled = true;
    signupSubmit.textContent = "Creating account...";

    const { data, error } = await supabase.auth.signUp({
        email,
        password,
        options: {
            data: { username }
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

    try {
        await ensureProfile({ id: data.user.id, username });
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
