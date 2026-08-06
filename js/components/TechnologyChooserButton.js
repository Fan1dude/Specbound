import { escapeHtml, escapeAttribute } from "../utils/escapeHtml.js";
import { technologyPickerIconUrl } from "./technologyPickerShared.js";

// Used by the Welcome dialog's chooser step (core/onboarding.js). Unlike
// TechnologyRadioCard (upload.html's form, where a choice is held until a
// separate submit), picking a technology here is an immediate one-click
// action — create a draft and navigate straight to the editor — so a real
// <button> is the correct native fit, not a radio input, which would
// incorrectly imply a persisted selection state this flow never has. No
// custom ARIA needed: the visible title/subtitle text already serves as
// each button's accessible name.
export function TechnologyChooserButton(technology, { pathPrefix = "" } = {}) {
    const iconUrl = technologyPickerIconUrl(technology, pathPrefix);

    return `
        <button
            type="button"
            class="technology-picker-card"
            data-category-accent="${escapeAttribute(technology.accent)}"
            data-category-icon="${escapeAttribute(iconUrl)}"
            data-category-id="${escapeAttribute(technology.id)}"
        >
            <span class="technology-picker-icon" aria-hidden="true">
                <span class="technology-picker-symbol"></span>
            </span>
            <span class="technology-picker-body">
                <strong>${escapeHtml(technology.title)}</strong>
                <span>${escapeHtml(technology.subtitle)}</span>
            </span>
        </button>
    `;
}
