import { getDraftMedia, addMedia, deleteMedia, getMediaSignedUrl } from "../../repositories/mediaRepository.js";
import { updateDraft } from "../../repositories/draftRepository.js";
import { uploadGalleryImage, deleteGalleryImage } from "../../services/imageService.js";
import { showToast } from "../../core/toast.js";
import { escapeAttribute } from "../../utils/escapeHtml.js";

// Gallery is intentionally not part of the shared text-field autosave
// pipeline. Uploads, deletes, and cover selection are discrete, atomic
// actions — each one either succeeds or it doesn't, right away — not
// continuous typing that benefits from debouncing or a local-recovery
// buffer. Each action gets its own immediate toast instead.
export async function renderGallerySection(draft, onMediaChange = () => {}) {
    const grid = document.getElementById("galleryGrid");
    const fileInput = document.getElementById("galleryFileInput");
    const statusText = document.getElementById("galleryUploadStatus");
    const uploadZone = fileInput.closest(".upload-zone");

    let mediaItems = [];
    let coverMediaId = draft.cover_media_id || null;
    let loadFailed = false;

    grid.innerHTML = `<p class="text-secondary">Loading gallery...</p>`;

    try {
        mediaItems = await getDraftMedia(draft.id);
    } catch (error) {
        console.error("Gallery load error:", error);
        loadFailed = true;
    }

    // render()'s empty-gallery path unconditionally clears the grid, which
    // previously ran right after this and wiped out the load-failure
    // message set two lines above before anyone could read it. Skipping
    // render() entirely on failure keeps the error message on screen.
    if (loadFailed) {
        grid.innerHTML = `<p class="text-secondary">Could not load gallery images. Try refreshing the page.</p>`;
    } else {
        await render();
    }

    onMediaChange(mediaItems.length);

    fileInput.addEventListener("change", async () => {
        const files = Array.from(fileInput.files || []);
        if (!files.length) return;

        fileInput.disabled = true;
        uploadZone.classList.add("is-dragging");
        statusText.textContent = `Uploading ${files.length} image${files.length > 1 ? "s" : ""}...`;

        for (const file of files) {
            const mediaId = crypto.randomUUID();
            let uploadedToStorage = false;

            try {
                await uploadGalleryImage(draft.id, mediaId, file);
                uploadedToStorage = true;

                const media = await addMedia({
                    id: mediaId,
                    draftId: draft.id,
                    storagePath: `projects/${draft.id}/${mediaId}.jpg`,
                    displayOrder: mediaItems.length
                });

                mediaItems = [...mediaItems, media];

                // First image uploaded becomes the cover automatically. A
                // failure here doesn't mean the upload failed — the image
                // and its record both exist — so it's handled and reported
                // separately rather than falling into the catch below and
                // being misreported as "could not upload image."
                if (!coverMediaId) {
                    try {
                        await updateDraft(draft.id, { cover_media_id: media.id });
                        coverMediaId = media.id;
                    } catch (coverError) {
                        console.error("Auto-cover assignment error:", coverError);
                        showToast(
                            "Image uploaded, but couldn't be set as the cover automatically. You can set it manually.",
                            "warning"
                        );
                    }
                }
            } catch (error) {
                console.error("Gallery upload error:", error);

                if (uploadedToStorage) {
                    // The file reached Storage but the project_media insert
                    // failed — remove it rather than leaving an orphaned
                    // object with no database row ever pointing back to it.
                    try {
                        await deleteGalleryImage(draft.id, mediaId);
                    } catch (cleanupError) {
                        console.error("Orphaned upload cleanup failed:", cleanupError);
                        showToast(
                            "Upload failed, and the partial file could not be automatically cleaned up.",
                            "error"
                        );
                        continue;
                    }
                }

                showToast(error.message || "Could not upload image.", "error");
            }
        }

        fileInput.disabled = false;
        fileInput.value = "";
        uploadZone.classList.remove("is-dragging");
        statusText.textContent = "JPEG, PNG, or WebP. You can select multiple files.";

        await render();
        onMediaChange(mediaItems.length);
    });

    async function render() {
        if (!mediaItems.length) {
            grid.innerHTML = "";
            return;
        }

        // Resolve every image's signed URL before building any markup —
        // project-images is a private bucket, so there's no ready URL to
        // read straight off the media row the way there used to be.
        const signedUrls = await Promise.all(
            mediaItems.map(media => getMediaSignedUrl(media.storage_path).catch(() => ""))
        );

        grid.innerHTML = mediaItems.map((media, index) => `
            <figure class="gallery-item${media.id === coverMediaId ? " is-cover" : ""}" data-id="${media.id}">
                <img
                    src="${escapeAttribute(signedUrls[index])}"
                    alt="${escapeAttribute(media.alt_text || "Project image")}"
                    loading="lazy"
                >

                <figcaption class="gallery-item-actions">
                    <button
                        type="button"
                        class="btn btn-ghost btn-small gallery-cover-btn"
                        ${media.id === coverMediaId ? "disabled" : ""}
                    >
                        ${media.id === coverMediaId ? "Cover" : "Set as Cover"}
                    </button>

                    <button
                        type="button"
                        class="btn btn-ghost btn-small gallery-delete-btn"
                        aria-label="Delete this image"
                    >
                        Delete
                    </button>
                </figcaption>
            </figure>
        `).join("");

        grid.querySelectorAll(".gallery-item").forEach(item => {
            const id = item.dataset.id;
            const media = mediaItems.find(m => m.id === id);

            item.querySelector(".gallery-cover-btn").addEventListener("click", async () => {
                try {
                    await updateDraft(draft.id, { cover_media_id: id });
                    coverMediaId = id;
                    await render();
                    showToast("Cover image updated.", "success");
                } catch (error) {
                    showToast(error.message || "Could not set cover image.", "error");
                }
            });

            item.querySelector(".gallery-delete-btn").addEventListener("click", async () => {
                if (!confirm("Delete this image?")) return;

                try {
                    await deleteMedia(media);
                    mediaItems = mediaItems.filter(m => m.id !== id);

                    if (coverMediaId === id) {
                        coverMediaId = mediaItems[0]?.id || null;
                        await updateDraft(draft.id, { cover_media_id: coverMediaId });
                    }

                    await render();
                    onMediaChange(mediaItems.length);
                    showToast("Image deleted.", "success");
                } catch (error) {
                    showToast(error.message || "Could not delete image.", "error");
                }
            });
        });
    }
}
