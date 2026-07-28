import { escapeAttribute } from "../../utils/escapeHtml.js";
import { icon } from "../../utils/icons.js";

export function renderResourcesSection(draft, autosave) {
    const container = document.getElementById("resourcesList");
    const addButton = document.getElementById("addResourceBtn");

    // Same rule as specifications: resources is one jsonb array column, so
    // every save sends the complete array, never just the changed row.
    let currentResources = Array.isArray(draft.resources) ? [...draft.resources] : [];

    render();

    addButton.addEventListener("click", () => {
        currentResources = [...currentResources, { label: "", url: "" }];
        render();
        // Nothing has actually been typed yet — don't save an empty row.
    });

    function render() {
        if (!currentResources.length) {
            container.innerHTML = `
                <div class="empty-state compact-empty-state">
                    <div class="empty-state-icon">${icon("document", 32)}</div>
                    <h3>No resources yet.</h3>
                    <p>Add links to datasheets, references, or anything else worth pointing to.</p>
                </div>
            `;
            return;
        }

        container.innerHTML = currentResources
            .map((resource, index) => `
                <div class="resource-row" data-index="${index}">
                    <input
                        type="text"
                        class="resource-label-input"
                        placeholder="Label (e.g. Datasheet)"
                        value="${escapeAttribute(resource.label || "")}"
                        autocomplete="off"
                        aria-label="Resource ${index + 1} label"
                    >

                    <input
                        type="url"
                        class="resource-url-input"
                        placeholder="https://..."
                        value="${escapeAttribute(resource.url || "")}"
                        autocomplete="off"
                        aria-label="Resource ${index + 1} URL"
                    >

                    <button
                        type="button"
                        class="btn btn-ghost btn-small resource-remove-btn"
                        aria-label="Remove this resource"
                    >
                        Remove
                    </button>
                </div>
            `)
            .join("");

        container.querySelectorAll(".resource-row").forEach(row => {
            const index = Number(row.dataset.index);
            const labelInput = row.querySelector(".resource-label-input");
            const urlInput = row.querySelector(".resource-url-input");
            const removeBtn = row.querySelector(".resource-remove-btn");

            labelInput.addEventListener("input", () => {
                if (labelInput.value === currentResources[index].label) return;

                currentResources[index] = { ...currentResources[index], label: labelInput.value };
                save();
            });

            urlInput.addEventListener("input", () => {
                if (urlInput.value === currentResources[index].url) return;

                currentResources[index] = { ...currentResources[index], url: urlInput.value };
                save();
            });

            removeBtn.addEventListener("click", () => {
                currentResources = currentResources.filter((_, i) => i !== index);
                render();
                save();
            });
        });
    }

    function save() {
        autosave.scheduleSave({ resources: [...currentResources] });
    }

    // Used by the recovery banner's Restore action — see the matching note
    // in renderSpecificationsSection.js.
    function applyFields(fields) {
        if (fields.resources === undefined) return;

        currentResources = Array.isArray(fields.resources) ? [...fields.resources] : [];
        render();
    }

    return { applyFields };
}

