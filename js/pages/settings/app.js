import { loadNavbar, loadFooter } from "../../core/layout.js";
import { supabase } from "../../core/supabase.js";
import { showToast } from "../../core/toast.js";
import { requireAuth } from "../../core/auth.js";
import { updateAvatarPath } from "../../repositories/profileRepository.js";
import { resolveAvatarUrl } from "../../repositories/mediaRepository.js";
import { uploadAvatar } from "../../services/imageService.js";
import { renderErrorState } from "../../utils/listState.js";
import { escapeAttribute } from "../../utils/escapeHtml.js";
import { avatarInitial } from "../../utils/avatarInitial.js";

loadNavbar("../");
loadFooter("../");

const user = await requireAuth("login.html");

if (user) {
    await loadSettings(user);
    initPasswordForm(user);
}

async function loadSettings(user) {
    const { data: profile, error } = await supabase
        .from("profiles")
        .select("*")
        .eq("id", user.id)
        .single();

    const errorContainer = document.getElementById("settingsLoadError");
    const saveButton = document.getElementById("saveProfile");
    const avatarInputEl = document.getElementById("avatar");

    if (error) {
        console.error("Settings profile load error:", error);

        // The form fields below would otherwise render blank on a failed
        // load — indistinguishable from a genuinely empty profile — and
        // clicking Save while blank would silently overwrite the user's
        // real profile with empty values. Disabling Save (not just
        // showing a message) is what actually prevents that; the toast
        // alone auto-dismisses in a few seconds and isn't a substitute.
        renderErrorState(errorContainer, {
            message: "Could not load your profile. Your existing profile has not been changed.",
            onRetry: () => loadSettings(user),
            // A successful retry repopulates the static form fields, not
            // this error container itself — point focus at the first one.
            retryFocusTarget: () => document.getElementById("displayName")
        });

        if (errorContainer) errorContainer.hidden = false;
        if (saveButton) saveButton.disabled = true;
        if (avatarInputEl) avatarInputEl.disabled = true;

        showToast("Could not load profile.", "error");
        return;
    }

    if (errorContainer) {
        errorContainer.hidden = true;
        errorContainer.innerHTML = "";
    }

    if (saveButton) saveButton.disabled = false;
    if (avatarInputEl) avatarInputEl.disabled = false;

    document.getElementById("displayName").value = profile?.display_name || "";
    document.getElementById("username").value = profile?.username || "";
    document.getElementById("bio").value = profile?.bio || "";
    document.getElementById("location").value = profile?.location || "";
    document.getElementById("website").value = profile?.website || "";
    document.getElementById("github").value = profile?.github || "";
    document.getElementById("youtube").value = profile?.youtube || "";

    const avatarPreview = document.getElementById("avatarPreview");

    if (avatarPreview) {
        await renderAvatarPreview(avatarPreview, profile);
    }

    const avatarInput = document.getElementById("avatar");

    if (avatarInput) {
        avatarInput.addEventListener("change", async () => {
            const file = avatarInput.files[0];
            if (!file) return;

            avatarInput.disabled = true;
            showToast("Uploading avatar...", "info", 2000);

            try {
                const avatarPath = await uploadAvatar(user.id, file);

                await updateAvatarPath(user.id, avatarPath);

                await renderAvatarPreview(avatarPreview, { ...profile, avatar_path: avatarPath });
                showToast("Avatar updated.", "success");
            } catch (avatarError) {
                console.error("Avatar upload error:", avatarError);

                showToast(
                    avatarError.message?.includes("column")
                        ? "Avatars aren't enabled on this profile yet."
                        : avatarError.message || "Could not upload avatar.",
                    "error"
                );
            } finally {
                avatarInput.disabled = false;
                avatarInput.value = "";
            }
        });
    }

    document.getElementById("saveProfile").addEventListener("click", async () => {
        const updates = {
            display_name: document.getElementById("displayName").value.trim(),
            username: document.getElementById("username").value.trim(),
            bio: document.getElementById("bio").value.trim(),
            location: document.getElementById("location").value.trim(),
            website: document.getElementById("website").value.trim(),
            github: document.getElementById("github").value.trim(),
            youtube: document.getElementById("youtube").value.trim()
        };

        const { error: updateError } = await supabase
            .from("profiles")
            .update(updates)
            .eq("id", user.id);

        if (updateError) {
            showToast(updateError.message, "error");
            return;
        }

        showToast("Profile updated successfully.", "success");
    });
}

async function renderAvatarPreview(container, profile) {
    // Delegates to the shared resolver (avatar_path preferred, avatar_url
    // — including this project's own legacy pre-private-bucket URLs —
    // as the fallback) rather than re-implementing that branching here.
    // See mediaRepository.js's resolveAvatarUrl()/extractStoragePath().
    const url = await resolveAvatarUrl(profile);

    if (url) {
        container.innerHTML = `<img src="${escapeAttribute(url)}" alt="Your avatar">`;
        return;
    }

    container.textContent = avatarInitial(profile?.username);
}

function initPasswordForm(user) {
    const form = document.getElementById("passwordForm");
    const submitButton = document.getElementById("changePasswordSubmit");

    form.addEventListener("submit", async (event) => {
        event.preventDefault();

        const currentPassword = document.getElementById("currentPassword").value;
        const newPassword = document.getElementById("newPassword").value;
        const confirmNewPassword = document.getElementById("confirmNewPassword").value;

        if (newPassword !== confirmNewPassword) {
            showToast("Those new passwords don't match.", "warning");
            return;
        }

        submitButton.disabled = true;
        submitButton.textContent = "Updating...";

        try {
            // Supabase has no direct "verify current password" call —
            // signing in again with it is the standard way to confirm it's
            // correct before allowing the change. This is the user's own
            // account and they're already signed in, so a specific "wrong
            // password" message here is fine — unlike the reset-request
            // flow, there's no other account whose existence this could leak.
            const { error: reauthError } = await supabase.auth.signInWithPassword({
                email: user.email,
                password: currentPassword
            });

            if (reauthError) {
                showToast("Current password is incorrect.", "error");
                return;
            }

            const { error: updateError } = await supabase.auth.updateUser({ password: newPassword });

            if (updateError) {
                console.error("Password update error:", { code: updateError.code, message: updateError.message });
                showToast(updateError.message || "Could not update your password.", "error");
                return;
            }

            showToast("Password updated.", "success");
            form.reset();
        } finally {
            submitButton.disabled = false;
            submitButton.textContent = "Update Password";
        }
    });
}