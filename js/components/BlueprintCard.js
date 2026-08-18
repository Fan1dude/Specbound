import { escapeHtml, escapeAttribute } from "../utils/escapeHtml.js";
import { formatCategory } from "../utils/formatCategory.js";
import { icon } from "../utils/icons.js";
import { getSpecDisplayName, isSpecEntryFilled } from "../utils/specifications.js";

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

    // V2 hardware line — plain inline text, not a bordered grid (see
    // css/components/blueprint-card.css's file header for the full
    // rationale). Built as one string with inline label spans rather
    // than a flex/grid layout of separate elements, so the whole line
    // can truncate with a single text-overflow: ellipsis on its parent
    // instead of needing wrapping/overflow logic of its own.
    const hardwareLine = specificationItems.length
        ? specificationItems
            .map(item => `<span class="blueprint-card-hw-label">${escapeHtml(item.label)}</span> ${escapeHtml(item.value)}`)
            .join(`<span class="blueprint-card-hw-sep">&middot;</span>`)
        : null;

    return `
        <article class="blueprint-card card">
            <a
                class="blueprint-card-image"
                href="${buildUrl}"
                aria-label="View ${escapeHtml(build.title || "Untitled Blueprint")} — ${escapeHtml(stage.label)}"
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

                <h3 class="blueprint-card-title">
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
                    hardwareLine
                        ? `
                            <p class="blueprint-card-hardware" title="${escapeAttribute(
                                specificationItems.map(item => `${item.label} ${item.value}`).join(" · ")
                            )}">
                                ${hardwareLine}
                            </p>
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
    // Every specs.X read stays a raw value here — display resolution
    // happens once, below, via getSpecDisplayName(), since a value may be
    // either the old plain-string shape or the new {componentId, name}
    // shape (see js/utils/specifications.js). specs.filament here matched
    // js/config/technologies/printing.js's field key was "material", so
    // this line never displayed anything — now reads the real key.
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
            // specs.controller may be a structured {componentId, name}
            // object even when "empty" — always truthy, so a plain ||
            // fallback would never reach specs.board. isSpecEntryFilled
            // checks the actual display name instead.
            ["Controller", isSpecEntryFilled(specs.controller) ? specs.controller : specs.board],
            ["Motor", specs.motor],
            ["Power", specs.battery]
        ],
        "3d_printer": [
            ["Printer", specs.printer],
            ["Material", specs.material],
            ["Nozzle", specs.nozzle]
        ],
        homelab: [
            ["Server", specs.server],
            ["CPU", specs.cpu],
            ["Storage", specs.storage]
        ]
    };

    return (categoryFields[category] || Object.entries(specs))
        .filter(([, value]) => isSpecEntryFilled(value))
        .slice(0, 3)
        .map(([label, value]) => ({
            label,
            value: getSpecDisplayName(value)
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

