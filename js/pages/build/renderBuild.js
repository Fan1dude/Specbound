import { resolveImageUrl } from "../../repositories/mediaRepository.js";
import { formatCategory } from "../../utils/formatCategory.js";
import { avatarInitial } from "../../utils/avatarInitial.js";

export async function renderBuild(build, latestRevision = null, { editDraftId = null } = {}) {
    const username =
        build.profiles?.username || "Specbound Member";

    const latestDate =
        latestRevision?.created_at ||
        build.updated_at ||
        build.created_at;

    const updatedDate = latestDate
        ? new Date(latestDate).toLocaleDateString()
        : "Recently";

    const progress = clampProgress(
        latestRevision?.progress
    );

    const version = normalizeVersion(
        latestRevision?.version
    );

    renderHero(build, username, updatedDate);
    renderCreator(build, username);
    await renderCoverImage(build);
    renderOverview(build, version, progress, updatedDate);
    renderActions(editDraftId);
}

// Renders build.html from a specific historical build_revisions row
// instead of the build's current/latest state — used when
// ?revision={id} is present (see loadBuild.js). Reuses the same
// formatCategory/formatStatus/setText helpers as the default view for
// consistent labels, but reads content from the revision snapshot
// (snapshot_title, snapshot_description, category, specifications,
// resources) and from revisionMedia (this revision's own immutable
// gallery) rather than from `build`/its current gallery.
//
// Revisions published before Milestone 5C never captured a content
// snapshot — snapshot_title is empty for every one of them (a real
// revision can never have an empty title, since publish_draft() requires
// at least 3 characters, so an empty value reliably means "not
// recorded," not "was recorded as blank"). Rather than silently falling
// back to the build's current data — which would misrepresent what that
// revision actually was — the affected sections show an explicit notice.
export async function renderRevisionView(build, revision, revisionMedia, { canRestore = false } = {}) {
    const username = build.profiles?.username || "Specbound Member";
    const hasSnapshot = Boolean(revision.snapshot_title);

    setText("buildTitle", hasSnapshot ? revision.snapshot_title : (build.title || "Untitled Blueprint"));
    setText("buildCategory", hasSnapshot ? formatCategory(revision.category) : "Not recorded for this revision");
    setText(
        "buildDescription",
        hasSnapshot
            ? (revision.snapshot_description || "No description was recorded for this revision.")
            : "This revision was published before per-revision snapshots were captured — the project's content at that point wasn't recorded."
    );
    setText("buildStatus", formatStatus(build.status));
    setText("buildUpdated", `Published ${new Date(revision.created_at).toLocaleDateString()}`);

    const builderLink = document.getElementById("buildBuilder");

    if (builderLink) {
        builderLink.textContent = `Built by ${username}`;
        builderLink.href = `../../pages/profile.html?user=${encodeURIComponent(build.user_id || "")}`;
    }

    renderCreator(build, username);

    const cover = revisionMedia.find(media => media.is_cover) || revisionMedia[0] || null;
    await renderCoverImageFromPath(cover?.storage_path, revision.snapshot_title || build.title);

    renderOverview(
        build,
        normalizeVersion(revision.version),
        clampProgress(revision.progress),
        new Date(revision.created_at).toLocaleDateString()
    );

    // A historical revision isn't the place to jump into the live editor —
    // that acts on the current/latest draft state, unrelated to what's
    // being viewed here. Swap it for a single, owner-only Restore action.
    hideElement("editBuildBtn");

    const restoreButton = document.getElementById("restoreRevisionBtn");
    const restoreHint = document.getElementById("restoreRevisionHint");

    if (restoreButton) {
        restoreButton.hidden = !canRestore;

        // Restoring copies snapshot_title/snapshot_description/category
        // straight into the draft (see restore_revision_to_draft() in
        // supabase/migrations/0005_revision_history_and_restore.sql) — for
        // a pre-5C revision those are empty strings, so restoring one
        // would silently blank out the draft's title/description rather
        // than actually restoring anything. Disabled with a visible
        // explanation instead of hidden outright, so it's clear this
        // revision simply predates snapshot capture rather than that
        // restore is broken. Not a title/tooltip attribute — disabled
        // buttons generally don't show those, so a sighted user with no
        // reason to open devtools would never see it.
        const missingSnapshot = canRestore && !hasSnapshot;

        restoreButton.disabled = missingSnapshot;

        if (restoreHint) {
            restoreHint.hidden = !missingSnapshot;
        }
    }

    const banner = document.getElementById("revisionBanner");

    if (banner) {
        banner.hidden = false;
        setText("revisionBannerVersion", normalizeVersion(revision.version));

        const latestLink = document.getElementById("revisionBannerLatestLink");

        if (latestLink) {
            latestLink.href = `build.html?slug=${encodeURIComponent(build.slug || "")}`;
        }
    }

    return {
        specifications: hasSnapshot ? revision.specifications : null,
        resources: hasSnapshot ? revision.resources : null,
        hasSnapshot
    };
}

function hideElement(id) {
    const element = document.getElementById(id);

    if (element) element.hidden = true;
}

async function renderCoverImageFromPath(storagePath, altSource) {
    const image = document.getElementById("buildImage");

    if (!image) return;

    const url = await resolveImageUrl(storagePath);

    if (url) {
        image.src = url;
        image.alt = `${altSource || "Blueprint"} cover image`;
    } else {
        image.src = "../../assets/placeholders/default-cover.svg";
        image.alt = "Default Blueprint cover";
    }

    image.style.display = "block";
}

function renderHero(build, username, updatedDate) {
    setText(
        "buildTitle",
        build.title || "Untitled Blueprint"
    );

    setText(
        "buildCategory",
        formatCategory(build.category)
    );

    setText(
        "buildDescription",
        build.description ||
            "No description has been added yet."
    );

    setText(
        "buildStatus",
        formatStatus(build.status)
    );

    setText(
        "buildUpdated",
        `Updated ${updatedDate}`
    );

    const builderLink =
        document.getElementById("buildBuilder");

    if (builderLink) {
        builderLink.textContent = `Built by ${username}`;
        builderLink.href =
            `../../pages/profile.html?user=${encodeURIComponent(
                build.user_id || ""
            )}`;
    }
}

function renderCreator(build, username) {
    setText("creatorName", username);

    const profileUrl =
        `../../pages/profile.html?user=${encodeURIComponent(
            build.user_id || ""
        )}`;

    // Two links to the same profile in this sidebar (the name itself, and
    // the separate "View Profile" button) — previously only the button
    // worked, the name was plain text. Milestone 6C: usernames should
    // consistently navigate to the profile wherever they're shown, and
    // this was the one place on a project page that didn't.
    const creatorNameLink =
        document.getElementById("creatorName");

    if (creatorNameLink) {
        creatorNameLink.href = profileUrl;
    }

    const creatorProfileLink =
        document.getElementById("creatorProfileLink");

    if (creatorProfileLink) {
        creatorProfileLink.href = profileUrl;
    }

    const creatorAvatar =
        document.querySelector(".creator-avatar");

    if (creatorAvatar) {
        creatorAvatar.textContent =
            avatarInitial(username);
    }
}

async function renderCoverImage(build) {
    const image =
        document.getElementById("buildImage");

    if (!image) return;

    const url = await resolveImageUrl(build.image_url);

    if (url) {
        image.src = url;
        image.alt =
            `${build.title || "Blueprint"} cover image`;
    } else {
        image.src =
            "../../assets/placeholders/default-cover.svg";
        image.alt = "Default Blueprint cover";
    }

    image.style.display = "block";
}

function renderOverview(
    build,
    version,
    progress,
    updatedDate
) {
    setText(
        "overviewStatus",
        formatStatus(build.status)
    );

    setText(
        "overviewVersion",
        version
    );

    setText(
        "overviewProgress",
        `${progress}%`
    );

    setText(
        "overviewUpdated",
        updatedDate
    );

    setText(
        "overviewViews",
        formatViews(build.views)
    );

    const progressBar =
        document.querySelector(
            "[data-overview-progress]"
        );

    if (progressBar) {
        progressBar.style.setProperty(
            "--progress",
            `${progress}%`
        );

        progressBar.setAttribute(
            "aria-valuenow",
            String(progress)
        );
    }
}

// editDraftId is only ever populated by loadBuild.js for the build's own
// owner (see the ownership check there) — everyone else, and the case
// where no draft is currently linked to this build, gets no edit action
// at all, rather than the previous behavior of showing "Continue
// Building"/"Edit Blueprint" to every visitor regardless of ownership,
// pointing at pages that don't work for them (continue.html's write path
// is retired; pages/edit-build.html never existed).
function renderActions(editDraftId) {
    const editButton = document.getElementById("editBuildBtn");

    if (!editButton) return;

    if (editDraftId) {
        editButton.href = `edit.html?draft=${encodeURIComponent(editDraftId)}`;
        editButton.hidden = false;
    } else {
        editButton.hidden = true;
    }
}

function setText(id, value) {
    const element =
        document.getElementById(id);

    if (element) {
        element.textContent = value;
    }
}

function clampProgress(value) {
    const number = Number(value || 0);

    if (!Number.isFinite(number)) {
        return 0;
    }

    return Math.min(
        100,
        Math.max(0, Math.round(number))
    );
}

function formatViews(value) {
    const number = Number(value || 0);

    if (!Number.isFinite(number) || number < 0) {
        return "0";
    }

    return Math.floor(number).toLocaleString();
}

function normalizeVersion(version) {
    if (!version) {
        return "v0.1";
    }

    const value = String(version).trim();

    return value.toLowerCase().startsWith("v")
        ? value
        : `v${value}`;
}


function formatStatus(status) {
    switch (status) {
        case "planning":
            return "Blueprint";

        case "building":
        case "in_progress":
            return "Project";

        case "completed":
            return "Completed Build";

        case "paused":
            return "Paused";

        default:
            return "Blueprint";
    }
}