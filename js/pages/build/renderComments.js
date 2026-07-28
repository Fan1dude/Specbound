import { getBuildComments, createComment, deleteComment } from "../../repositories/commentRepository.js";
import { getProfilesByIds } from "../../repositories/profileRepository.js";
import { resolveAvatarUrls } from "../../repositories/mediaRepository.js";
import { showToast } from "../../core/toast.js";
import { escapeHtml, escapeAttribute } from "../../utils/escapeHtml.js";
import { formatDate } from "../../utils/formatDate.js";
import { avatarInitial } from "../../utils/avatarInitial.js";
import { confirmDialog } from "../../utils/modal.js";
import { commentsSkeleton } from "../../utils/skeletons.js";
import { icon } from "../../utils/icons.js";

const PAGE_SIZE = 50;

// currentUser is whoever is viewing the page right now (or null if signed
// out) — separate from build.user_id, the project's owner, since either
// can delete a given comment (see delete_comment() in
// supabase/migrations/0007_comments.sql) and only the owner sees it as
// "my project," not "my comment."
export async function renderComments(build, currentUser) {
    const composeArea = document.getElementById("commentComposeArea");
    const listEl = document.getElementById("commentsList");
    const loadMoreBtn = document.getElementById("commentsLoadMore");

    if (!listEl) return;

    let comments = [];
    let hasMore = false;

    renderCompose();

    listEl.setAttribute("role", "status");
    listEl.setAttribute("aria-live", "polite");
    listEl.setAttribute("aria-label", "Loading comments");
    listEl.innerHTML = commentsSkeleton();
    if (loadMoreBtn) loadMoreBtn.hidden = true;

    try {
        comments = await getBuildComments(build.id, { limit: PAGE_SIZE });
        hasMore = comments.length === PAGE_SIZE;
    } catch (error) {
        console.error("Comments load error:", error);
        listEl.innerHTML = `<p class="text-secondary">Could not load comments. Try refreshing the page.</p>`;
        return;
    }

    await renderList();

    if (loadMoreBtn) {
        loadMoreBtn.addEventListener("click", async () => {
            loadMoreBtn.disabled = true;
            loadMoreBtn.textContent = "Loading...";

            try {
                // Comments render oldest-first (a thread, not a feed), so
                // "Load More" continues forward from the last comment
                // already shown, not backward in time like every other
                // paginated list in this app.
                const lastLoaded = comments[comments.length - 1]?.created_at;
                const nextPage = await getBuildComments(build.id, { after: lastLoaded, limit: PAGE_SIZE });

                comments = [...comments, ...nextPage];
                hasMore = nextPage.length === PAGE_SIZE;

                // Appends only the newly-fetched page instead of
                // re-rendering everything already shown — post/delete
                // still do a full renderList() below (they're small,
                // single-item mutations where simplicity/correctness
                // matters more than render cost), but repeatedly clicking
                // Load More on a long thread shouldn't get progressively
                // more expensive.
                await appendComments(nextPage);

                if (loadMoreBtn) loadMoreBtn.hidden = !hasMore;
            } catch (error) {
                console.error("Comments load more error:", error);
            } finally {
                loadMoreBtn.disabled = false;
                loadMoreBtn.textContent = "Load More";
            }
        });
    }

    function renderCompose() {
        if (!composeArea) return;

        if (!currentUser) {
            composeArea.innerHTML = `
                <p class="comment-signed-out">
                    <a href="../login.html">Sign in</a> to leave a comment.
                </p>
            `;
            return;
        }

        composeArea.innerHTML = `
            <form id="commentForm" class="comment-form">
                <label for="commentBody" class="sr-only">Write a comment</label>
                <textarea
                    id="commentBody"
                    class="comment-textarea"
                    placeholder="Share your thoughts..."
                    rows="3"
                    maxlength="2000"
                    aria-describedby="commentFormHint"
                ></textarea>

                <div class="comment-form-footer">
                    <p id="commentFormHint" class="comment-form-hint" role="status" aria-live="polite" hidden></p>

                    <button type="submit" id="commentSubmitBtn" class="btn btn-primary btn-small">
                        Post Comment
                    </button>
                </div>
            </form>
        `;

        const form = document.getElementById("commentForm");
        const textarea = document.getElementById("commentBody");
        const submitBtn = document.getElementById("commentSubmitBtn");
        const hint = document.getElementById("commentFormHint");

        form.addEventListener("submit", async event => {
            event.preventDefault();

            const body = textarea.value.trim();

            if (!body) {
                // A visible line of text, not a title/tooltip attribute —
                // the same lesson from the Restore/Publish disabled-state
                // fix: an inert control with no visible explanation reads
                // as broken, not as "you need to type something first."
                hint.textContent = "Write something before posting.";
                hint.hidden = false;
                return;
            }

            hint.hidden = true;
            textarea.disabled = true;
            submitBtn.disabled = true;
            submitBtn.textContent = "Posting...";

            try {
                const comment = await createComment(build.id, body);

                comments = [...comments, comment];
                textarea.value = "";

                await renderList();
                showToast("Comment posted.", "success");
            } catch (error) {
                console.error("Comment post error:", error);
                showToast(error.message || "Could not post your comment.", "error");
            } finally {
                textarea.disabled = false;
                submitBtn.disabled = false;
                submitBtn.textContent = "Post Comment";
            }
        });
    }

    // Resolves a batch of comments' authors + avatars in two queries total
    // (not one per comment) and returns their rendered markup, without
    // touching the DOM itself — shared by the full renderList() (the whole
    // comments array) and appendComments() (just a newly-fetched page).
    async function renderCommentsBatch(commentsBatch) {
        const uniqueUserIds = [...new Set(commentsBatch.map(comment => comment.user_id))];

        let profiles = [];

        try {
            profiles = await getProfilesByIds(uniqueUserIds);
        } catch (error) {
            console.error("Comment authors load error:", error);
        }

        const profilesById = new Map(profiles.map(profile => [profile.id, profile]));

        // One Storage request for every distinct author's avatar, not one
        // per comment — a prolific commenter's avatar is only signed once
        // here regardless of how many comments they've posted.
        const avatarUrlByProfileId = await resolveAvatarUrls(profiles);

        return commentsBatch
            .map(comment => renderCommentItem(
                comment,
                profilesById.get(comment.user_id),
                avatarUrlByProfileId.get(comment.user_id) || ""
            ))
            .join("");
    }

    async function renderList() {
        if (!comments.length) {
            listEl.innerHTML = `
                <div class="empty-state compact-empty-state">
                    <div class="empty-state-icon">${icon("document", 32)}</div>
                    <h3>Be the first to weigh in on this build.</h3>
                </div>
            `;
            if (loadMoreBtn) loadMoreBtn.hidden = true;
            return;
        }

        // Re-fetched on every post/delete rather than incrementally
        // patched — this stays the simple, always-correct full rebuild
        // for those two small, single-item mutations. Load More (above)
        // is the one case that appends instead, since it's the one case
        // where the accumulated list can realistically grow large.
        listEl.innerHTML = await renderCommentsBatch(comments);

        bindDeleteButtons(listEl.querySelectorAll(".comment-delete-btn"));

        if (loadMoreBtn) loadMoreBtn.hidden = !hasMore;
    }

    // Builds the new comments' markup in a detached fragment, binds their
    // delete-button listeners while still detached, then inserts the
    // whole fragment in one operation — existing comments (and their
    // already-bound listeners) are never touched.
    async function appendComments(newComments) {
        const html = await renderCommentsBatch(newComments);

        const temp = document.createElement("div");
        temp.innerHTML = html;

        const fragment = document.createDocumentFragment();

        while (temp.firstChild) {
            fragment.appendChild(temp.firstChild);
        }

        bindDeleteButtons(fragment.querySelectorAll(".comment-delete-btn"));

        listEl.appendChild(fragment);
    }

    function bindDeleteButtons(buttons) {
        buttons.forEach(button => {
            button.addEventListener("click", async () => {
                const confirmed = await confirmDialog({
                    title: "Delete this comment?",
                    body: "This can't be undone.",
                    confirmLabel: "Delete",
                    danger: true
                });

                if (!confirmed) return;

                const commentId = button.dataset.id;

                button.disabled = true;

                try {
                    await deleteComment(commentId);

                    comments = comments.filter(comment => comment.id !== commentId);

                    await renderList();
                    showToast("Comment deleted.", "success");
                } catch (error) {
                    console.error("Comment delete error:", error);
                    showToast(error.message || "Could not delete this comment.", "error");
                    button.disabled = false;
                }
            });
        });
    }

    function renderCommentItem(comment, profile, avatarUrl) {
        const username = profile?.username || profile?.display_name || "Specbound Member";

        const canDelete = Boolean(currentUser) &&
            (currentUser.id === comment.user_id || currentUser.id === build.user_id);

        return `
            <article class="comment-item" data-id="${escapeAttribute(comment.id)}">
                <div class="comment-avatar">
                    ${avatarUrl
                        ? `<img src="${escapeAttribute(avatarUrl)}" alt="${escapeAttribute(username)}" loading="lazy">`
                        : escapeHtml(avatarInitial(username))
                    }
                </div>

                <div class="comment-body-wrap">
                    <div class="comment-meta">
                        <a href="../profile.html?user=${encodeURIComponent(comment.user_id)}" class="comment-author">
                            ${escapeHtml(username)}
                        </a>

                        <time class="comment-date" datetime="${escapeAttribute(comment.created_at)}">
                            ${formatDate(comment.created_at)}
                        </time>
                    </div>

                    <p class="comment-body">${escapeHtml(comment.body)}</p>
                </div>

                ${
                    canDelete
                        ? `
                            <button
                                type="button"
                                class="btn btn-ghost btn-small comment-delete-btn"
                                data-id="${escapeAttribute(comment.id)}"
                                aria-label="Delete this comment"
                            >
                                Delete
                            </button>
                        `
                        : ""
                }
            </article>
        `;
    }
}


