import {
    getNotificationsPage,
    markAllNotificationsRead,
    markNotificationRead,
    enrichNotifications
} from "../../repositories/notificationRepository.js";

import { formatNotificationText, getNotificationUrl, formatRelativeTime } from "../../utils/notificationFormat.js";
import { showToast } from "../../core/toast.js";

const PAGE_SIZE = 20;

// Self-contained, same shape as renderComments.js — fetches its own data
// and owns its own list state across mutations (load more, mark
// read/mark all read), re-rendering the whole list each time rather than
// patching individual rows.
export async function renderNotifications() {
    const listEl = document.getElementById("notificationsList");
    const loadMoreBtn = document.getElementById("notificationsLoadMore");
    const markAllBtn = document.getElementById("notificationsMarkAllRead");

    if (!listEl) return;

    let notifications = [];
    let hasMore = false;

    listEl.innerHTML = `<p class="text-secondary">Loading notifications...</p>`;

    try {
        const page = await enrichNotifications(await getNotificationsPage({ limit: PAGE_SIZE }));

        notifications = page;
        hasMore = page.length === PAGE_SIZE;
    } catch (error) {
        console.error("Notifications load error:", error);
        listEl.innerHTML = `<p class="text-secondary">Could not load notifications. Try refreshing the page.</p>`;
        return;
    }

    renderList();

    if (markAllBtn) {
        markAllBtn.addEventListener("click", async () => {
            markAllBtn.disabled = true;

            try {
                await markAllNotificationsRead();

                notifications = notifications.map(notification => ({
                    ...notification,
                    read_at: notification.read_at || new Date().toISOString()
                }));

                renderList();
            } catch (error) {
                console.error("Mark all notifications read error:", error);
                showToast(error.message || "Could not mark notifications as read.", "error");
            } finally {
                markAllBtn.disabled = false;
            }
        });
    }

    if (loadMoreBtn) {
        loadMoreBtn.addEventListener("click", async () => {
            loadMoreBtn.disabled = true;
            loadMoreBtn.textContent = "Loading...";

            try {
                const oldestLoaded = notifications[notifications.length - 1]?.created_at;

                const nextPage = await enrichNotifications(
                    await getNotificationsPage({ before: oldestLoaded, limit: PAGE_SIZE })
                );

                notifications = [...notifications, ...nextPage];
                hasMore = nextPage.length === PAGE_SIZE;

                // Appends only the newly-fetched page instead of
                // re-rendering every previously-loaded row — rendering
                // cost stays proportional to the new page, not to
                // everything loaded so far across every previous Load
                // More click. Mark all read still does a full renderList()
                // below, since it genuinely needs to update every visible
                // row's state, not just append new ones.
                appendRows(nextPage);

                if (loadMoreBtn) loadMoreBtn.hidden = !hasMore;
            } catch (error) {
                console.error("Notifications load more error:", error);
            } finally {
                loadMoreBtn.disabled = false;
                loadMoreBtn.textContent = "Load More";
            }
        });
    }

    function renderList() {
        if (!notifications.length) {
            listEl.innerHTML = `
                <div class="empty-state">
                    <h3>No notifications yet.</h3>
                    <p>You'll see comments, likes, and saves on your projects here.</p>
                </div>
            `;

            if (loadMoreBtn) loadMoreBtn.hidden = true;
            return;
        }

        listEl.innerHTML = notifications.map(renderRow).join("");
        bindRowListeners(listEl.querySelectorAll(".notification-row"));

        if (loadMoreBtn) loadMoreBtn.hidden = !hasMore;
    }

    // Builds the new rows' markup in a detached fragment, binds their
    // click listeners while still detached, then inserts the whole
    // fragment in one operation — existing rows (and their already-bound
    // listeners) are never touched.
    function appendRows(newNotifications) {
        const temp = document.createElement("div");

        temp.innerHTML = newNotifications.map(renderRow).join("");

        const fragment = document.createDocumentFragment();

        while (temp.firstChild) {
            fragment.appendChild(temp.firstChild);
        }

        bindRowListeners(fragment.querySelectorAll(".notification-row"));

        listEl.appendChild(fragment);
    }

    function bindRowListeners(rows) {
        rows.forEach(row => {
            row.addEventListener("click", () => {
                const id = row.dataset.id;

                if (row.classList.contains("is-unread")) {
                    row.classList.remove("is-unread");

                    // Not awaited — a real link navigating away
                    // immediately; the read-state update happens in the
                    // background and shouldn't delay the click.
                    markNotificationRead(id).catch(error =>
                        console.error("Mark notification read error:", error)
                    );
                }
            });
        });
    }

    function renderRow(notification) {
        return `
            <a
                class="notification-row ${notification.read_at ? "" : "is-unread"}"
                data-id="${escapeAttribute(notification.id)}"
                href="${escapeAttribute(getNotificationUrl(notification, "../"))}"
            >
                <span class="notification-row-text">${escapeHtml(formatNotificationText(notification))}</span>
                <span class="notification-row-time">${escapeHtml(formatRelativeTime(notification.created_at))}</span>
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
