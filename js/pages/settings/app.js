import { loadNavbar, loadFooter } from "../../core/layout.js";
import { supabase } from "../../core/supabase.js";
import { showToast } from "../../core/toast.js";
import { requireAuth } from "../../core/auth.js";
import { updateAvatarPath, getProfileBuilds } from "../../repositories/profileRepository.js";
import { resolveAvatarUrl } from "../../repositories/mediaRepository.js";
import { uploadAvatar } from "../../services/imageService.js";
import { renderErrorState } from "../../utils/listState.js";
import { createDiscordConnectionTracker } from "./discordConnectionTracker.js";
import { escapeAttribute, escapeHtml } from "../../utils/escapeHtml.js";
import { avatarInitial } from "../../utils/avatarInitial.js";
import { icon } from "../../utils/icons.js";
import {
    getMyDiscordConnection,
    linkDiscord,
    disconnectDiscord,
    setDiscordVisibility,
    reconcileDiscordConnection
} from "../../repositories/discordRepository.js";
import { confirmDialog } from "../../utils/modal.js";
import {
    describeDiscordLinkError,
    readDiscordOAuthRedirectError,
    describeDiscordRedirectError
} from "../../utils/discordAuthErrors.js";

loadNavbar("../");
loadFooter("../");

const user = await requireAuth("login.html");

if (user) {
    initPasswordForm(user);

    // Independent of each other — profile/avatar/featured-builds and the
    // Discord connection check don't share any data, so running them
    // sequentially (the original shape: fully finish loadSettings, only
    // *then* start the Discord check) just made the Discord section wait
    // out however long the rest of the page took to load before its own
    // fetch even began.
    await Promise.all([
        loadSettings(user),
        initDiscordConnection(user)
    ]);
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
    document.getElementById("headline").value = profile?.headline || "";
    document.getElementById("bio").value = profile?.bio || "";
    document.getElementById("location").value = profile?.location || "";
    initBuildingSinceYearField(profile);
    document.getElementById("website").value = profile?.website || "";
    document.getElementById("github").value = profile?.github || "";
    document.getElementById("youtube").value = profile?.youtube || "";

    initHeadlineCounter();

    // Independent of each other (avatar preview only needs profile;
    // featured-build options only need user/profile to query builds) —
    // running them one after another added a full extra round-trip of
    // wait with nothing gained from the ordering.
    const avatarPreview = document.getElementById("avatarPreview");

    await Promise.all([
        avatarPreview ? renderAvatarPreview(avatarPreview, profile) : Promise.resolve(),
        loadFeaturedBuildOptions(user, profile)
    ]);

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
        const featuredBuildValue = document.getElementById("featuredBuild").value;

        const buildingSinceYear = parseBuildingSinceYear();

        if (buildingSinceYear === INVALID_BUILDING_SINCE_YEAR) {
            showToast(`Building Since must be a year between 1980 and ${new Date().getFullYear()}.`, "warning");
            document.getElementById("buildingSinceYear").focus();
            return;
        }

        const updates = {
            display_name: document.getElementById("displayName").value.trim(),
            username: document.getElementById("username").value.trim(),
            headline: document.getElementById("headline").value.trim() || null,
            bio: document.getElementById("bio").value.trim(),
            location: document.getElementById("location").value.trim(),
            website: document.getElementById("website").value.trim(),
            github: document.getElementById("github").value.trim(),
            youtube: document.getElementById("youtube").value.trim(),
            building_since_year: buildingSinceYear,
            // "Choose automatically" is the empty option — unpins any
            // existing selection, falling back to the documented
            // completed -> published -> hidden chain (see
            // js/pages/profile/resolveFeaturedBuild.js).
            featured_build_id: featuredBuildValue || null
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

// Milestone 23 §6 — "Building since" is optional and nullable; existing
// users get null, never a guessed/backfilled value (spec explicitly
// prohibits this). Mirrors migration 0035's own CHECK constraint bounds
// (1980..current year) so an invalid value is caught here with a clear
// message rather than surfacing as a raw Postgres constraint-violation
// error after Save is clicked.
const MIN_BUILDING_SINCE_YEAR = 1980;
const INVALID_BUILDING_SINCE_YEAR = Symbol("invalid-building-since-year");

function initBuildingSinceYearField(profile) {
    const input = document.getElementById("buildingSinceYear");
    if (!input) return;

    input.max = String(new Date().getFullYear());
    input.value = Number.isInteger(profile?.building_since_year) ? String(profile.building_since_year) : "";
}

// Returns a valid integer year, null (field left blank — explicitly
// allowed, never defaulted to anything), or the INVALID sentinel.
function parseBuildingSinceYear() {
    const raw = document.getElementById("buildingSinceYear")?.value.trim();
    if (!raw) return null;

    const year = Number(raw);
    const currentYear = new Date().getFullYear();

    if (!Number.isInteger(year) || year < MIN_BUILDING_SINCE_YEAR || year > currentYear) {
        return INVALID_BUILDING_SINCE_YEAR;
    }

    return year;
}

function initHeadlineCounter() {
    const input = document.getElementById("headline");
    const countEl = document.getElementById("headlineCount");

    if (!input || !countEl) return;

    const update = () => {
        countEl.textContent = `${input.value.length}/120`;
    };

    update();
    input.addEventListener("input", update);
}

// Featured Build picker options are restricted to this builder's own
// published (visibility "public") projects — the picker's data source is
// the primary guard against picking an ineligible build (spec §19 Phase
// 5 / §20.2); the 0024 migration's ownership trigger is defense in
// depth, not the mechanism a user ever actually encounters. A failure
// here degrades to "Choose automatically" being the only option, not a
// broken settings page.
async function loadFeaturedBuildOptions(user, profile) {
    const select = document.getElementById("featuredBuild");

    if (!select) return;

    let builds = [];

    try {
        builds = await getProfileBuilds(user.id);
    } catch (error) {
        console.error("Featured build options load error:", error);
        return;
    }

    const options = builds
        .map(build => `<option value="${escapeAttribute(build.id)}">${escapeHtml(build.title || "Untitled project")}</option>`)
        .join("");

    select.innerHTML = `<option value="">Choose automatically</option>${options}`;
    select.value = profile?.featured_build_id || "";
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

// Milestone 22 §4, hardened for production stabilization (see
// discordConnectionTracker.js). reconcileDiscordConnection() is called
// unconditionally on every load (not just right after an OAuth
// redirect) — cheap, and it self-heals a linked-but-unsynced or
// disconnected-but-stale state either way (see the repository's own
// comment). What changed: this used to collapse "the check failed" and
// "the check succeeded and found nothing" into the exact same rendered
// state (the static "Connect Discord" markup, which was also the
// pre-JS default — so a slow-but-successful load looked identically
// disconnected for the entire time it was loading). Settings and the
// public profile disagreeing was traceable to this: a transient failure
// here rendered as "Not connected" even though the durable
// social_connections row Settings itself treats as the real answer
// hadn't changed at all.
async function initDiscordConnection(user) {
    const loadingState = document.getElementById("discordConnectLoading");
    const errorState = document.getElementById("discordConnectError");
    const emptyState = document.getElementById("discordConnectEmpty");
    const activeState = document.getElementById("discordConnectActive");
    const iconEl = document.getElementById("discordIcon");
    const usernameEl = document.getElementById("discordUsername");
    const visibilityToggle = document.getElementById("discordVisibilityToggle");
    const connectBtn = document.getElementById("connectDiscordBtn");
    const refreshBtn = document.getElementById("refreshDiscordBtn");
    const disconnectBtn = document.getElementById("disconnectDiscordBtn");
    const menuTrigger = document.getElementById("discordMenuTrigger");
    const menuIcon = document.getElementById("discordMenuIcon");
    const menuDropdown = document.getElementById("discordMenuDropdown");

    if (!emptyState || !activeState) return;

    if (iconEl) iconEl.innerHTML = icon("discord", 20);
    if (menuIcon) menuIcon.innerHTML = icon("more", 16);

    function closeMenu() {
        menuDropdown?.classList.remove("show-dropdown");
        menuTrigger?.setAttribute("aria-expanded", "false");
    }

    menuTrigger?.addEventListener("click", (event) => {
        event.stopPropagation();
        const isOpen = menuDropdown.classList.toggle("show-dropdown");
        menuTrigger.setAttribute("aria-expanded", String(isOpen));
    });

    document.addEventListener("click", (event) => {
        if (menuTrigger?.contains(event.target) || menuDropdown?.contains(event.target)) return;
        closeMenu();
    });

    document.addEventListener("keydown", (event) => {
        if (event.key !== "Escape") return;
        if (!menuDropdown?.classList.contains("show-dropdown")) return;
        closeMenu();
        menuTrigger?.focus();
    });

    // Four distinct, mutually exclusive states — loading and error each
    // get their own container so neither can ever be mistaken for a
    // confirmed "disconnected" read (see the four-state requirement this
    // pass introduced). Only ever called with a result this tracker
    // confirmed is still current — see loadConnection() below.
    function renderState(status, payload) {
        loadingState.hidden = true;
        emptyState.hidden = true;
        activeState.hidden = true;

        if (status !== "error") {
            // Clears out a previous attempt's error markup (including
            // its now-stale retry button) rather than just hiding it —
            // renderErrorState()'s own retry handler looks for a
            // lingering ".list-state-error h3" to decide whether a
            // retry actually succeeded, and would find one here forever
            // otherwise, even after a real success.
            errorState.hidden = true;
            errorState.innerHTML = "";
        }

        if (status === "loading") {
            loadingState.hidden = false;
            return;
        }

        if (status === "error") {
            errorState.hidden = false;
            renderErrorState(errorState, {
                message: "Couldn't load connection status.",
                onRetry: loadConnection,
                retryFocusTarget: () =>
                    (emptyState.hidden ? activeState : emptyState).querySelector("button, a, input")
            });
            return;
        }

        if (status === "connected") {
            activeState.hidden = false;
            usernameEl.textContent = payload.provider_username;
            visibilityToggle.checked = payload.is_public;
            return;
        }

        // "disconnected" — a definitive, successful lookup found no
        // connection. The only status allowed to render this container.
        emptyState.hidden = false;
        closeMenu();
    }

    // Shared across the initial load and every Refresh click, so the
    // request-id guard inside actually spans both — a Refresh started
    // while the initial load is still in flight can't be clobbered by
    // that older call resolving after it, and vice versa.
    const tracker = createDiscordConnectionTracker(() => reconcileDiscordConnection(user.id));

    async function loadConnection() {
        renderState("loading");

        const result = await tracker.run();

        // null means a newer call through this same tracker has already
        // taken over — this call's result is stale, discard it rather
        // than render over whatever that newer call decided.
        if (!result) return null;

        if (result.status === "error") {
            console.error("Discord connection load error:", result.error);
        }

        renderState(result.status, result.status === "connected" ? result.connection : undefined);
        return result;
    }

    // Read (and clear) any OAuth error Discord's own redirect back may
    // carry — cancellation, an identity already linked somewhere, or a
    // provider-side callback failure — *before* reconciling, since the
    // reconcile result is how "already linked to you" (harmless) gets
    // told apart from "already linked to someone else" (a real conflict)
    // below.
    const redirectError = readDiscordOAuthRedirectError();

    const initialResult = await loadConnection();

    if (redirectError) {
        const described = describeDiscordRedirectError(redirectError);
        const connected = initialResult?.status === "connected";

        if (described.type === "already_exists") {
            showToast(
                connected
                    ? "Discord is already connected."
                    : "This Discord account is already linked to a different Specbound account.",
                connected ? "info" : "error"
            );
        } else {
            showToast(described.message, described.type === "cancelled" ? "info" : "error");
        }
    }

    connectBtn?.addEventListener("click", async () => {
        connectBtn.disabled = true;

        try {
            await linkDiscord(window.location.href);
            // linkIdentity() redirects the browser away immediately on
            // success — nothing after this line runs in practice. The
            // disabled state and catch below only matter for the
            // network-error-before-redirect case, and for the
            // synchronous configuration errors (manual linking off,
            // provider not set up) that GoTrue rejects before ever
            // redirecting to Discord.
        } catch (error) {
            console.error("Discord link error:", error);
            showToast(describeDiscordLinkError(error), "error");
            connectBtn.disabled = false;
        }
    });

    refreshBtn?.addEventListener("click", async () => {
        closeMenu();
        refreshBtn.disabled = true;

        const result = await loadConnection();

        if (result?.status === "error") {
            showToast("Could not refresh Discord connection.", "error");
        } else if (result) {
            showToast("Discord connection refreshed.", "success");
        }

        refreshBtn.disabled = false;
    });

    visibilityToggle?.addEventListener("change", async () => {
        const isPublic = visibilityToggle.checked;
        visibilityToggle.disabled = true;

        try {
            await setDiscordVisibility(user.id, isPublic);
            showToast(isPublic ? "Discord is now shown on your public profile." : "Discord is now hidden from your public profile.", "success");
        } catch (error) {
            console.error("Discord visibility update error:", error);
            showToast("Could not update visibility.", "error");
            visibilityToggle.checked = !isPublic;
        } finally {
            visibilityToggle.disabled = false;
        }
    });

    disconnectBtn?.addEventListener("click", async () => {
        closeMenu();

        const confirmed = await confirmDialog({
            title: "Disconnect Discord?",
            body: "Your Discord connection and any public display of it will be removed.",
            confirmLabel: "Disconnect",
            danger: true
        });

        if (!confirmed) return;

        disconnectBtn.disabled = true;

        try {
            await disconnectDiscord();
            renderState("disconnected");
            showToast("Discord disconnected.", "success");
        } catch (error) {
            console.error("Discord disconnect error:", error);
            showToast("Could not disconnect Discord.", "error");
        } finally {
            disconnectBtn.disabled = false;
        }
    });
}