import { BlueprintCard } from "../../components/BlueprintCard.js";
import { hydrateProgressBars } from "../../utils/progressBar.js";
import { resolveAvatarUrl } from "../../repositories/mediaRepository.js";
import { renderFollow } from "./renderFollow.js";
import { escapeHtml, escapeAttribute } from "../../utils/escapeHtml.js";
import { avatarInitial } from "../../utils/avatarInitial.js";
import { icon } from "../../utils/icons.js";

const LINK_FIELDS = [
    { key: "website", label: "Website", format: value => normalizeUrl(value) },
    { key: "github", label: "GitHub", format: value => `https://github.com/${value.replace(/^@/, "")}` },
    { key: "youtube", label: "YouTube", format: value => `https://youtube.com/${value.replace(/^@/, "")}` }
];

export async function renderProfile({ profile, builds, commentCount, currentUser = null }) {
    const username = profile?.username || "Creator";

    document.getElementById("profileUsername").textContent = username;

    renderDisplayName(profile);

    document.getElementById("profileBio").textContent = profile?.bio || "Hardware Creator";

    renderMeta(profile);
    renderLinks(profile);
    await renderAvatar(profile, username);
    await renderFollow(profile, currentUser);
    renderStats(profile, builds, commentCount);
    renderBuilds(builds);
}

function renderDisplayName(profile) {
    const el = document.getElementById("profileDisplayName");

    if (!el) return;

    if (profile?.display_name && profile.display_name.trim() && profile.display_name.trim() !== profile.username) {
        el.textContent = profile.display_name.trim();
        el.hidden = false;
    } else {
        el.hidden = true;
    }
}

function renderMeta(profile) {
    const el = document.getElementById("profileMeta");

    if (!el) return;

    const items = [];

    if (profile?.location) {
        items.push(`<span class="profile-meta-item">${escapeHtml(profile.location)}</span>`);
    }

    items.push(`<span class="profile-meta-item">Joined ${formatJoinDate(profile?.created_at)}</span>`);

    el.innerHTML = items.join("");
}

function renderLinks(profile) {
    const el = document.getElementById("profileLinks");

    if (!el) return;

    const links = LINK_FIELDS
        .map(field => {
            const rawValue = profile?.[field.key]?.trim();

            if (!rawValue) return null;

            let href;

            try {
                href = field.format(rawValue);
            } catch {
                return null;
            }

            return `
                <a class="profile-link" href="${escapeAttribute(href)}" target="_blank" rel="noopener noreferrer">
                    ${escapeHtml(field.label)}
                </a>
            `;
        })
        .filter(Boolean);

    el.innerHTML = links.join("");
}

async function renderAvatar(profile, username) {
    const avatarEl = document.getElementById("profileAvatar");

    if (!avatarEl) return;

    const avatarUrl = await resolveAvatarUrl(profile);

    if (avatarUrl) {
        avatarEl.innerHTML = `<img src="${escapeAttribute(avatarUrl)}" alt="${escapeAttribute(username)}'s avatar">`;
    } else {
        avatarEl.textContent = avatarInitial(username);
    }
}

function renderStats(profile, builds, commentCount) {
    const el = document.getElementById("profileStats");

    if (!el) return;

    // Summed client-side from the builds already fetched for this page —
    // builds.views comes back with every existing build query (see
    // supabase/migrations/0010_build_view_tracking.sql), so this needs no
    // query of its own, same reasoning as Published Projects/builds.length.
    const totalViews = builds.reduce((sum, build) => sum + Number(build.views || 0), 0);

    el.innerHTML = `
        <div class="profile-stat">
            <span>${builds.length}</span>
            <p>Published Projects</p>
        </div>

        <div class="profile-stat">
            <span>${commentCount}</span>
            <p>Comments Received</p>
        </div>

        <div class="profile-stat">
            <span>${totalViews.toLocaleString()}</span>
            <p>Total Views</p>
        </div>

        <div class="profile-stat">
            <span>${formatJoinDate(profile?.created_at, { yearOnly: true })}</span>
            <p>Member Since</p>
        </div>
    `;
}

function renderBuilds(builds) {
    const el = document.getElementById("profileBuilds");

    if (!el) return;

    el.innerHTML =
        builds.length
            ? builds.map(build => BlueprintCard(build, "../")).join("")
            : `
                <div class="empty-state">
                    <div class="empty-state-icon">${icon("document", 32)}</div>
                    <h3>Nothing published yet</h3>
                    <p>Every great build starts with a first draft.</p>
                </div>
            `;

    hydrateProgressBars(el);
}

export function renderProfileError() {
    const username = document.getElementById("profileUsername");

    if (username) username.textContent = "Profile unavailable";

    const bio = document.getElementById("profileBio");

    if (bio) bio.textContent = "This profile could not be loaded.";

    const stats = document.getElementById("profileStats");

    if (stats) stats.innerHTML = "";

    const followCounts = document.getElementById("profileFollowCounts");

    if (followCounts) followCounts.innerHTML = "";

    const followBtn = document.getElementById("followBtn");

    if (followBtn) followBtn.hidden = true;

    const builds = document.getElementById("profileBuilds");

    if (builds) {
        builds.innerHTML = `
            <div class="empty-state">
                <div class="empty-state-icon">${icon("warning", 32)}</div>
                <h3>This profile could not be loaded.</h3>
            </div>
        `;
    }
}

function formatJoinDate(value, { yearOnly = false } = {}) {
    if (!value) return yearOnly ? "—" : "recently";

    const date = new Date(value);

    if (Number.isNaN(date.getTime())) return yearOnly ? "—" : "recently";

    if (yearOnly) {
        return String(date.getFullYear());
    }

    return date.toLocaleDateString(undefined, { month: "long", year: "numeric" });
}

function normalizeUrl(value) {
    return /^https?:\/\//i.test(value) ? value : `https://${value}`;
}

