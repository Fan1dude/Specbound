import { resolveAvatarUrl } from "../../repositories/mediaRepository.js";
import { escapeHtml, escapeAttribute } from "../../utils/escapeHtml.js";
import { avatarInitial } from "../../utils/avatarInitial.js";
import { icon } from "../../utils/icons.js";
import { formatJoinDate } from "./formatJoinDate.js";
import { renderRoleBadges } from "../../components/RoleBadge.js";

// Identity block — Milestone 20 Builder Portfolio. Left-aligned (avatar +
// text side by side), not centered — a centered identity block reads as a
// landing page, not a workspace (spec §4.1). Replaces the old
// .profile-hero's bio line with `headline` (the new short tagline, spec
// §3.3a) — the longer `bio` now lives in About Builder only.
const LINK_FIELDS = [
    { key: "website", label: "Website", icon: "link", format: value => normalizeUrl(value) },
    { key: "github", label: "GitHub", icon: "github", format: value => `https://github.com/${value.replace(/^@/, "")}` },
    { key: "youtube", label: "YouTube", icon: "link", format: value => `https://youtube.com/${value.replace(/^@/, "")}` }
];

export async function renderProfileHero(profile, discordConnection = null, roles = []) {
    const username = profile?.username || "Creator";

    document.getElementById("profileUsername").textContent = username;

    renderRoleBadges(document.getElementById("profileRoles"), roles);
    renderDisplayName(profile);
    renderHeadline(profile);
    renderMeta(profile);
    renderLinks(profile, discordConnection);
    await renderAvatar(profile, username);
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

function renderHeadline(profile) {
    const el = document.getElementById("profileHeadline");

    if (!el) return;

    const headline = profile?.headline?.trim();

    if (headline) {
        el.textContent = headline;
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
        items.push(`
            <span class="profile-meta-item">
                ${icon("location-pin", 16)} ${escapeHtml(profile.location)}
            </span>
        `);
    }

    items.push(`
        <span class="profile-meta-item">
            ${icon("calendar", 16)} Joined ${formatJoinDate(profile?.created_at)}
        </span>
    `);

    el.innerHTML = items.join("");
}

function renderLinks(profile, discordConnection) {
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
                    ${icon(field.icon, 16)} ${escapeHtml(field.label)}
                </a>
            `;
        })
        .filter(Boolean);

    // Milestone 22 §4.8 — an additive list item, not a new section: same
    // .profile-link visual treatment as website/github/youtube above,
    // but a <span>, not an <a> — unlike those, there's no meaningful
    // Discord profile URL to link to, only a verified username to show.
    // Independently owner-controlled (discordConnection is only ever
    // non-null here when is_public = true; see loadProfile.js/
    // discordRepository.js's getPublicDiscordConnection()), so
    // connecting Discord never implies this renders.
    if (discordConnection?.provider_username) {
        links.push(`
            <span class="profile-link" title="Connected Discord account">
                ${icon("discord", 16)} ${escapeHtml(discordConnection.provider_username)}
            </span>
        `);
    }

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

function normalizeUrl(value) {
    return /^https?:\/\//i.test(value) ? value : `https://${value}`;
}
