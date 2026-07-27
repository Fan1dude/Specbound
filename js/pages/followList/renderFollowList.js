import { getFollowersPage, getFollowingPage, getFollowedIds, setFollow } from "../../repositories/followRepository.js";
import { getProfilesByIds } from "../../repositories/profileRepository.js";
import { resolveAvatarUrls } from "../../repositories/mediaRepository.js";
import { showToast } from "../../core/toast.js";
import { escapeHtml, escapeAttribute } from "../../utils/escapeHtml.js";
import { avatarInitial } from "../../utils/avatarInitial.js";

const PAGE_SIZE = 20;

// Self-contained, same shape as renderComments.js/renderNotifications.js —
// fetches its own data and owns its own list state across mutations
// (load more, per-row follow/unfollow), re-rendering the whole list each
// time rather than patching individual rows.
export async function renderFollowList(type, profileUserId, currentUser) {
    const listEl = document.getElementById("followListContainer");
    const loadMoreBtn = document.getElementById("followListLoadMore");

    if (!listEl) return;

    const getPage = type === "followers" ? getFollowersPage : getFollowingPage;
    const idKey = type === "followers" ? "follower_id" : "following_id";
    const nounLabel = type === "followers" ? "followers" : "following";

    let rows = [];
    let hasMore = false;

    listEl.innerHTML = `<p class="text-secondary">Loading ${nounLabel}...</p>`;

    try {
        const page = await getPage(profileUserId, { limit: PAGE_SIZE });

        rows = await enrich(page);
        hasMore = page.length === PAGE_SIZE;
    } catch (error) {
        console.error("Follow list load error:", error);
        listEl.innerHTML = `<p class="text-secondary">Could not load ${nounLabel}. Try refreshing the page.</p>`;
        return;
    }

    renderList();

    if (loadMoreBtn) {
        loadMoreBtn.addEventListener("click", async () => {
            loadMoreBtn.disabled = true;
            loadMoreBtn.textContent = "Loading...";

            try {
                const oldestLoaded = rows[rows.length - 1]?.createdAt;
                const nextPage = await getPage(profileUserId, { before: oldestLoaded, limit: PAGE_SIZE });
                const nextRows = await enrich(nextPage);

                rows = [...rows, ...nextRows];
                hasMore = nextPage.length === PAGE_SIZE;

                // Appends only the newly-fetched page's rows instead of
                // re-rendering the whole accumulated list — rendering cost
                // stays proportional to the new page, not to everything
                // loaded so far across every previous Load More click.
                appendRows(nextRows);

                if (loadMoreBtn) loadMoreBtn.hidden = !hasMore;
            } catch (error) {
                console.error("Follow list load more error:", error);
            } finally {
                loadMoreBtn.disabled = false;
                loadMoreBtn.textContent = "Load More";
            }
        });
    }

    // Batch-fetches profiles + avatars + the viewer's own follow status
    // for a whole page of rows in a handful of queries total, not one per
    // row — same no-FK, batch-fetch-then-map pattern as everywhere else
    // in this app. Avatars are signed in one Storage request for the
    // whole page (resolveAvatarUrls), not one request per row.
    async function enrich(page) {
        const ids = page.map(row => row[idKey]);

        if (!ids.length) return [];

        const profiles = await getProfilesByIds(ids);
        const profilesById = new Map(profiles.map(profile => [profile.id, profile]));

        let followedSet = new Set();

        if (currentUser) {
            try {
                followedSet = new Set(await getFollowedIds(currentUser.id, ids));
            } catch (error) {
                console.error("Follow status batch load error:", error);
            }
        }

        const avatarUrlByProfileId = await resolveAvatarUrls(profiles);

        return page.map(row => {
            const id = row[idKey];

            return {
                id,
                username: profilesById.get(id)?.username || "Specbound Member",
                avatarUrl: avatarUrlByProfileId.get(id) || "",
                createdAt: row.created_at,
                isFollowedByViewer: followedSet.has(id)
            };
        });
    }

    function renderList() {
        if (!rows.length) {
            const emptyText = type === "followers"
                ? "No followers yet."
                : "Not following anyone yet.";

            listEl.innerHTML = `<div class="empty-state"><h3>${emptyText}</h3></div>`;

            if (loadMoreBtn) loadMoreBtn.hidden = true;
            return;
        }

        listEl.innerHTML = rows.map(renderRow).join("");
        bindRowButtons(listEl.querySelectorAll(".follow-row-btn"));

        if (loadMoreBtn) loadMoreBtn.hidden = !hasMore;
    }

    // Builds the new rows' markup in a detached fragment, binds their
    // listeners while still detached, then inserts the whole fragment in
    // one operation — existing rows (and their already-bound listeners)
    // are never touched.
    function appendRows(newRows) {
        const temp = document.createElement("div");

        temp.innerHTML = newRows.map(renderRow).join("");

        const fragment = document.createDocumentFragment();

        while (temp.firstChild) {
            fragment.appendChild(temp.firstChild);
        }

        bindRowButtons(fragment.querySelectorAll(".follow-row-btn"));

        listEl.appendChild(fragment);
    }

    function bindRowButtons(buttons) {
        buttons.forEach(button => {
            button.addEventListener("click", async () => {
                const targetId = button.dataset.id;
                const row = rows.find(candidate => candidate.id === targetId);

                if (!row) return;

                const nextFollowed = !row.isFollowedByViewer;
                const previousFollowed = row.isFollowedByViewer;

                row.isFollowedByViewer = nextFollowed;
                updateRowButton(button, nextFollowed);
                button.disabled = true;

                try {
                    const result = await setFollow(targetId, nextFollowed);

                    // Reconcile against the RPC's authoritative followed
                    // value, just like Likes and Saves.
                    row.isFollowedByViewer = result.followed;
                    updateRowButton(button, result.followed);
                } catch (error) {
                    console.error("Follow update error:", error);

                    row.isFollowedByViewer = previousFollowed;
                    updateRowButton(button, previousFollowed);

                    showToast(error.message || "Could not update your follow status.", "error");
                } finally {
                    button.disabled = false;
                }
            });
        });
    }

    function renderRow(row) {
        const showButton = currentUser && currentUser.id !== row.id;

        return `
            <div class="follow-row">
                <a href="profile.html?user=${encodeURIComponent(row.id)}" class="follow-row-profile">
                    <span class="follow-row-avatar">
                        ${row.avatarUrl
                            ? `<img src="${escapeAttribute(row.avatarUrl)}" alt="${escapeAttribute(row.username)}" loading="lazy">`
                            : escapeHtml(avatarInitial(row.username))
                        }
                    </span>

                    <span class="follow-row-username">${escapeHtml(row.username)}</span>
                </a>

                ${showButton
                    ? `
                        <button
                            type="button"
                            class="btn btn-small follow-row-btn ${row.isFollowedByViewer ? "is-following" : ""}"
                            data-id="${escapeAttribute(row.id)}"
                        >
                            ${row.isFollowedByViewer ? "Following" : "Follow"}
                        </button>
                    `
                    : ""
                }
            </div>
        `;
    }

    function updateRowButton(button, isFollowed) {
        button.classList.toggle("is-following", isFollowed);
        button.textContent = isFollowed ? "Following" : "Follow";
    }
}

