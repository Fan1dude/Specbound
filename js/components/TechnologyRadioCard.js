import { escapeHtml, escapeAttribute } from "../utils/escapeHtml.js";
import { technologyPickerIconUrl } from "./technologyPickerShared.js";

// Replaces upload.html's old <select id="category" required> with a
// visual card grid while preserving its exact contract: value comes
// straight from TECHNOLOGIES[].id (the same strings the old hardcoded
// <option> list used), and native `required` on a radio group blocks
// submission the same way `<select required>` did — no new validation
// logic needed anywhere. The radio input itself is visually hidden via
// the existing .sr-only utility (clipped, not display:none — display:none
// would drop it from the accessibility tree and from constraint
// validation entirely), so it stays keyboard-focusable and screen readers
// announce a real "N of 6" radiogroup. The <label> wraps the whole visual
// card, so the entire card — not just the hidden input — is the click/tap
// target on both desktop and mobile.
export function TechnologyRadioCard(technology, { pathPrefix = "", checked = false } = {}) {
    const iconUrl = technologyPickerIconUrl(technology, pathPrefix);
    const inputId = `category-${technology.id}`;

    return `
        <label
            class="technology-picker-card"
            for="${escapeAttribute(inputId)}"
            data-category-accent="${escapeAttribute(technology.accent)}"
            data-category-icon="${escapeAttribute(iconUrl)}"
        >
            <input
                type="radio"
                name="category"
                id="${escapeAttribute(inputId)}"
                value="${escapeAttribute(technology.id)}"
                class="sr-only"
                required
                ${checked ? "checked" : ""}
            >
            <span class="technology-picker-icon" aria-hidden="true">
                <span class="technology-picker-symbol"></span>
            </span>
            <span class="technology-picker-body">
                <strong>${escapeHtml(technology.title)}</strong>
                <span>${escapeHtml(technology.subtitle)}</span>
            </span>
        </label>
    `;
}
