import { supabase } from "./supabase.js";
import { getCurrentUser, clearCurrentUserCache } from "./auth.js";
import { initNotificationBell } from "./notificationBell.js";
import { maybeShowWelcome } from "./onboarding.js";
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

        authLinks = `
            <div class="builder-menu">
                <button class="builder-button" id="builderMenuButton">
                    ${escapeHtml(username)} ${icon("chevron-down", 16)}
                </button>

                <div class="builder-dropdown" id="builderDropdown">
                    <a href="${pathPrefix}pages/workshop.html">Workshop</a>
                    <a href="${pathPrefix}pages/profile.html?user=${user.id}">View My Profile</a>
                    <a href="${pathPrefix}pages/settings.html">Settings</a>
                    <hr>
                    <a href="#" id="logoutLink">Log Out</a>
                </div>
            </div>
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

            <input
                class="search-bar"
                type="text"
                placeholder="Search builds, builders, parts..."
                aria-label="Search builds, builders, parts"
            >

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

    const logoutLink = document.getElementById("logoutLink");

    if (logoutLink) {
        logoutLink.addEventListener("click", async (e) => {
            e.preventDefault();
            await supabase.auth.signOut();
            clearCurrentUserCache();
            window.location.href = `${pathPrefix}index.html`;
        });
    }
}

export function loadFooter(pathPrefix = "") {
    ensureToastContainer();

    const footer = document.getElementById("footer");
    if (!footer) return;

    footer.innerHTML = `
        <div class="footer-inner">
            <div>
                <h2>SPECBOUND</h2>
                <p>Document Every Build.</p>
                <p>v0.9.0</p>
            </div>

            <div>
                <h3>Platform</h3>
                <a href="${pathPrefix}pages/explore.html">Explore</a>
                <a href="${pathPrefix}pages/upload.html">Publish</a>
                <a href="${pathPrefix}index.html">Categories</a>
            </div>

            <div>
                <h3>Builders</h3>
                <a href="${pathPrefix}pages/workshop.html">Workshop</a>
                <a href="${pathPrefix}pages/explore.html">Profiles</a>
                <button type="button" id="footerFeedbackBtn">Feedback</button>
            </div>

            <div>
                <h3>Legal</h3>
                <a href="${pathPrefix}pages/legal/privacy.html">Privacy</a>
                <a href="${pathPrefix}pages/legal/terms.html">Terms</a>
                <a href="${pathPrefix}pages/legal/community-guidelines.html">Community Guidelines</a>
            </div>
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