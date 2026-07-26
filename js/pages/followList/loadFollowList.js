import { getProfile } from "../../repositories/profileRepository.js";
import { getCurrentUser } from "../../core/auth.js";
import { renderFollowList } from "./renderFollowList.js";

// Shared by pages/followers.html and pages/following.html — type is the
// only thing that differs between them (which repository query runs,
// which id field on each follows row is the "other side" of the
// relationship, and the empty-state wording).
export async function loadFollowList(type) {
    const params = new URLSearchParams(window.location.search);
    const userId = params.get("user");

    if (!userId) {
        window.location.href = "../index.html";
        return;
    }

    const heading = document.getElementById("followListHeading");
    const profileLink = document.getElementById("followListProfileLink");
    const label = type === "followers" ? "Followers" : "Following";

    if (profileLink) {
        profileLink.href = `profile.html?user=${encodeURIComponent(userId)}`;
    }

    let profile = null;

    try {
        profile = await getProfile(userId);
    } catch (error) {
        console.error("Profile load error:", error);
    }

    if (heading) {
        heading.textContent = profile?.username ? `${label} · ${profile.username}` : label;
    }

    const currentUser = await getCurrentUser();

    await renderFollowList(type, userId, currentUser);
}
