import { getReadinessChecks, isDraftReady } from "../../services/draftValidation.js";
import { escapeHtml } from "../../utils/escapeHtml.js";
import { icon } from "../../utils/icons.js";

// Previews what publish_draft() will actually require server-side (see
// supabase/migrations/0002_publish_draft_and_visibility.sql) — this is a UX
// convenience, not the real gate, but it drives the Publish button's
// enabled state so users aren't sent to the server just to be rejected.
// getMediaCount is a callback rather than a fetched value so this can be
// re-checked cheaply without a duplicate network call each time a Gallery
// action happens (renderGallerySection already holds the media list in
// memory).
export function renderReadinessChecklist(getMediaCount, onReadyChange = () => {}) {
    const container = document.getElementById("editorReadiness");

    if (!container) return { update() {} };

    function update() {
        const checks = getReadinessChecks({
            title: document.getElementById("fieldTitle")?.value,
            description: document.getElementById("fieldDescription")?.value,
            category: document.getElementById("fieldCategory")?.value,
            hasCoverImage: getMediaCount() > 0
        });

        const completeCount = checks.filter(check => check.passed).length;

        container.setAttribute(
            "aria-label",
            `Ready to publish checklist: ${completeCount} of ${checks.length} complete`
        );

        container.innerHTML = checks
            .map(check => `
                <span class="readiness-check${check.passed ? " is-complete" : ""}">
                    <span aria-hidden="true">${icon(check.passed ? "check" : "circle", 16)}</span>
                    ${escapeHtml(check.label)}
                </span>
            `)
            .join("");

        onReadyChange(isDraftReady(checks));
    }

    update();

    return { update };
}

