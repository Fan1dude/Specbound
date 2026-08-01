import { hasFollowed, setFollow } from "../../repositories/followRepository.js";
import { showToast } from "../../core/toast.js";

// Renders the clickable Followers/Following counts AND the Follow button
// together, since a successful follow/unfollow updates both at once.
// currentUser is whoever is viewing the page (or null if signed out) —
// separate from `profile`, which is whose page this is.
export async function renderFollow(profile, currentUser) {
    renderCounts(profile.followers_count, profile.following_count);

    const button = document.getElementById("followBtn");

    if (!button) return;

    const isOwnProfile = Boolean(currentUser) && currentUser.id === profile.id;

    // No Follow control at all on your own profile — nothing to toggle.
    if (isOwnProfile) {
        button.hidden = true;
        return;
    }

    button.hidden = false;

    // Signed-out: the button itself is the sign-in affordance (Milestone
    // 20 polish — previously a disabled button paired with a separate
    // "Sign in to follow this builder" hint sentence below it, two
    // competing controls doing one job). Returns before any of the
    // toggle-follow wiring below, since a signed-out click should only
    // ever navigate to login, never attempt a follow.
    if (!currentUser) {
        button.disabled = false;
        button.classList.remove("is-following");
        button.setAttribute("aria-pressed", "false");
        button.textContent = "Sign In to Follow";
        button.onclick = () => {
            window.location.href = "../login.html";
        };
        return;
    }

    let followed = false;

    try {
        followed = await hasFollowed(currentUser.id, profile.id);
    } catch (error) {
        // Fail soft, same reasoning as renderLike.js/renderSave.js — a
        // failed status check shouldn't block the rest of the page.
        console.error("Follow status load error:", error);
    }

    setButtonState(followed);
    button.disabled = false;

    button.onclick = async () => {
        if (button.disabled) return;

        const nextFollowed = !followed;
        const previousFollowed = followed;
        const previousFollowersCount = readFollowersCount();

        followed = nextFollowed;
        setButtonState(followed);
        renderCounts(previousFollowersCount + (nextFollowed ? 1 : -1), profile.following_count);
        button.disabled = true;

        try {
            const result = await setFollow(profile.id, nextFollowed);

            // Reconcile against the RPC's authoritative followed value,
            // just like Likes and Saves — not the optimistic guess.
            followed = result.followed;
            setButtonState(followed);
            renderCounts(result.followersCount, profile.following_count);
        } catch (error) {
            console.error("Follow update error:", error);

            followed = previousFollowed;
            setButtonState(followed);
            renderCounts(previousFollowersCount, profile.following_count);

            showToast(error.message || "Could not update your follow status.", "error");
        } finally {
            button.disabled = false;
        }
    };

    function setButtonState(isFollowed) {
        button.classList.toggle("is-following", isFollowed);
        button.setAttribute("aria-pressed", String(isFollowed));
        button.textContent = isFollowed ? "Following" : "Follow";
    }
}

function renderCounts(followersCount, followingCount) {
    const el = document.getElementById("profileFollowCounts");

    if (!el) return;

    const params = new URLSearchParams(window.location.search);
    const userId = params.get("user") || "";

    el.innerHTML = `
        <a href="followers.html?user=${encodeURIComponent(userId)}" class="profile-follow-count">
            <strong>${formatCount(followersCount)}</strong> Followers
        </a>

        <a href="following.html?user=${encodeURIComponent(userId)}" class="profile-follow-count">
            <strong>${formatCount(followingCount)}</strong> Following
        </a>
    `;
}

function readFollowersCount() {
    const el = document.querySelector("#profileFollowCounts .profile-follow-count strong");
    const value = Number(el?.textContent.replace(/,/g, ""));

    return Number.isFinite(value) ? value : 0;
}

function formatCount(value) {
    const number = Number(value || 0);

    if (!Number.isFinite(number) || number < 0) return "0";

    return Math.floor(number).toLocaleString();
}
