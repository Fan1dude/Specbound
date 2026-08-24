import { isValidStatus, normalizeProgress } from "../../services/draftValidation.js";

export function renderOverviewSection(draft, autosave) {
    const titleField = document.getElementById("fieldTitle");
    const descriptionField = document.getElementById("fieldDescription");
    const categoryField = document.getElementById("fieldCategory");
    const statusField = document.getElementById("fieldStatus");
    const progressField = document.getElementById("fieldProgress");
    const progressValue = document.getElementById("fieldProgressValue");
    const announcement = document.getElementById("lifecycleAnnouncement");
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
        category: draft.category || "",
        status: draft.status || "planning",
        progress: normalizeProgress(draft.progress) ?? 0
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

    // Product decision: status = 'completed' requires progress = 100,
    // enforced two ways — selecting Completed here forces progress to
    // 100 (this listener), and dragging progress below 100 while
    // Completed forces status back to 'in_progress' (the progress
    // listener below). Every OTHER status change (including reopening a
    // Completed build by picking In Progress or Paused) leaves progress
    // completely untouched — the database's own
    // builds_status_progress_check / project_drafts_status_progress_check
    // constraints (0042) are the real, unconditional gate; this is the
    // matching client-side behavior, not a substitute for it.
    statusField.addEventListener("change", () => {
        const value = statusField.value;

        if (!isValidStatus(value) || value === lastKnownValues.status) return;

        lastKnownValues.status = value;

        if (value === "completed" && lastKnownValues.progress !== 100) {
            lastKnownValues.progress = 100;
            setProgressDisplay(100);
            autosave.scheduleSave({ status: value, progress: 100 });
            announce("Progress set to 100% because status was changed to Completed.");
            return;
        }

        autosave.scheduleSave({ status: value });
    });

    progressField.addEventListener("input", () => {
        // Runs on every tick while dragging, unconditionally, so the
        // visible number tracks the thumb in real time — the dedup/save
        // logic below is what's actually debounced (via the existing
        // autosave controller), not this readout.
        const rawValue = normalizeProgress(progressField.value) ?? 0;
        updateProgressReadout(rawValue);

        if (rawValue === lastKnownValues.progress) return;

        const wasCompleted = lastKnownValues.status === "completed";
        lastKnownValues.progress = rawValue;

        if (wasCompleted && rawValue < 100) {
            lastKnownValues.status = "in_progress";
            statusField.value = "in_progress";
            autosave.scheduleSave({ progress: rawValue, status: "in_progress" });
            announce("Status changed to In Progress because progress is below 100%.");
            return;
        }

        autosave.scheduleSave({ progress: rawValue });
    });

    function setProgressDisplay(value) {
        progressField.value = value;
        updateProgressReadout(value);
    }

    function updateProgressReadout(value) {
        progressValue.textContent = `${value}%`;
    }

    // A dedicated, visually-hidden live region — not the visible readout
    // itself — so a screen reader announces exactly these two automatic
    // adjustments once each, without narrating every tick of a drag (the
    // readout updates far too often for that) and without moving focus.
    function announce(message) {
        if (announcement) announcement.textContent = message;
    }

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

        // Used both for the initial, server-trusted bootstrap (always
        // valid — project_drafts' own CHECK constraints guarantee that)
        // and for crash-recovery restoration from localStorage, which
        // isn't trusted the same way — a corrupted or stale buffer value
        // is silently left as whatever's already showing rather than
        // applied, matching "invalid recovered values must not be
        // applied." Never calls scheduleSave itself — this only sets DOM
        // state, so bootstrapping/restoring a draft can never trigger a
        // phantom autosave on its own.
        if (fields.status !== undefined && isValidStatus(fields.status)) {
            statusField.value = fields.status;
            lastKnownValues.status = fields.status;
        }

        if (fields.progress !== undefined) {
            const value = normalizeProgress(fields.progress);

            if (value !== null) {
                setProgressDisplay(value);
                lastKnownValues.progress = value;
            }
        }
    }

    return { applyFields };
}
