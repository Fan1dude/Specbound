export function renderOverviewSection(draft, autosave) {
    const titleField = document.getElementById("fieldTitle");
    const descriptionField = document.getElementById("fieldDescription");
    const categoryField = document.getElementById("fieldCategory");
    const editorTitle = document.getElementById("editorTitle");

    // Tracks the last value we know the server (or a just-applied restore)
    // actually has for each field. Browsers can fire a real "input" event
    // on their own — e.g. Chrome restoring a <textarea>'s value on page
    // reload — with no user interaction at all. Comparing against the last
    // known value before scheduling a save means a phantom event that
    // reports the same value we already have is a no-op, regardless of
    // what triggered it, rather than us guessing at browser-specific causes.
    const lastKnownValues = {
        title: draft.title || "",
        description: draft.description || "",
        category: draft.category || ""
    };

    applyFields(lastKnownValues);

    titleField.addEventListener("input", () => {
        const value = titleField.value.trim();
        editorTitle.textContent = value || "Untitled project";

        if (value === lastKnownValues.title) return;

        lastKnownValues.title = value;
        autosave.scheduleSave({ title: value });
    });

    descriptionField.addEventListener("input", () => {
        const value = descriptionField.value.trim();

        if (value === lastKnownValues.description) return;

        lastKnownValues.description = value;
        autosave.scheduleSave({ description: value });
    });

    categoryField.addEventListener("change", () => {
        const value = categoryField.value;

        if (value === lastKnownValues.category) return;

        lastKnownValues.category = value;
        autosave.scheduleSave({ category: value });
    });

    function applyFields(fields) {
        if (fields.title !== undefined) {
            titleField.value = fields.title || "";
            editorTitle.textContent = fields.title?.trim() || "Untitled project";
            lastKnownValues.title = fields.title || "";
        }

        if (fields.description !== undefined) {
            descriptionField.value = fields.description || "";
            lastKnownValues.description = fields.description || "";
        }

        if (fields.category !== undefined) {
            categoryField.value = fields.category || "";
            lastKnownValues.category = fields.category || "";
        }
    }

    return { applyFields };
}
