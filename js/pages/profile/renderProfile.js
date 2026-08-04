import { renderProfileHero } from "./renderProfileHero.js";
import { renderFollow } from "./renderFollow.js";
import { renderBuilderOverview } from "./renderBuilderOverview.js";
import { renderFeaturedProject } from "./renderFeaturedProject.js";
import { renderProjectGallery } from "./renderProjectGallery.js";
import { renderTechnologyBreakdown } from "./renderTechnologyBreakdown.js";
import { renderBuilderJourney } from "./renderBuilderJourney.js";
import { renderAboutBuilder } from "./renderAboutBuilder.js";
import { resolveFeaturedBuild } from "./resolveFeaturedBuild.js";
import { icon } from "../../utils/icons.js";
import { renderManageRoles } from "../../components/ManageRolesControl.js";

const CONDITIONAL_SECTION_IDS = [
    "profileEmptyState",
    "profileFeatured",
    "profileGallery",
    "profileTechBreakdown",
    "profileJourney",
    "profileAbout"
];

// Thin orchestrator — Milestone 20 Builder Portfolio. Each section owns
// its own rendering and its own empty-state/visibility decision; this
// function's only real job is deciding the two things that depend on
// more than one section's data: whether the visitor is the profile
// owner (gates the zero-project CTA and the empty-bio prompt) and which
// build is Featured (so Project Gallery can exclude it, spec §4.1).
const AUTOMATIC_ROLES = ["new_builder", "active_builder", "long_term_builder"];

export async function renderProfile({ profile, builds, commentCount, currentUser = null, journeyEvents = [], discordConnection = null, roles = [], viewerRoles = [] }) {
    const isOwner = Boolean(currentUser) && currentUser?.id === profile?.id;

    await renderProfileHero(profile, discordConnection, roles);
    await renderFollow(profile, currentUser);
    renderBuilderOverview(profile, builds, commentCount);

    // §13 phase 5 — a minimal grant/revoke control, only ever rendered
    // for a signed-in moderator/staff viewer looking at someone else's
    // profile. Re-renders itself after a successful grant/revoke so the
    // current-roles list and grantable-options list both stay accurate
    // without a full page reload.
    const viewerIsModerator = viewerRoles.includes("moderator") || viewerRoles.includes("staff");

    if (!isOwner && viewerIsModerator) {
        renderManageRoles(document.getElementById("manageRolesControl"), {
            targetUserId: profile.id,
            currentManualRoles: roles.filter(role => !AUTOMATIC_ROLES.includes(role)),
            viewerIsStaff: viewerRoles.includes("staff"),
            onChange: () => window.location.reload()
        });

        const manageRolesEl = document.getElementById("manageRolesControl");
        if (manageRolesEl) manageRolesEl.hidden = false;
    }

    const emptyStateEl = document.getElementById("profileEmptyState");
    if (emptyStateEl) {
        emptyStateEl.hidden = !(builds.length === 0 && isOwner);
    }

    if (builds.length === 0) {
        setHidden("profileFeatured", true);
        setHidden("profileGallery", true);
        setHidden("profileTechBreakdown", true);
        setHidden("profileJourney", true);
    } else {
        const featuredBuild = resolveFeaturedBuild(profile, builds);

        if (featuredBuild) {
            renderFeaturedProject(featuredBuild, "../");
        }
        setHidden("profileFeatured", !featuredBuild);

        const galleryBuilds = featuredBuild
            ? builds.filter(build => build.id !== featuredBuild.id)
            : builds;

        renderProjectGallery(galleryBuilds, "../");
        renderTechnologyBreakdown(builds);
        renderBuilderJourney(journeyEvents, "../");
    }

    renderAboutBuilder(profile, isOwner);
}

function setHidden(id, hidden) {
    const el = document.getElementById(id);
    if (el) el.hidden = hidden;
}

export function renderProfileError() {
    const username = document.getElementById("profileUsername");
    if (username) username.textContent = "Profile unavailable";

    const headline = document.getElementById("profileHeadline");
    if (headline) {
        headline.textContent = "This profile could not be loaded.";
        headline.hidden = false;
    }

    const displayName = document.getElementById("profileDisplayName");
    if (displayName) displayName.hidden = true;

    const meta = document.getElementById("profileMeta");
    if (meta) meta.innerHTML = "";

    const links = document.getElementById("profileLinks");
    if (links) links.innerHTML = "";

    const stats = document.getElementById("profileStats");
    if (stats) stats.innerHTML = "";

    const techFocus = document.getElementById("profileTechFocus");
    if (techFocus) techFocus.hidden = true;

    const followCounts = document.getElementById("profileFollowCounts");
    if (followCounts) followCounts.innerHTML = "";

    const followBtn = document.getElementById("followBtn");
    if (followBtn) followBtn.hidden = true;

    for (const id of CONDITIONAL_SECTION_IDS) {
        setHidden(id, true);
    }

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
