import { getBuildBySlug } from "../../repositories/buildRepository.js";
import { getBuildRevisions, getRevisionById } from "../../repositories/revisionRepository.js";
import { getPublicProfile } from "../../repositories/profileRepository.js";
import { getRevisionMedia } from "../../repositories/mediaRepository.js";
import { getDraftByPublishedBuildId } from "../../repositories/draftRepository.js";
import { restoreRevisionToDraft } from "../../repositories/publishRepository.js";
import { getCurrentUser } from "../../core/auth.js";
import { showToast } from "../../core/toast.js";
import { renderErrorState, renderLoadingState } from "../../utils/listState.js";
import { confirmDialog } from "../../utils/modal.js";

import { renderBuild, renderRevisionView } from "./renderBuild.js";
import { renderSpecifications } from "./renderSpecifications.js";
import { renderResources } from "./renderResources.js";
import { renderTimeline } from "./renderTimeline.js";
import { renderComments } from "./renderComments.js";
import { renderLike } from "./renderLike.js";
import { renderSave } from "./renderSave.js";
import { recordBuildView } from "../../repositories/viewRepository.js";

export async function loadBuild() {
    const params = new URLSearchParams(window.location.search);
    const slug = params.get("slug");
    const revisionId = params.get("revision");

    if (!slug) {
        window.location.href = "../../index.html";
        return;
    }

    // Primary: the build itself. Nothing below this point should be able
    // to clobber it once it's rendered — a secondary section failing
    // (revisions, comments, likes, saves) degrades that one section only.
    let build;

    try {
        build = await getBuildBySlug(slug);
    } catch (error) {
        console.error("Build page error:", error);
        showBuildUnavailable();
        return;
    }

    // Secondary: creator profile — only affects the "Built by {name}"
    // byline, not whether the build itself can render.
    let profile = null;

    try {
        if (build.user_id) {
            profile = await getPublicProfile(build.user_id);
        }
    } catch (error) {
        console.error("Creator profile load error:", error);
    }

    build.profiles = profile;

    // Secondary: revision history. A real failure here is now
    // distinguishable from "this build genuinely has no revisions yet"
    // (see revisionRepository.js) — revisionsFailed tracks that
    // distinction so the timeline section below can show an honest error
    // instead of a misleading "no history" empty state. latestRevision
    // falls back to null either way, which renderBuild() already renders
    // sensible defaults for (0% progress, "v0.1", the build's own
    // updated_at as the date) — a revisions failure degrades the overview
    // stats, it doesn't block the rest of the primary build content.
    let revisions = [];
    let revisionsFailed = false;

    try {
        revisions = await getBuildRevisions(build.id);
    } catch (error) {
        console.error("Revision history load error:", error);
        revisionsFailed = true;
    }

    const latestRevision =
        revisions.length > 0
            ? revisions[revisions.length - 1]
            : null;

    // Secondary: current viewer identity — a failure here degrades to
    // "treated as signed out" (no edit action, no like/save/comment
    // compose, anonymous view tracking), not a broken page.
    let currentUser = null;

    try {
        currentUser = await getCurrentUser();
    } catch (error) {
        console.error("Current user load error:", error);
    }

    // Primary render. Everything above this point that failed already
    // degraded to a safe fallback value rather than throwing, so reaching
    // here means the build itself is known-good — a failure inside this
    // block is a real rendering problem with the primary content, and
    // still gets the page-level error state.
    try {
        if (revisionId) {
            await loadRevisionView(build, revisionId, currentUser);
        } else {
            // The edit action only ever makes sense for the build's own
            // owner, and only once a draft is actually linked to it — so
            // this is looked up (and the ownership check made) here, not
            // assumed. Everyone else sees no edit action at all.
            let editDraftId = null;

            if (currentUser && currentUser.id === build.user_id) {
                try {
                    const linkedDraft = await getDraftByPublishedBuildId(build.id);
                    editDraftId = linkedDraft?.id || null;
                } catch (error) {
                    console.error("Could not load this project's linked draft:", error);
                }
            }

            await renderBuild(build, latestRevision, { editDraftId });
            renderSpecifications(build.specifications || {});
            // resources only exist on build_revisions (see Milestone 5C) —
            // builds has no column for them, so "current" resources are the
            // latest revision's snapshot, not something read off `build`.
            renderResources(latestRevision?.resources ?? []);
        }
    } catch (error) {
        console.error("Build page error:", error);
        showBuildUnavailable();
        return;
    }

    // Secondary: the revision timeline. Shown as a distinct, honest error
    // (with its own scoped retry — re-fetching only the revisions, never
    // the build/comments/likes/saves that already rendered successfully)
    // rather than silently falling back to renderTimeline([]), which
    // would render "Start Your Project Log" and misleadingly imply this
    // build has no history at all.
    if (revisionsFailed) {
        renderErrorState(document.getElementById("revisionTimeline"), {
            message: "Could not load this project's revision history. Try again.",
            onRetry: () => retryTimeline(build)
        });
    } else {
        try {
            await renderTimeline(revisions, build.slug);
        } catch (error) {
            console.error("Timeline render error:", error);
        }
    }

    // Comments, likes, and saves all belong to the build, not a
    // revision (see supabase/migrations/0007_comments.sql,
    // 0008_project_likes.sql, and 0009_saved_builds.sql) — same data
    // regardless of whether ?revision= is present. Each is independently
    // isolated: any one of them throwing (each already fails soft
    // internally for its own primary concern, but this guards against an
    // unexpected error escaping anyway) must not take down the others or
    // the already-rendered primary build content above.
    try {
        await renderComments(build, currentUser);
    } catch (error) {
        console.error("Comments render error:", error);
    }

    try {
        await renderLike(build, currentUser);
    } catch (error) {
        console.error("Like render error:", error);
    }

    try {
        await renderSave(build, currentUser);
    } catch (error) {
        console.error("Save render error:", error);
    }

    // Not awaited — the page has already rendered with the
    // pre-increment count, and recording a view isn't something the
    // rest of the page should wait on. As soon as the RPC resolves,
    // the visible counter is patched in place with the authoritative
    // value (which may be unchanged, if this view didn't count — see
    // record_build_view() for why: owner, private, or cooldown).
    recordBuildView(build.id)
        .then(views => {
            const el = document.getElementById("overviewViews");

            if (el) el.textContent = views.toLocaleString();
        })
        .catch(error => console.error("View recording error:", error));
}

async function retryTimeline(build) {
    const container = document.getElementById("revisionTimeline");

    renderLoadingState(container, "Loading revision history...");

    try {
        const revisions = await getBuildRevisions(build.id);
        await renderTimeline(revisions, build.slug);
    } catch (error) {
        console.error("Revision history load error:", error);
        renderErrorState(container, {
            message: "Could not load this project's revision history. Try again.",
            onRetry: () => retryTimeline(build)
        });
    }
}

function showBuildUnavailable() {
    const title = document.getElementById("buildTitle");

    if (title) {
        title.textContent = "Blueprint unavailable";
    }

    const description = document.getElementById("buildDescription");

    if (description) {
        description.textContent = "This Blueprint could not be loaded.";
    }
}

async function loadRevisionView(build, revisionId, currentUser) {
    const revision = await getRevisionById(revisionId);

    if (!revision || revision.build_id !== build.id) {
        showToast("That revision could not be found for this project.", "error");

        window.location.href = `build.html?slug=${encodeURIComponent(build.slug)}`;
        return;
    }

    const revisionMedia = await getRevisionMedia(revision.id);
    const canRestore = Boolean(currentUser && currentUser.id === build.user_id);

    const snapshot = await renderRevisionView(build, revision, revisionMedia, { canRestore });

    renderSpecifications(snapshot.specifications);
    renderResources(snapshot.resources);

    if (canRestore) {
        setupRestoreButton(build, revision);
    }
}

export function setupRestoreButton(build, revision) {
    const button = document.getElementById("restoreRevisionBtn");

    if (!button) return;

    button.addEventListener("click", async () => {
        if (button.disabled) return;

        if (!revision.snapshot_title) {
            // Mirrors the disabled state renderRevisionView already sets
            // for this case — re-checked here rather than trusted solely
            // to the DOM attribute, the same lesson from the Milestone 5D
            // Publish-button bug (a disabled control not firing is not a
            // substitute for the handler knowing why it shouldn't proceed).
            showToast("This revision predates version history snapshots, so there's nothing to restore from it.", "warning");
            return;
        }

        const confirmed = await confirmDialog({
            title: `Restore ${revision.version || "this revision"} into your editable draft?`,
            body:
                "This replaces your current draft's title, description, category, specifications, resources, and gallery with this revision's content. " +
                "It does NOT change anything published — this revision and every other live revision stay exactly as they are. " +
                "You'll review the restored draft and publish it yourself when you're ready.",
            confirmLabel: "Restore"
        });

        if (!confirmed) return;

        button.disabled = true;
        button.textContent = "Restoring...";

        try {
            // Fetched right before the call (not cached from page load) so
            // the concurrency check reflects the draft's real current
            // state, not a stale snapshot from whenever this page opened.
            const existingDraft = await getDraftByPublishedBuildId(build.id);
            const draft = await restoreRevisionToDraft(revision.id, existingDraft?.updated_at ?? null);

            window.location.href = `edit.html?draft=${encodeURIComponent(draft.id)}`;
        } catch (error) {
            console.error("Restore error:", error);

            showToast(error.message || "Could not restore this revision.", "error");

            button.disabled = false;
            button.textContent = "Restore This Revision";
        }
    });
}
