import { getTechnology, getTechnologySpecifications } from "../../config/technologies/index.js";
import { setupComponentAutocomplete } from "../../components/ComponentAutocomplete.js";
import { openImportSpecificationsModal } from "../../components/ImportSpecificationsModal.js";
import { submitComponent } from "../../repositories/componentRepository.js";
import { escapeHtml, escapeAttribute } from "../../utils/escapeHtml.js";
import { icon } from "../../utils/icons.js";
import { normalizeSpecEntry, getSpecDisplayName } from "../../utils/specifications.js";
import { showToast } from "../../core/toast.js";

export function renderSpecificationsSection(draft, autosave) {
    const container = document.getElementById("specificationsFields");
    const categoryField = document.getElementById("fieldCategory");
    const importButton = document.getElementById("importSpecificationsBtn");

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

    importButton?.addEventListener("click", () => {
        const fields = getTechnologySpecifications(currentTechnologyId);

        if (!fields.length) return;

        openImportSpecificationsModal({
            technologyId: currentTechnologyId,
            fields,
            onImport: applyImportedValues
        });
    });

    function render(technologyId) {
        currentTechnologyId = technologyId;

        activeAutocompleteInstances.forEach(instance => instance.destroy());
        activeAutocompleteInstances = [];

        const technology = getTechnology(technologyId);
        const fields = getTechnologySpecifications(technologyId);

        if (importButton) importButton.hidden = !technology || !fields.length;

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
                            value="${escapeAttribute(getSpecDisplayName(currentSpecifications[field.key]))}"
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

            // Free typing always clears componentId — the value on screen
            // no longer necessarily matches the catalog entry it may have
            // come from. A subsequent catalog selection (via onSelect
            // below) is what re-attaches a componentId.
            input.addEventListener("input", () => {
                setValue(field.key, { name: input.value, componentId: null });
            });

            activeAutocompleteInstances.push(
                setupComponentAutocomplete({
                    input,
                    technologyId,
                    componentType: field.key,
                    onSelect: component => {
                        setValue(field.key, {
                            name: component.canonical_name,
                            componentId: component.id
                        });
                    },
                    // No catalog match — offer to submit it for moderator
                    // review (public.component_submissions) rather than
                    // creating a catalog row directly; ordinary users can
                    // no longer insert into public.components (see
                    // 0020_components_catalog.sql). The typed value is
                    // already saved as free text via the input listener
                    // above regardless of whether this submission happens
                    // or is ever approved.
                    onSubmitNew: async submittedName => {
                        try {
                            await submitComponent({
                                technologyId,
                                fieldKey: field.key,
                                submittedName
                            });

                            showToast("Submitted for catalog review. Your entry is already saved on this build.", "success");
                        } catch (error) {
                            showToast(error.message || "Could not submit this component for review.", "error");
                            throw error;
                        }
                    }
                })
            );
        });
    }

    // Single write path for both free typing and catalog selection, so
    // every save always writes the structured {componentId, name} shape
    // (see js/utils/specifications.js) regardless of which one produced
    // the change.
    function setValue(fieldKey, { name, componentId = null }) {
        const trimmedName = name.trim();
        const lastEntry = normalizeSpecEntry(lastKnownValues[fieldKey]);

        if (trimmedName === lastEntry.name && componentId === lastEntry.componentId) return;

        const nextEntry = { componentId, name: trimmedName };

        lastKnownValues[fieldKey] = nextEntry;
        currentSpecifications = { ...currentSpecifications, [fieldKey]: nextEntry };

        autosave.scheduleSave({ specifications: { ...currentSpecifications } });
    }

    // Callback for openImportSpecificationsModal — routes every imported
    // value through the same setValue() write path free typing and
    // catalog selection use, then syncs the now-stale visible inputs
    // (setValue only updates state + schedules a save, it doesn't touch
    // the DOM, since its other two callers already have the input in sync
    // by construction).
    function applyImportedValues(fieldValues) {
        Object.entries(fieldValues).forEach(([fieldKey, entry]) => {
            setValue(fieldKey, entry);

            const input = document.getElementById(`spec-${fieldKey}`);
            if (input) input.value = entry.name;
        });
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

