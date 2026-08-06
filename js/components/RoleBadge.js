import { escapeHtml } from "../utils/escapeHtml.js";
import { ROLE_LABELS } from "../services/communityRecognition.js";

// One small, text-first, non-tiered badge per role — deliberately no
// color ladder or rank ordering (Milestone 22 spec §5.4): a role badge
// answers "what is this person's relationship to the community," never
// "how much have they done compared to others." Reuses the existing
// .badge class verbatim — no new visual language.
export function RoleBadge(role) {
    const label = ROLE_LABELS[role];
    if (!label) return "";

    return `<span class="badge role-badge">${escapeHtml(label)}</span>`;
}

// Renders every role a profile currently holds (the one automatic role,
// plus zero or more manually-granted roles) as a small row. Hides its
// container entirely when there's nothing to show, rather than an empty
// row — same "omit, don't show empty" convention as every other
// conditional section in the Builder Portfolio.
export function renderRoleBadges(container, roles) {
    if (!container) return;

    const badges = roles.filter(Boolean).map(RoleBadge).join("");

    container.innerHTML = badges;
    container.hidden = badges.length === 0;
}
