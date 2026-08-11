import { escapeHtml, escapeAttribute } from "../../utils/escapeHtml.js";
import {
    normalizeInventory,
    isInventoryEmpty,
    calculateCategoryTotal,
    calculateSetupTotal,
    formatCents,
    SOURCE_TYPES
} from "../../utils/setupInventory.js";

const SOURCE_TYPE_LABELS = new Map(SOURCE_TYPES.map(type => [type.value, type.label]));

// Public, read-only rendering of a Setup blueprint's product inventory
// (Milestone 23 §4). Deliberately narrower than the editor's own render
// in renderSetupInventorySection.js — this never shows templateId
// (an internal editor-only reference), retailerName/listedPriceCents
// (link-metadata suggestions, not something the creator curated for
// public display), or metadataFetchedAt. Only the creator's own
// pricePaid/isFree and "where I found it" fields are public-facing.
//
// setup_inventory === null means "not recorded for this revision" (a
// revision published before this milestone captured per-revision
// snapshots) — mirrors the same null-vs-empty convention already used by
// renderSpecifications.js/renderResources.js for their own revision
// snapshots.
export function renderSetupInventory(rawInventory) {
    const container = document.getElementById("buildSetupInventory");
    const section = document.getElementById("buildSetupInventorySection");

    if (!container || !section) return;

    if (rawInventory === null) {
        section.hidden = true;
        return;
    }

    const inventory = normalizeInventory(rawInventory);

    if (isInventoryEmpty(inventory)) {
        section.hidden = true;
        return;
    }

    section.hidden = false;

    const setupTotal = calculateSetupTotal(inventory);

    container.innerHTML = `
        <div class="setup-inventory-total">
            <span class="setup-inventory-total-label">${escapeHtml(setupTotal.label)}</span>
            <span class="setup-inventory-total-value">${escapeHtml(formatCents(setupTotal.knownCents, inventory.currency))}</span>
            ${setupTotal.hasUnknown ? `<span class="setup-inventory-total-note">One or more products don't have a price paid listed.</span>` : ""}
        </div>

        <div class="setup-inventory-categories">
            ${inventory.categories.map(category => renderCategory(category, inventory.currency)).join("")}
        </div>
    `;
}

function renderCategory(category, currency) {
    if (!category.items.length) return "";

    const subtotal = calculateCategoryTotal(category);

    return `
        <section class="setup-category setup-category-public">
            <h3 class="setup-category-name">${escapeHtml(category.name)}</h3>

            <ul class="setup-items setup-items-public">
                ${category.items.map(item => renderItem(item, currency)).join("")}
            </ul>

            <p class="setup-category-subtotal">
                Subtotal: ${escapeHtml(formatCents(subtotal.knownCents, currency))}${subtotal.hasUnknown ? " (known)" : ""}
            </p>
        </section>
    `;
}

function renderItem(item, currency) {
    const title = item.title || "Untitled product";

    const titleMarkup = item.originalUrl
        ? `<a href="${escapeAttribute(item.originalUrl)}" target="_blank" rel="noopener noreferrer">${escapeHtml(title)}</a>`
        : escapeHtml(title);

    const priceMarkup = item.pricePaid.isFree
        ? `<span class="setup-item-public-price">Free</span>`
        : item.pricePaid.cents !== null
            ? `<span class="setup-item-public-price">${escapeHtml(formatCents(item.pricePaid.cents, currency))}</span>`
            : "";

    const sourceLabel = SOURCE_TYPE_LABELS.get(item.sourceType) || "";
    const sourceText = item.sourceName
        ? `${sourceLabel} — ${item.sourceName}`
        : (item.sourceType !== "other" ? sourceLabel : "");

    return `
        <li class="setup-item setup-item-public">
            <span class="setup-item-public-title">${titleMarkup}</span>
            ${priceMarkup}
            ${sourceText ? `<span class="setup-item-public-source">${escapeHtml(sourceText)}</span>` : ""}
        </li>
    `;
}
