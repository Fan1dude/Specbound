import {
    getUnreadNotificationCount,
    getRecentNotifications,
    markNotificationRead,
    markAllNotificationsRead,
    enrichNotifications
} from "../repositories/notificationRepository.js";

import { formatNotificationText, getNotificationUrl, formatRelativeTime } from "../utils/notificationFormat.js";
import { showToast } from "./toast.js";

// Called once from loadNavbar() when a user is signed in. Renders the
// bell button + badge + dropdown into the given container and wires up
// all of its behavior. The unread count is fetched immediately (cheap,
// needed for the badge on every page); the dropdown's actual notification
// list is lazy-loaded only the first time it's opened, so most page loads
// don't pay for it.
export async function initNotificationBell(container, { user, pathPrefix = "" }) {
    if (!container || !user) return;

    container.innerHTML = `
        <div class="notification-bell" id="notificationBell">
            <button
                class="notification-bell-button"
                id="notificationBellButton"
                type="button"
                aria-haspopup="true"
                aria-expanded="false"
                aria-label="Notifications"
            >
                <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                    <path d="M18 8a6 6 0 0 0-12 0c0 7-3 9-3 9h18s-3-2-3-9"></path>
                    <path d="M13.73 21a2 2 0 0 1-3.46 0"></path>
                </svg>

                <span class="notification-badge" id="notificationBadge" hidden>0</span>
            </button>

            <div class="notification-dropdown" id="notificationDropdown">
                <div class="notification-dropdown-header">
                    <p>Notifications</p>

                    <button type="button" class="notification-mark-all" id="notificationMarkAllRead">
                        Mark all read
                    </button>
                </div>

                <div id="notificationDropdownList" class="notification-dropdown-list" role="status" aria-live="polite">
                    <p class="text-secondary notification-dropdown-message">Loading...</p>
                </div>

                <a href="${pathPrefix}pages/notifications.html" class="notification-dropdown-viewall">
                    View all notifications
                </a>
            </div>
        </div>
    `;

    const bellButton = document.getElementById("notificationBellButton");
    const dropdown = document.getElementById("notificationDropdown");
    const badge = document.getElementById("notificationBadge");
    const listEl = document.getElementById("notificationDropdownList");
    const markAllButton = document.getElementById("notificationMarkAllRead");

    let hasLoadedList = false;

    await refreshBadge();

    bellButton.addEventListener("click", async () => {
        const isOpen = dropdown.classList.toggle("show-dropdown");
        bellButton.setAttribute("aria-expanded", String(isOpen));

        if (isOpen && !hasLoadedList) {
            hasLoadedList = true;
            await loadList();
        }
    });

    document.addEventListener("click", event => {
        if (bellButton.contains(event.target) || dropdown.contains(event.target)) {
            return;
        }

        dropdown.classList.remove("show-dropdown");
        bellButton.setAttribute("aria-expanded", "false");
    });

    document.addEventListener("keydown", event => {
        if (event.key !== "Escape") return;
        if (!dropdown.classList.contains("show-dropdown")) return;

        dropdown.classList.remove("show-dropdown");
        bellButton.setAttribute("aria-expanded", "false");
        bellButton.focus();
    });

    markAllButton.addEventListener("click", async () => {
        markAllButton.disabled = true;

        try {
            await markAllNotificationsRead();

            listEl.querySelectorAll(".notification-item").forEach(item => {
                item.classList.remove("is-unread");
            });

            await refreshBadge();
        } catch (error) {
            console.error("Mark all notifications read error:", error);
            showToast(error.message || "Could not mark notifications as read.", "error");
        } finally {
            markAllButton.disabled = false;
        }
    });

    async function refreshBadge() {
        try {
            const count = await getUnreadNotificationCount();

            if (count > 0) {
                badge.textContent = count > 99 ? "99+" : String(count);
                badge.hidden = false;
            } else {
                badge.hidden = true;
            }
        } catch (error) {
            console.error("Unread notification count error:", error);
        }
    }

    async function loadList() {
        try {
            const notifications = await enrichNotifications(await getRecentNotifications(8));

            if (!notifications.length) {
                listEl.innerHTML = `<p class="text-secondary notification-dropdown-message">No notifications yet.</p>`;
                return;
            }

            listEl.innerHTML = notifications.map(renderItem).join("");

            listEl.querySelectorAll(".notification-item").forEach(item => {
                item.addEventListener("click", () => {
                    const id = item.dataset.id;

                    if (item.classList.contains("is-unread")) {
                        item.classList.remove("is-unread");

                        // Not awaited — this is a real link navigating away
                        // immediately; the read-state update happens in the
                        // background and shouldn't delay the click.
                        markNotificationRead(id)
                            .then(refreshBadge)
                            .catch(error => console.error("Mark notification read error:", error));
                    }
                });
            });
        } catch (error) {
            console.error("Notification list load error:", error);
            listEl.innerHTML = `<p class="text-secondary notification-dropdown-message">Could not load notifications. Try refreshing the page.</p>`;
        }
    }

    function renderItem(notification) {
        return `
            <a
                class="notification-item ${notification.read_at ? "" : "is-unread"}"
                data-id="${escapeAttribute(notification.id)}"
                href="${escapeAttribute(getNotificationUrl(notification, pathPrefix))}"
            >
                <span class="notification-item-text">${escapeHtml(formatNotificationText(notification))}</span>
                <span class="notification-item-time">${escapeHtml(formatRelativeTime(notification.created_at))}</span>
            </a>
        `;
    }
}

function escapeHtml(value) {
    return String(value)
        .replaceAll("&", "&amp;")
        .replaceAll("<", "&lt;")
        .replaceAll(">", "&gt;")
        .replaceAll('"', "&quot;")
        .replaceAll("'", "&#039;");
}

function escapeAttribute(value) {
    return escapeHtml(value);
}
