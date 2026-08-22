import { resolveAvatarUrl } from "../../repositories/mediaRepository.js";
import { escapeHtml, escapeAttribute } from "../../utils/escapeHtml.js";
import { avatarInitial } from "../../utils/avatarInitial.js";
import { icon } from "../../utils/icons.js";
import { formatJoinDate } from "./formatJoinDate.js";
import { renderRoleBadges } from "../../components/RoleBadge.js";
import { isFeatureEnabled } from "../../core/featureFlags.js";

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
    renderLinks(profile);
    renderConnectedAccounts(discordConnection);
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
                    ${icon(field.icon, 16)} ${escapeHtml(field.label)}
                </a>
            `;
        })
        .filter(Boolean);

    el.innerHTML = links.join("");
}

// Milestone 22 §4.8, redesigned in the Connected Accounts polish pass —
// a distinct area from the free-text links above (website/github/
// youtube are unverified profile fields; this is OAuth-verified
// identity, a different concept per the §0.1 design review), not an
// extra item folded into .profile-links. Only ever populated when
// discordConnection is non-null, which — per loadProfile.js/
// discordRepository.js's getPublicDiscordConnection() — only happens
// when RLS has already confirmed both is_public = true and that the
// connection belongs to the profile being viewed; there is no
// additional ownership/visibility check to apply here.
// https://discord.com/users/<id> is a real, Discord-documented profile
// deep link (opens the app or web client to that user), which is why
// this can be a genuine <a>, unlike the old inline span that had
// nowhere to link to.
function renderConnectedAccounts(discordConnection) {
    const el = document.getElementById("profileConnectedAccounts");

    if (!el) return;

    // Beta launch gate (js/core/featureFlags.js) — a second, independent
    // guard on top of loadProfile.js's own: even if a real discordConnection
    // object somehow reached this function (e.g. old/mocked data), nothing
    // Discord-related renders while the flag is off. No old social_connections
    // row is deleted or touched by this — it's just never displayed.
    if (!isFeatureEnabled("discordConnections") || !discordConnection?.provider_username || !discordConnection?.provider_user_id) {
        el.hidden = true;
        el.innerHTML = "";
        return;
    }

    const href = `https://discord.com/users/${encodeURIComponent(discordConnection.provider_user_id)}`;

    el.innerHTML = `
        <a
            class="profile-link connected-account-link"
            href="${escapeAttribute(href)}"
            target="_blank"
            rel="noopener noreferrer"
            aria-label="Discord: ${escapeAttribute(discordConnection.provider_username)}"
        >
            ${icon("discord", 16)}
            <span class="connected-account-link-platform">Discord</span>
            <span class="connected-account-link-username">${escapeHtml(discordConnection.provider_username)}</span>
        </a>
    `;
    el.hidden = false;
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
