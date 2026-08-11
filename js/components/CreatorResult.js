import { escapeHtml, escapeAttribute } from "../utils/escapeHtml.js";
import { avatarInitial } from "../utils/avatarInitial.js";

// Milestone 23 §5 — the reusable card for a Creator-scoped (or "All"
// scope's Builders section) search result. profile.avatarResolvedUrl is
// expected to already be resolved (see resolveAvatarUrls() in
// mediaRepository.js) — this component stays synchronous, same
// separation BlueprintCard/BlueprintFeed already use for build cover
// images. Always links to the public Builder Portfolio, including a
// creator with zero published blueprints — this card never depends on
// build data existing at all.
export function CreatorResult(profile, pathPrefix = "") {
    const username = profile.username || "Builder";
    const displayName = profile.display_name?.trim() || username;
    const profileUrl = `${pathPrefix}pages/profile.html?user=${encodeURIComponent(profile.id)}`;

    const avatarMarkup = profile.avatarResolvedUrl
        ? `<img src="${escapeAttribute(profile.avatarResolvedUrl)}" alt="" loading="lazy">`
        : escapeHtml(avatarInitial(displayName));

    return `
        <a class="creator-result card" href="${profileUrl}">
            <span class="creator-result-avatar" aria-hidden="true">${avatarMarkup}</span>

            <span class="creator-result-body">
                <span class="creator-result-name">${escapeHtml(displayName)}</span>
                <span class="creator-result-username">@${escapeHtml(username)}</span>
                ${profile.headline ? `<span class="creator-result-headline">${escapeHtml(profile.headline)}</span>` : ""}
            </span>
        </a>
    `;
}
