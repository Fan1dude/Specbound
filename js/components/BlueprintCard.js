import { escapeHtml, escapeAttribute } from "../utils/escapeHtml.js";
import { formatCategory } from "../utils/formatCategory.js";
import { icon } from "../utils/icons.js";

export function BlueprintCard(build, pathPrefix = "", options = {}) {
    const { variant = "default" } = options;
    const specs = build.specifications || {};
    const username =
        build.profiles?.username ||
        build.creator?.username ||
        "Unknown Creator";

    const profileId = build.user_id || build.profiles?.id;
    const progress = clampProgress(build.progress);
    const version = normalizeVersion(build.version);
    const stage = getStage(build.status);

    const buildUrl =
        `${pathPrefix}pages/build/build.html?slug=${encodeURIComponent(build.slug || "")}`;

    // build.draftId is attached by the caller (see renderWorkshop.js) from
    // a draft lookup it's already doing — not fetched here, to avoid an
    // extra query per card. continue.html's direct-write flow is retired
    // (Milestone 5A); "Continue Editing" now opens the linked draft in the
    // real editor. If no draft is linked (a real but unusual edge case —
    // nothing in the app deletes drafts, but nothing guarantees one
    // either), this falls back to the public project page instead of a
    // dead link.
    const hasLinkedDraft = Boolean(build.draftId);

    const continueUrl = hasLinkedDraft
        ? `${pathPrefix}pages/build/edit.html?draft=${encodeURIComponent(build.draftId)}`
        : buildUrl;

    const profileUrl = profileId
        ? `${pathPrefix}pages/profile.html?user=${encodeURIComponent(profileId)}`
        : null;

    const fallbackImage = new URL(
        `${pathPrefix}assets/placeholders/default-cover.svg`,
        document.baseURI
    ).href;

    const imageUrl = build.image_url || fallbackImage;
    const specificationItems = getSpecificationItems(build.category, specs);

    return `
        <article class="blueprint-card card">
            <a
                class="blueprint-card-image"
                href="${buildUrl}"
                aria-label="View ${escapeHtml(build.title || "Untitled Blueprint")}"
            >
                <img
                    src="${escapeAttribute(imageUrl)}"
                    alt="${escapeAttribute(build.title || "Blueprint cover")}"
                    loading="lazy"
                >

                <span class="blueprint-card-stage ${stage.className}">
                    ${stage.label}
                </span>
            </a>

            <div class="blueprint-card-body">
                <div class="blueprint-card-topline">
                    <span class="badge">
                        ${formatCategory(build.category)}
                    </span>

                    <span class="blueprint-card-version">
                        ${escapeHtml(version)}
                    </span>
                </div>

                <h3>
                    <a href="${buildUrl}">
                        ${escapeHtml(build.title || "Untitled Blueprint")}
                    </a>
                </h3>

                <p class="blueprint-card-creator">
                    By
                    ${
                        profileUrl
                            ? `
                                <a href="${profileUrl}">
                                    ${escapeHtml(username)}
                                </a>
                            `
                            : `<span>${escapeHtml(username)}</span>`
                    }
                </p>

                ${
                    specificationItems.length
                        ? `
                            <div class="blueprint-card-specs">
                                ${specificationItems
                                    .map(
                                        item => `
                                            <div class="blueprint-card-spec">
                                                <span>${escapeHtml(item.label)}</span>
                                                <strong>${escapeHtml(item.value)}</strong>
                                            </div>
                                        `
                                    )
                                    .join("")}
                            </div>
                        `
                        : `
                            <p class="blueprint-card-summary">
                                ${escapeHtml(
                                    build.description ||
                                    "No project summary has been added yet."
                                )}
                            </p>
                        `
                }

                <div class="blueprint-card-progress">
                    <div class="blueprint-card-progress-header">
                        <span>Progress</span>
                        <span>${progress}%</span>
                    </div>

                    <div
                        class="progress-track"
                        role="progressbar"
                        aria-label="Project progress"
                        aria-valuemin="0"
                        aria-valuemax="100"
                        aria-valuenow="${progress}"
                    >
                        <div
                            class="progress-fill"
                            data-progress="${progress}"
                        ></div>
                    </div>
                </div>

                <footer class="blueprint-card-footer">
                    <div class="blueprint-card-meta">
                        <span>${formatUpdatedDate(build.updated_at || build.created_at)}</span>
                        <span class="blueprint-card-views">${formatViewCount(build.views)} views</span>
                    </div>

                    ${
                        variant === "workspace"
                            ? `
                                <a href="${continueUrl}" class="blueprint-card-link">
                                    ${hasLinkedDraft ? "Continue Editing" : "View Blueprint"}
                                    ${icon("arrow-right", 16)}
                                </a>
                            `
                            : `
                                <a href="${buildUrl}" class="blueprint-card-link">
                                    View Blueprint
                                    ${icon("arrow-right", 16)}
                                </a>
                            `
                    }
                </footer>
            </div>
        </article>
    `;
}

function getSpecificationItems(category, specs) {
    const categoryFields = {
        pc_build: [
            ["CPU", specs.cpu],
            ["GPU", specs.gpu],
            ["Memory", specs.ram]
        ],
        setup: [
            ["Desk", specs.desk],
            ["Monitor", specs.monitor],
            ["Keyboard", specs.keyboard]
        ],
        arduino: [
            ["Board", specs.board],
            ["Sensor", specs.sensor],
            ["Display", specs.display]
        ],
        robotics: [
            ["Controller", specs.controller || specs.board],
            ["Motor", specs.motor],
            ["Power", specs.battery]
        ],
        "3d_printer": [
            ["Printer", specs.printer],
            ["Material", specs.filament],
            ["Nozzle", specs.nozzle]
        ],
        homelab: [
            ["Server", specs.server],
            ["CPU", specs.cpu],
            ["Storage", specs.storage]
        ]
    };

    return (categoryFields[category] || Object.entries(specs))
        .filter(([, value]) => value)
        .slice(0, 3)
        .map(([label, value]) => ({
            label,
            value: String(value)
        }));
}

function getStage(status) {
    switch (status) {
        case "planning":
            return {
                label: "Blueprint",
                className: "is-planning"
            };

        case "building":
        case "in_progress":
            return {
                label: "Project",
                className: "is-project"
            };

        case "completed":
            return {
                label: "Completed Build",
                className: "is-completed"
            };

        case "paused":
            return {
                label: "Paused",
                className: "is-paused"
            };

        default:
            return {
                label: "Blueprint",
                className: "is-planning"
            };
    }
}


function normalizeVersion(version) {
    if (!version) return "v1.0";

    const value = String(version);
    return value.toLowerCase().startsWith("v")
        ? value
        : `v${value}`;
}

function clampProgress(value) {
    const number = Number(value || 0);

    if (!Number.isFinite(number)) return 0;

    return Math.min(100, Math.max(0, Math.round(number)));
}

function formatViewCount(value) {
    const number = Number(value || 0);

    if (!Number.isFinite(number) || number < 0) return "0";

    return Math.floor(number).toLocaleString();
}

function formatUpdatedDate(value) {
    if (!value) return "Updated recently";

    const date = new Date(value);

    if (Number.isNaN(date.getTime())) {
        return "Updated recently";
    }

    return `Updated ${date.toLocaleDateString(undefined, {
        month: "short",
        day: "numeric",
        year: "numeric"
    })}`;
}

