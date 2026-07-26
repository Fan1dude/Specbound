import { hasLikedBuild, setBuildLike } from "../../repositories/likeRepository.js";
import { showToast } from "../../core/toast.js";

// Likes belong to the build, not a revision (see
// supabase/migrations/0008_project_likes.sql) — called with the same
// `build` object from both renderBuild() (latest) and renderRevisionView()
// (historical revision), same as renderCreator()/renderComments().
export async function renderLike(build, currentUser) {
    const button = document.getElementById("likeBtn");
    const countEl = document.getElementById("likeCount");
    const hint = document.getElementById("likeHint");

    if (!button || !countEl) return;

    const isPublic = build.visibility === "public";

    let liked = false;

    countEl.textContent = String(build.likes_count || 0);

    if (currentUser && isPublic) {
        try {
            liked = await hasLikedBuild(build.id);
        } catch (error) {
            // Fail soft — the count above already rendered from the build
            // row, so a failed "did I like this" check shouldn't block the
            // rest of the page. The button just starts in the unliked
            // visual state.
            console.error("Like status load error:", error);
        }
    }

    setButtonState(liked);

    if (!currentUser) {
        button.disabled = true;
        setHint(`<a href="../login.html">Sign in</a> to like this project.`);
    } else if (!isPublic) {
        button.disabled = true;
        setHint("Likes are only available once this project is public.");
    } else {
        button.disabled = false;
        setHint(null);
    }

    button.onclick = async () => {
        if (button.disabled) return;

        const nextLiked = !liked;
        const previousLiked = liked;
        const previousCount = Number(countEl.textContent) || 0;
        const nextCount = Math.max(0, previousCount + (nextLiked ? 1 : -1));

        liked = nextLiked;
        setButtonState(liked);
        countEl.textContent = String(nextCount);
        button.disabled = true;

        try {
            const result = await setBuildLike(build.id, nextLiked);

            liked = result.liked;
            setButtonState(liked);
            countEl.textContent = String(result.likesCount);
        } catch (error) {
            console.error("Like update error:", error);

            liked = previousLiked;
            setButtonState(liked);
            countEl.textContent = String(previousCount);

            showToast(error.message || "Could not update your like.", "error");
        } finally {
            button.disabled = false;
        }
    };

    function setButtonState(isLiked) {
        button.classList.toggle("is-liked", isLiked);
        button.setAttribute("aria-pressed", String(isLiked));
    }

    function setHint(html) {
        if (!hint) return;

        if (!html) {
            hint.hidden = true;
            hint.innerHTML = "";
            return;
        }

        hint.hidden = false;
        hint.innerHTML = html;
    }
}
