import { supabase } from "./supabase.js";
import { getCurrentUser, clearCurrentUserCache } from "./auth.js";
import { initNotificationBell } from "./notificationBell.js";
import { maybeShowWelcome } from "./onboarding.js";
import { getProfileRoles } from "../repositories/communityRepository.js";
import { escapeHtml } from "../utils/escapeHtml.js";
import { icon } from "../utils/icons.js";

export async function loadNavbar(pathPrefix = "") {
    ensureToastContainer();
    insertSkipLink();

    const navbar = document.getElementById("navbar");
    if (!navbar) return;

    const user = await getCurrentUser();

    let authLinks = "";

    if (user) {
        // onboarding_welcomed_at added for Milestone 21 — this is the one
        // place in the app that already runs on every authenticated page
        // load and already resolves the profile, so it's also the global
        // trigger point for the first-sign-in Welcome dialog (see
        // core/onboarding.js). Eligibility is only known once this
        // query resolves; maybeShowWelcome() is never called before then.
        const { data: profile } = await supabase
            .from("profiles")
            .select("username, onboarding_welcomed_at")
            .eq("id", user.id)
            .single();

        const username = profile?.username || "Builder";

        if (profile && !profile.onboarding_welcomed_at) {
            maybeShowWelcome(user, profile, pathPrefix);
        }

        // Milestone 24 — a moderator-only "Moderation" entry point. One
        // extra lightweight RPC per signed-in page load (the same
        // get_public_profile_roles() call already used to gate
        // ManageRolesControl.js on the profile page), deliberately with
        // no open-report count fetched alongside it: a count needs its
        // own query, and a stale or wrong count would be worse than none
        // — see docs/milestones/MILESTONE_24_MODERATOR_REPORT_QUEUE_SPECIFICATION.md.
        // This is a UX convenience only, same as every other role check
        // in this app; the real boundary is the page's own gate
        // (js/pages/moderation/loadModerationQueue.js) plus RLS.
        let isModerator = false;

        try {
            const roles = await getProfileRoles(user.id);
            isModerator = roles.includes("moderator") || roles.includes("staff");
        } catch (error) {
            console.error("Moderator nav-link role check error:", error);
        }

        const moderationLink = isModerator
            ? `<a href="${pathPrefix}pages/moderation.html">Moderation</a>`
            : "";

        // Milestone 26 — a second moderator/staff-only entry point,
        // reusing the exact same isModerator check above (no extra role
        // check needed) rather than a separate one.
        const feedbackReviewLink = isModerator
            ? `<a href="${pathPrefix}pages/feedback.html">Feedback</a>`
            : "";

        // .builder-menu (the desktop-style disclosure button + dropdown)
        // and .mobile-account-link (three plain links) render the same
        // three destinations two different ways — CSS picks exactly one
        // per viewport (navbar.css), never both. Desktop keeps the
        // existing click-to-open dropdown untouched. Mobile no longer
        // requires that second tap at all: Profile/Settings/Log Out are
        // just three more items in the same list as Explore/Workshop/
        // Publish, always present the moment the hamburger opens — this
        // is also what makes .builder-menu's own real height (and
        // whatever a real device's Safari toolbar is doing to 100vh)
        // irrelevant to reaching these three links on mobile: they don't
        // live inside that nested, conditionally-revealed container at
        // all there. logoutLink is duplicated with a shared class (not a
        // duplicate id — see the listener wiring below) so both routes
        // sign out identically.
        authLinks = `
            <div class="builder-menu">
                <button class="builder-button" id="builderMenuButton">
                    ${escapeHtml(username)} ${icon("chevron-down", 16)}
                </button>

                <div class="builder-dropdown" id="builderDropdown">
                    <a href="${pathPrefix}pages/workshop.html">Workshop</a>
                    <a href="${pathPrefix}pages/profile.html?user=${user.id}">View My Profile</a>
                    <a href="${pathPrefix}pages/settings.html">Settings</a>
                    <a href="${pathPrefix}pages/my-feedback.html">My Feedback</a>
                    ${moderationLink}
                    ${feedbackReviewLink}
                    <hr>
                    <a href="#" class="logout-link">Log Out</a>
                </div>
            </div>

            <a href="${pathPrefix}pages/profile.html?user=${user.id}" class="mobile-account-link">View My Profile</a>
            <a href="${pathPrefix}pages/settings.html" class="mobile-account-link">Settings</a>
            <a href="${pathPrefix}pages/my-feedback.html" class="mobile-account-link">My Feedback</a>
            ${moderationLink ? `<a href="${pathPrefix}pages/moderation.html" class="mobile-account-link">Moderation</a>` : ""}
            ${feedbackReviewLink ? `<a href="${pathPrefix}pages/feedback.html" class="mobile-account-link">Feedback</a>` : ""}
            <a href="#" class="mobile-account-link logout-link">Log Out</a>
        `;
    } else {
        authLinks = `
            <a href="${pathPrefix}pages/login.html" class="nav-signin">Sign In</a>
        `;
    }

    navbar.innerHTML = `
        <div class="navbar-inner">
            <h1 class="logo">
                <a href="${pathPrefix}index.html">
                    SPECBOUND
                </a>
            </h1>

            <button
                class="nav-toggle"
                id="navToggle"
                type="button"
                aria-expanded="false"
                aria-controls="navLinks"
                aria-label="Toggle navigation menu"
            >
                <svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round">
                    <line x1="3" y1="6" x2="21" y2="6"></line>
                    <line x1="3" y1="12" x2="21" y2="12"></line>
                    <line x1="3" y1="18" x2="21" y2="18"></line>
                </svg>
            </button>

            <div class="navbar-search">
                <input
                    class="search-bar"
                    type="text"
                    placeholder="Search builds, builders, parts..."
                    aria-label="Search builds, builders, parts"
                >
            </div>

            <div class="nav-links" id="navLinks">
                <a href="${pathPrefix}pages/explore.html">Explore</a>
                <a href="${pathPrefix}pages/workshop.html">Workshop</a>
                <a href="${pathPrefix}pages/upload.html">Publish</a>
                ${user ? `<div id="notificationBellContainer"></div>` : ""}
                ${authLinks}
            </div>
        </div>
    `;

    // Marks whichever top-level nav link matches the current page with
    // aria-current="page" — no prior mechanism existed for this at all.
    // Comparing pathnames (not full hrefs) so query strings on the current
    // URL (e.g. explore.html?category=pc_build) don't prevent a match.
    const currentPath = window.location.pathname.split("/").pop();

    navbar.querySelectorAll(".nav-links > a[href]").forEach(link => {
        const linkPath = new URL(link.href, window.location.origin).pathname.split("/").pop();
        if (linkPath === currentPath) link.setAttribute("aria-current", "page");
    });

    if (user) {
        const bellContainer = document.getElementById("notificationBellContainer");
        initNotificationBell(bellContainer, { user, pathPrefix });
    }

    const search = navbar.querySelector(".search-bar");

    if (search) {
        search.addEventListener("keydown", (e) => {
            if (e.key !== "Enter") return;

            const value = search.value.trim();
            if (!value) return;

            // Milestone 23 polish — the navbar carries only the query now;
            // scope is chosen on the results page itself (search.html),
            // which defaults to "all" when none is supplied.
            window.location.href =
                `${pathPrefix}pages/search.html?q=${encodeURIComponent(value)}`;
        });
    }

    const navToggle = document.getElementById("navToggle");
    const navLinks = document.getElementById("navLinks");

    if (navToggle && navLinks) {
        const openNavMenu = () => {
            navLinks.classList.add("show-nav-links");
            navToggle.setAttribute("aria-expanded", "true");
            document.body.style.overflow = "hidden";
        };

        const closeNavMenu = () => {
            navLinks.classList.remove("show-nav-links");
            navToggle.setAttribute("aria-expanded", "false");
            document.body.style.overflow = "";
        };

        navToggle.addEventListener("click", () => {
            if (navLinks.classList.contains("show-nav-links")) {
                closeNavMenu();
            } else {
                openNavMenu();
            }
        });

        document.addEventListener("click", event => {
            if (!navLinks.classList.contains("show-nav-links")) return;
            if (navToggle.contains(event.target) || navLinks.contains(event.target)) return;

            closeNavMenu();
        });

        document.addEventListener("keydown", event => {
            if (event.key !== "Escape") return;
            if (!navLinks.classList.contains("show-nav-links")) return;

            closeNavMenu();
            navToggle.focus();
        });
    }

    const builderButton = document.getElementById("builderMenuButton");
    const builderDropdown = document.getElementById("builderDropdown");

    if (builderButton && builderDropdown) {
        builderButton.setAttribute("aria-expanded", "false");
        builderButton.setAttribute("aria-haspopup", "true");

        builderButton.addEventListener("click", () => {
            const isOpen = builderDropdown.classList.toggle("show-dropdown");
            builderButton.setAttribute("aria-expanded", String(isOpen));
        });

        document.addEventListener("click", (e) => {
            if (builderButton.contains(e.target) || builderDropdown.contains(e.target)) {
                return;
            }

            builderDropdown.classList.remove("show-dropdown");
            builderButton.setAttribute("aria-expanded", "false");
        });

        document.addEventListener("keydown", (e) => {
            if (e.key !== "Escape") return;
            if (!builderDropdown.classList.contains("show-dropdown")) return;

            builderDropdown.classList.remove("show-dropdown");
            builderButton.setAttribute("aria-expanded", "false");
            builderButton.focus();
        });
    }

    // Two Log Out links exist now (the desktop dropdown's, and the flat
    // mobile list's) — a shared class, not a shared id (ids must be
    // unique per document), so both get the same handler here.
    navbar.querySelectorAll(".logout-link").forEach(link => {
        link.addEventListener("click", async (e) => {
            e.preventDefault();
            await supabase.auth.signOut();
            clearCurrentUserCache();
            window.location.href = `${pathPrefix}index.html`;
        });
    });
}

export function loadFooter(pathPrefix = "") {
    ensureToastContainer();

    const footer = document.getElementById("footer");
    if (!footer) return;

    footer.innerHTML = `
        <div class="footer-inner">
            <div class="footer-brand">
                <h2>SPECBOUND</h2>
                <p>Document Every Build.</p>
                <p class="footer-version">v0.9.0</p>
            </div>

            <nav class="footer-group" aria-labelledby="footerPlatformHeading">
                <h3 id="footerPlatformHeading">Platform</h3>
                <a href="${pathPrefix}pages/explore.html">Explore</a>
                <a href="${pathPrefix}pages/upload.html">Publish</a>
                <a href="${pathPrefix}index.html#technologies">Categories</a>
            </nav>

            <nav class="footer-group" aria-labelledby="footerBuildersHeading">
                <h3 id="footerBuildersHeading">Builders</h3>
                <a href="${pathPrefix}pages/workshop.html">Workshop</a>
                <a href="${pathPrefix}pages/explore.html">Profiles</a>
                <button type="button" id="footerFeedbackBtn">Feedback</button>
            </nav>

            <nav class="footer-group" aria-labelledby="footerLegalHeading">
                <h3 id="footerLegalHeading">Legal</h3>
                <a href="${pathPrefix}pages/legal/privacy.html">Privacy</a>
                <a href="${pathPrefix}pages/legal/terms.html">Terms</a>
                <a href="${pathPrefix}pages/legal/community-guidelines.html">Community Guidelines</a>
            </nav>
        </div>
    `;

    // Milestone 22 §9 — one link's worth of footprint, not a new footer
    // section. Signed-out visitors are sent to sign in rather than
    // silently failing on submit_feedback()'s own auth.uid() check
    // (0029_feedback_submissions.sql) — the same "explain, don't fail
    // silently" posture as every other auth-gated action in this app.
    const feedbackBtn = document.getElementById("footerFeedbackBtn");

    if (feedbackBtn) {
        feedbackBtn.addEventListener("click", async () => {
            const user = await getCurrentUser();

            if (!user) {
                window.location.href = `${pathPrefix}pages/login.html`;
                return;
            }

            const { showFeedbackModal } = await import("../components/FeedbackModal.js");
            showFeedbackModal();
        });
    }
}

// A visually-hidden-until-focused link, inserted as the very first
// element in <body> on every page. This app has no client-side router
// (every navigation is a full page load), so a keyboard user otherwise
// has to tab through the entire navbar (logo, nav toggle, search,
// primary links, notification bell, builder menu) on every single page
// view before reaching real content.
function insertSkipLink() {
    if (document.getElementById("skipLink")) return;

    document.body.insertAdjacentHTML(
        "afterbegin",
        `<a href="#main" id="skipLink" class="skip-link">Skip to content</a>`
    );
}

function ensureToastContainer() {
    if (document.getElementById("toastContainer")) return;

    const container = document.createElement("div");
    container.id = "toastContainer";
    container.className = "toast-container";
    container.setAttribute("role", "status");
    container.setAttribute("aria-live", "polite");

    document.body.appendChild(container);
}