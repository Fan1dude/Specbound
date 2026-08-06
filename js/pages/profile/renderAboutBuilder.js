import { escapeHtml } from "../../utils/escapeHtml.js";
import { icon } from "../../utils/icons.js";
import { formatJoinDate } from "./formatJoinDate.js";

// The narrative section — spec §4.1/§10.2/§7, revised in the polish pass
// to drop the repeated Website/GitHub/YouTube links this section used to
// show a second time at the bottom of the page — those live in the Hero
// only now, so there's exactly one place to look for them, not two.
// Empty-bio handling differs by viewer (spec §7): the owner gets a quiet
// prompt linking to Settings; anyone else sees the section omitted
// entirely rather than empty white space.
export function renderAboutBuilder(profile, isOwner) {
    const el = document.getElementById("profileAbout");

    if (!el) return;

    const bio = profile?.bio?.trim();

    if (!bio && !isOwner) {
        el.hidden = true;
        el.innerHTML = "";
        return;
    }

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
    `;
}
