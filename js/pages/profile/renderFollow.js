import { hasFollowed, setFollow } from "../../repositories/followRepository.js";
import { showToast } from "../../core/toast.js";

// Renders the clickable Followers/Following counts AND the Follow button
// together, since a successful follow/unfollow updates both at once.
// currentUser is whoever is viewing the page (or null if signed out) —
// separate from `profile`, which is whose page this is.
export async function renderFollow(profile, currentUser) {
    renderCounts(profile.followers_count, profile.following_count);

    const button = document.getElementById("followBtn");
    const hint = document.getElementById("followHint");

    if (!button) return;

    const isOwnProfile = Boolean(currentUser) && currentUser.id === profile.id;

    // No Follow control at all on your own profile — nothing to toggle.
    if (isOwnProfile) {
        button.hidden = true;
        if (hint) hint.hidden = true;
        return;
    }

    button.hidden = false;

    let followed = false;

    if (currentUser) {
        try {
            followed = await hasFollowed(currentUser.id, profile.id);
        } catch (error) {
            // Fail soft, same reasoning as renderLike.js/renderSave.js — a
            // failed status check shouldn't block the rest of the page.
            console.error("Follow status load error:", error);
        }
    }

    setButtonState(followed);

    if (!currentUser) {
        button.disabled = true;
        setHint(`<a href="../login.html">Sign in</a> to follow this builder.`);
    } else {
        button.disabled = false;
        setHint(null);
    }

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

    function setHint(html) {
        if (!hint) return;

        if (!html) {
            hint.hidden = true;
            hint.innerHTML = "";
            return;
        }

        hint.hidden = false;
        hint.innerHTML = html;
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
