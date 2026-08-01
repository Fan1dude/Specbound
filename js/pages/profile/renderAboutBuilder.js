import { escapeHtml, escapeAttribute } from "../../utils/escapeHtml.js";
import { icon } from "../../utils/icons.js";
import { formatJoinDate } from "./formatJoinDate.js";

const LINK_FIELDS = [
    { key: "website", label: "Website", icon: "link", format: value => normalizeUrl(value) },
    { key: "github", label: "GitHub", icon: "github", format: value => `https://github.com/${value.replace(/^@/, "")}` },
    { key: "youtube", label: "YouTube", icon: "link", format: value => `https://youtube.com/${value.replace(/^@/, "")}` }
];

// The narrative section — spec §4.1/§10.2/§7. Not a duplicate of Hero:
// Hero is the quick-facts identity block, About is the fuller story, plus
// the same links repeated near the bottom of the page for a scrolled-down
// visitor. Empty-bio handling differs by viewer (spec §7): the owner gets
// a quiet prompt linking to Settings; anyone else sees the section
// omitted entirely rather than empty white space.
export function renderAboutBuilder(profile, isOwner) {
    const el = document.getElementById("profileAbout");

    if (!el) return;

    const bio = profile?.bio?.trim();

    if (!bio && !isOwner) {
        el.hidden = true;
        el.innerHTML = "";
        return;
    }

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

    el.hidden = false;
    el.innerHTML = `
        <div class="section-heading">
            <p class="hero-badge">About</p>
            <h2>About Builder</h2>
        </div>

        ${
            bio
                ? `<p class="about-builder-bio">${escapeHtml(bio)}</p>`
                : `<p class="about-builder-bio about-builder-bio-empty">
                        Add a bio to tell people about your work.
                        <a href="../settings.html">Edit your profile</a>
                   </p>`
        }

        <p class="about-builder-since">
            ${icon("calendar", 16)} Building since ${formatJoinDate(profile?.created_at)}
        </p>

        ${links.length ? `<div class="profile-links about-builder-links">${links.join("")}</div>` : ""}
    `;
}

function normalizeUrl(value) {
    return /^https?:\/\//i.test(value) ? value : `https://${value}`;
}
