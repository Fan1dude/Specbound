import { loadNavbar, loadFooter } from "../../core/layout.js";
import { requireAuth } from "../../core/auth.js";
import { showToast } from "../../core/toast.js";
import { getDraft, updateDraft } from "../../repositories/draftRepository.js";
import { publishDraft, setBuildVisibility } from "../../repositories/publishRepository.js";
import { getBuildById } from "../../repositories/buildRepository.js";
import { createAutosaveController } from "../../services/draftAutosave.js";
import { renderOverviewSection } from "./renderOverviewSection.js";
import { renderSpecificationsSection } from "./renderSpecificationsSection.js";
import { renderResourcesSection } from "./renderResourcesSection.js";
import { renderGallerySection } from "./renderGallerySection.js";
import { renderReadinessChecklist } from "./renderReadinessChecklist.js";
import { setupEditorTabs } from "./editorTabs.js";
import { setEditorStatus } from "./editorStatus.js";
import { maybeShowRecoveryBanner } from "./draftRecoveryBanner.js";

loadNavbar("../../");
loadFooter("../../");

setupEditorTabs();

const params = new URLSearchParams(window.location.search);
const draftId = params.get("draft");

if (!draftId) {
    window.location.href = "../upload.html";
} else {
    initEditor(draftId);
}

async function initEditor(id) {
    const user = await requireAuth("../login.html");
    if (!user) return;

    let draft;

    try {
        draft = await getDraft(id);
    } catch (error) {
        console.error("Draft load error:", error);
        showToast("Could not load this project draft.", "error");
        return;
    }

    if (!draft) {
        showToast("That draft doesn't exist, or you don't have access to it.", "error");
        setTimeout(() => {
            window.location.href = "../upload.html";
        }, 1200);
        return;
    }

    document.getElementById("editorTitle").textContent = draft.title || "Untitled project";

    // One autosave controller for the whole draft, shared by every section,
    // so there is exactly one save pipeline and one status indicator — not
    // a separate one per section.
    const statusEl = document.getElementById("editorSaveStatus");

    // Readiness previews what publish_draft() requires server-side — it
    // gates the Publish button, though the server re-validates regardless.
    // Reads Overview's fields live from the DOM and Gallery's media count
    // via a simple pushed variable (Gallery loads/mutates asynchronously
    // and independently of the autosave pipeline, so it notifies rather
    // than being polled).
    let mediaCount = 0;
    let isReady = false;
    let isPublishing = false;
    let isUnpublishing = false;
    let visibility = "public";

    const publishBtn = document.getElementById("editorPublishBtn");
    const publishHint = document.getElementById("editorPublishHint");
    const unpublishBtn = document.getElementById("editorUnpublishBtn");
    const publishBadge = document.getElementById("editorPublishBadge");
    const viewLiveLink = document.getElementById("editorViewLiveLink");

    const readiness = renderReadinessChecklist(() => mediaCount, ready => {
        isReady = ready;
        updatePublishBtn();
    });

    function updatePublishBtn() {
        if (publishBtn) {
            publishBtn.disabled = isPublishing || !isReady;

            // A disabled <button> never fires a click event at all — with
            // no explanation, that reads as "the button doesn't work"
            // rather than "readiness isn't met yet." A title/tooltip
            // attribute doesn't reliably do this: disabled elements
            // generally don't show their title on hover, so this is a
            // visible line of text instead, not just a devtools-visible
            // attribute.
            if (publishHint) {
                publishHint.hidden = !(!isReady && !isPublishing);
            }

            if (isPublishing) {
                publishBtn.textContent = "Publishing...";
            } else if (!draft.published_build_id) {
                publishBtn.textContent = "Publish";
            } else if (visibility === "private") {
                // Publishing is the action that makes a project live again —
                // there's no separate "make public" step, so the button
                // makes that explicit rather than reading like a routine
                // content update.
                publishBtn.textContent = "Publish Again";
            } else {
                publishBtn.textContent = "Update Live Version";
            }
        }

        if (unpublishBtn) {
            // Only offered once there's something live to take down, and
            // only while it actually is live — once unpublished, the way
            // back is Publish/"Publish Again", not a second button.
            unpublishBtn.hidden = !draft.published_build_id || visibility !== "public";
            unpublishBtn.disabled = isUnpublishing;
            unpublishBtn.textContent = isUnpublishing ? "Unpublishing..." : "Unpublish";
        }
    }

    function showPublished(build) {
        draft.published_build_id = build.id;
        visibility = build.visibility || "public";

        if (publishBadge) {
            if (visibility === "private") {
                publishBadge.textContent = "Unpublished";
                publishBadge.classList.remove("badge-success");
                publishBadge.classList.add("badge-unpublished");
            } else {
                publishBadge.textContent = "Published";
                publishBadge.classList.remove("badge-unpublished");
                publishBadge.classList.add("badge-success");
            }
        }

        if (viewLiveLink) {
            viewLiveLink.href = `../build/build.html?slug=${encodeURIComponent(build.slug)}`;
            viewLiveLink.textContent = visibility === "private" ? "Preview (unpublished) →" : "View live project →";
            viewLiveLink.hidden = false;
        }

        updatePublishBtn();
    }

    if (draft.published_build_id) {
        getBuildById(draft.published_build_id)
            .then(build => {
                if (build) {
                    showPublished(build);
                } else {
                    // The draft is linked to a build, but that build wasn't
                    // readable — RLS silently returns no row rather than an
                    // error here (see buildRepository.getBuildById), so this
                    // isn't a thrown exception to catch below. Previously
                    // this left the badge/button silently showing stale
                    // "public" defaults with no indication anything was
                    // wrong. Surfacing it so a real problem (e.g. the build
                    // was deleted) isn't mistaken for "Publish Again doing
                    // nothing."
                    console.error("Published build not found or not readable:", draft.published_build_id);
                    showToast("Could not load this project's published status — try refreshing.", "error");

                    // draft.published_build_id existing proves this WAS
                    // published at least once — leaving the badge at its
                    // raw-HTML "Draft" default here would misleadingly
                    // claim the opposite. Exact current visibility is
                    // unknown, so this doesn't call showPublished() (which
                    // would also claim a specific, unverified visibility);
                    // it just stops the badge from actively lying.
                    if (publishBadge) {
                        publishBadge.textContent = "Published";
                        publishBadge.classList.remove("badge-unpublished");
                    }
                }
            })
            .catch(error => {
                console.error("Could not load published build:", error);
                showToast("Could not load this project's published status — try refreshing.", "error");
            });
    }

    publishBtn?.addEventListener("click", async () => {
        if (isPublishing) return;

        if (!isReady) {
            // A disabled button shouldn't dispatch a click at all, so
            // reaching this with isReady false means either state managed
            // to desync from the DOM, or this fired some other way — either
            // way, say so instead of returning silently.
            console.warn("Publish blocked: readiness checklist not complete.", { draftId: draft.id, publishedBuildId: draft.published_build_id, visibility });
            showToast("Complete the readiness checklist before publishing.", "warning");
            return;
        }

        console.log("Publishing draft:", { draftId: draft.id, publishedBuildId: draft.published_build_id, visibilityBeforePublish: visibility });

        isPublishing = true;
        updatePublishBtn();

        try {
            // Publish reads project_drafts server-side, so anything still
            // only in the local autosave buffer or debounce window has to
            // reach the server first, or publishing could snapshot stale
            // content.
            await autosave.flushNow();

            const build = await publishDraft(draft.id);

            console.log("Publish succeeded:", { buildId: build?.id, visibilityAfterPublish: build?.visibility });

            showPublished(build);
            showToast("Project published.", "success");
        } catch (error) {
            // Log the full error object, not just .message — Postgrest
            // errors carry .details/.hint/.code too, and a thrown
            // non-Postgrest error (e.g. a network failure) may not have a
            // usable .message at all, which is exactly the shape that goes
            // silent if the fallback string is skipped.
            console.error("Publish error:", error);
            showToast(error?.message || "Could not publish this project. Check the console for details.", "error");
        } finally {
            isPublishing = false;
            updatePublishBtn();
        }
    });

    unpublishBtn?.addEventListener("click", async () => {
        if (isUnpublishing || !draft.published_build_id) return;

        const confirmed = confirm(
            "Unpublish this project?\n\n" +
            "It will no longer appear on Home, Explore, or your public profile, and direct links will stop working for other people. " +
            "Nothing is deleted — your drafts, gallery, and full version history stay exactly as they are, and you can publish again anytime."
        );

        if (!confirmed) return;

        isUnpublishing = true;
        updatePublishBtn();

        try {
            const build = await setBuildVisibility(draft.published_build_id, "private");

            visibility = build.visibility;

            if (publishBadge) {
                publishBadge.textContent = "Unpublished";
                publishBadge.classList.remove("badge-success");
                publishBadge.classList.add("badge-unpublished");
            }

            if (viewLiveLink) {
                viewLiveLink.textContent = "Preview (unpublished) →";
            }

            showToast("Project unpublished.", "success");
        } catch (error) {
            console.error("Unpublish error:", error);
            showToast(error.message || "Could not unpublish this project.", "error");
        } finally {
            isUnpublishing = false;
            updatePublishBtn();
        }
    });

    const autosave = createAutosaveController({
        draftId: draft.id,
        save: fields => updateDraft(draft.id, fields),
        onStatusChange: (status, savedAt) => {
            setEditorStatus(statusEl, status, savedAt);
            readiness.update();
        }
    });

    setEditorStatus(statusEl, "saved", draft.updated_at);

    const overview = renderOverviewSection(draft, autosave);
    const specifications = renderSpecificationsSection(draft, autosave);
    const resources = renderResourcesSection(draft, autosave);

    renderGallerySection(draft, count => {
        mediaCount = count;
        readiness.update();
    });

    // A recovered buffer can contain fields from any section that shares
    // this draft's autosave controller (title/description/category,
    // specifications, resources — Gallery never buffers, see its own
    // comment). Every section's applyFields is a no-op for keys it doesn't
    // own, so calling all three with the same full buffer is safe and
    // correctly restores whichever fields were actually pending, instead of
    // only ever restoring Overview's three fields.
    function applyRestoredFields(fields) {
        overview.applyFields(fields);
        specifications.applyFields(fields);
        resources.applyFields(fields);
    }

    maybeShowRecoveryBanner(draft, autosave, applyRestoredFields);

    // Best-effort only, per the recovery architecture: the local buffer
    // (already written synchronously at scheduleSave time) is the actual
    // safety net, not this. No preventDefault/returnValue — never block or
    // delay navigation, and never imply to the user via the browser's
    // native dialog that their changes "might not be saved," since the
    // buffer already has them regardless of whether this flush completes.
    window.addEventListener("beforeunload", () => {
        if (!autosave.hasPendingChanges()) return;

        autosave.flushNow();
    });
}
