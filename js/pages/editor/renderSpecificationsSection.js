import { getTechnology, getTechnologySpecifications } from "../../config/technologies/index.js";
import { setupComponentAutocomplete } from "../../components/ComponentAutocomplete.js";
import { escapeHtml, escapeAttribute } from "../../utils/escapeHtml.js";
import { icon } from "../../utils/icons.js";

export function renderSpecificationsSection(draft, autosave) {
    const container = document.getElementById("specificationsFields");
    const categoryField = document.getElementById("fieldCategory");

    // Specifications live in one jsonb column, so every save must send the
    // complete object, not just the field that changed — autosave's field
    // merge is shallow, and Supabase's update() replaces the whole column.
    // Kept across re-renders (technology switches) so values for a
    // technology the user switched away from aren't discarded, just no
    // longer displayed.
    let currentSpecifications = { ...(draft.specifications || {}) };
    let lastKnownValues = { ...currentSpecifications };
    let currentTechnologyId = draft.category;

    // Component autocomplete instances from the previous render — must be
    // destroyed before creating new ones, or each technology switch back to
    // pc_build leaks another document-level click listener.
    let activeAutocompleteInstances = [];

    render(draft.category);

    // Specifications are technology-specific, so re-render whenever the
    // technology changes in Overview — regardless of which tab is visible
    // when that happens.
    categoryField.addEventListener("change", () => {
        render(categoryField.value);
    });

    function render(technologyId) {
        currentTechnologyId = technologyId;

        activeAutocompleteInstances.forEach(instance => instance.destroy());
        activeAutocompleteInstances = [];

        const technology = getTechnology(technologyId);
        const fields = getTechnologySpecifications(technologyId);

        if (!technology || !fields.length) {
            container.innerHTML = `
                <div class="empty-state compact-empty-state">
                    <div class="empty-state-icon">${icon("document", 32)}</div>
                    <h3>No specification fields for this technology yet.</h3>
                    <p>Choose a technology in Overview to see its fields here.</p>
                </div>
            `;
            return;
        }

        container.innerHTML = `
            <div class="technology-form-heading">
                <p class="technology-form-accent">
                    ${escapeHtml(technology.title)}
                </p>

                <p>Add the specifications that define this project.</p>
            </div>

            <div class="dynamic-field-grid">
                ${fields.map(field => `
                    <div class="dynamic-field">
                        <label for="spec-${escapeAttribute(field.key)}">
                            ${escapeHtml(field.label)}
                        </label>

                        <input
                            id="spec-${escapeAttribute(field.key)}"
                            type="text"
                            placeholder="Enter ${escapeAttribute(field.label)}"
                            value="${escapeAttribute(currentSpecifications[field.key] || "")}"
                            autocomplete="off"
                        >
                    </div>
                `).join("")}
            </div>
        `;

        // CSP compatibility: was an inline style="--technology-accent:..."
        // attribute — a strict style-src with no 'unsafe-inline' silently
        // blocks that (confirmed live during Milestone 10 implementation).
        // CSSOM property assignment isn't restricted the same way.
        container.querySelector(".technology-form-accent")
            ?.style.setProperty("--technology-accent", technology.accent);

        fields.forEach(field => {
            const input = document.getElementById(`spec-${field.key}`);

            input.addEventListener("input", () => {
                const value = input.value.trim();

                if (value === (lastKnownValues[field.key] || "")) return;

                lastKnownValues[field.key] = value;
                currentSpecifications = { ...currentSpecifications, [field.key]: value };

                autosave.scheduleSave({ specifications: { ...currentSpecifications } });
            });
        });

        if (technologyId === "pc_build") {
            activeAutocompleteInstances.push(
                setupComponentAutocomplete({
                    input: "#spec-cpu",
                    technologyId: "pc_build",
                    componentType: "cpu"
                }),
                setupComponentAutocomplete({
                    input: "#spec-gpu",
                    technologyId: "pc_build",
                    componentType: "gpu"
                })
            );
        }
    }

    // Used by the recovery banner's Restore action. A buffered save may
    // contain fields this section doesn't own (title, resources, ...) — a
    // no-op here is correct for those, since each section's applyFields
    // only reacts to its own key(s).
    function applyFields(fields) {
        if (fields.specifications === undefined) return;

        currentSpecifications = { ...fields.specifications };
        lastKnownValues = { ...currentSpecifications };

        render(currentTechnologyId);
    }

    return { applyFields };
}

