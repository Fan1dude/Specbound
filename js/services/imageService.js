import { supabase } from "../core/supabase.js";

const AVATAR_SIZES = [500, 200, 64, 32];
const AVATAR_BASE_SIZE = 500;
const AVATAR_CANONICAL_SIZE = 500;
const ALLOWED_MIME_TYPES = ["image/jpeg", "image/png", "image/webp"];
const MAX_SOURCE_BYTES = 8 * 1024 * 1024;
const PROJECT_IMAGES_BUCKET = "project-images";

const GALLERY_MAX_DIMENSION = 2000;

// 7 days — matches js/repositories/mediaRepository.js's SIGNED_URL_EXPIRY_SECONDS.
// project-images is a private bucket going forward; a signed URL is the
// only way to get a fetchable link out of it. See
// supabase/migrations/0002_publish_draft_and_visibility.sql for the RLS
// policy that lets any visitor sign a URL for an avatars/* path.
const SIGNED_URL_EXPIRY_SECONDS = 60 * 60 * 24 * 7;

// Full avatar pipeline: validate + resize the source file into every size
// variant, upload each to Storage at a path keyed by user id and size (so a
// re-upload overwrites in place — no orphaned files), and return the
// storage path of the canonical 500px variant for storing on the profile.
// Returns a path, not a ready URL — project-images is a private bucket, so
// callers resolve it to a signed URL at render time (see
// mediaRepository.getMediaSignedUrl), the same pattern gallery/build media
// use. Storing a signed URL directly would expire and silently break the
// avatar days later.
// This is the only function page scripts should call for avatar uploads —
// nothing outside this file should touch canvas/Image APIs or call
// supabase.storage directly for avatars.
export async function uploadAvatar(userId, file) {
    const variants = await buildAvatarVariants(file);

    for (const [size, blob] of Object.entries(variants)) {
        const path = avatarStoragePath(userId, size);

        const { error: uploadError } = await supabase
            .storage
            .from(PROJECT_IMAGES_BUCKET)
            .upload(path, blob, {
                contentType: "image/jpeg",
                upsert: true
            });

        if (uploadError) throw uploadError;
    }

    return avatarStoragePath(userId, AVATAR_CANONICAL_SIZE);
}

function avatarStoragePath(userId, size) {
    return `avatars/${userId}/${size}.jpg`;
}

async function buildAvatarVariants(file) {
    if (!ALLOWED_MIME_TYPES.includes(file.type)) {
        throw new Error("Avatars must be a JPEG, PNG, or WebP image.");
    }

    if (file.size > MAX_SOURCE_BYTES) {
        throw new Error("Avatar image must be smaller than 8 MB.");
    }

    const image = await loadImage(file);

    if (image.naturalWidth < AVATAR_BASE_SIZE || image.naturalHeight < AVATAR_BASE_SIZE) {
        throw new Error(
            `Avatar image must be at least ${AVATAR_BASE_SIZE}×${AVATAR_BASE_SIZE} pixels.`
        );
    }

    const cropSize = Math.min(image.naturalWidth, image.naturalHeight);
    const cropX = (image.naturalWidth - cropSize) / 2;
    const cropY = (image.naturalHeight - cropSize) / 2;

    const variants = {};

    for (const size of AVATAR_SIZES) {
        const canvas = document.createElement("canvas");
        canvas.width = size;
        canvas.height = size;

        const context = canvas.getContext("2d");
        context.drawImage(
            image,
            cropX,
            cropY,
            cropSize,
            cropSize,
            0,
            0,
            size,
            size
        );

        variants[size] = await new Promise((resolve, reject) => {
            canvas.toBlob(
                blob => blob ? resolve(blob) : reject(new Error("Could not process avatar image.")),
                "image/jpeg",
                0.9
            );
        });
    }

    return variants;
}

// Gallery pipeline: validate, constrain to a max dimension while preserving
// the original aspect ratio (unlike avatars, gallery images are not
// cropped to square — lightboxes need the real proportions), and upload to
// Storage at a path keyed by draft id and a caller-supplied media id. Does
// not touch the database — callers persist the storage path via
// mediaRepository separately, since a media record needs its id decided
// before the upload path can be built.
export async function uploadGalleryImage(draftId, mediaId, file) {
    const blob = await buildGalleryImage(file);
    const path = galleryStoragePath(draftId, mediaId);

    const { error: uploadError } = await supabase
        .storage
        .from(PROJECT_IMAGES_BUCKET)
        .upload(path, blob, {
            contentType: "image/jpeg",
            upsert: true
        });

    if (uploadError) throw uploadError;
}

export function galleryStoragePath(draftId, mediaId) {
    return `projects/${draftId}/${mediaId}.jpg`;
}

// Rollback counterpart to uploadGalleryImage: removes the Storage object at
// the same path a given (draftId, mediaId) pair would have uploaded to.
// Callers use this when the upload itself succeeded but a subsequent step
// (the project_media insert) failed, so the file isn't left orphaned in
// Storage with no database row ever pointing back to it.
export async function deleteGalleryImage(draftId, mediaId) {
    const { error } = await supabase
        .storage
        .from(PROJECT_IMAGES_BUCKET)
        .remove([galleryStoragePath(draftId, mediaId)]);

    if (error) throw error;
}

async function buildGalleryImage(file) {
    if (!ALLOWED_MIME_TYPES.includes(file.type)) {
        throw new Error("Images must be JPEG, PNG, or WebP.");
    }

    if (file.size > MAX_SOURCE_BYTES) {
        throw new Error("Image must be smaller than 8 MB.");
    }

    const image = await loadImage(file);

    const scale = Math.min(
        1,
        GALLERY_MAX_DIMENSION / Math.max(image.naturalWidth, image.naturalHeight)
    );

    const width = Math.round(image.naturalWidth * scale);
    const height = Math.round(image.naturalHeight * scale);

    const canvas = document.createElement("canvas");
    canvas.width = width;
    canvas.height = height;

    canvas.getContext("2d").drawImage(image, 0, 0, width, height);

    return new Promise((resolve, reject) => {
        canvas.toBlob(
            blob => blob ? resolve(blob) : reject(new Error("Could not process image.")),
            "image/jpeg",
            0.9
        );
    });
}

function loadImage(file) {
    return new Promise((resolve, reject) => {
        const url = URL.createObjectURL(file);
        const image = new Image();

        image.onload = () => {
            URL.revokeObjectURL(url);
            resolve(image);
        };

        image.onerror = () => {
            URL.revokeObjectURL(url);
            reject(new Error("That file could not be read as an image."));
        };

        image.src = url;
    });
}
