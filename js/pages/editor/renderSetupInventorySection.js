import {
    normalizeInventory,
    createEmptyInventory,
    createCategory,
    createItem,
    DEFAULT_CATEGORY_NAMES,
    SOURCE_TYPES,
    LIMITS,
    isInventoryEmpty,
    calculateCategoryTotal,
    calculateSetupTotal,
    formatCents,
    parseDollarsToCents,
    isCompatibleCurrency
} from "../../utils/setupInventory.js";
import {
    getMySavedSetupCategories,
    createSavedSetupCategory
} from "../../repositories/savedSetupCategoryRepository.js";
import { fetchProductMetadata } from "../../services/productMetadata.js";
import { escapeHtml, escapeAttribute } from "../../utils/escapeHtml.js";
import { icon } from "../../utils/icons.js";
import { showToast } from "../../core/toast.js";
import { confirmDialog } from "../../utils/modal.js";

// Milestone 23 — the Setup-technology product inventory. Lives inside
// the existing Specifications panel (js/pages/editor/renderSpecificationsSection.js
// renders the sibling #specificationsFields container in the same
// panel) rather than a new tab, so no change to editorTabs.js's
// static tab-cycling list is needed — this section simply shows/hides
// itself via the same categoryField "change" listener specifications
// already uses to re-render per technology.
//
// One committed, normalized inventory object lives in module state
// (currentInventory) and is mutated in place by every action below,
// never rebuilt from scratch — normalizeInventory() only ever fills in
// a missing id, never replaces an existing one, so item/category
// identity survives every re-render (explicit requirement: "Avoid
// regenerating item IDs during re-renders").
export function renderSetupInventorySection(draft, autosave) {
    const container = document.getElementById("setupInventorySection");
    const categoryField = document.getElementById("fieldCategory");

    if (!container || !categoryField) return { applyFields() {} };

    let currentInventory = normalizeInventory(draft.setup_inventory || createEmptyInventory());
    let savedCategories = [];
    let savedCategoriesLoadFailed = false;
    let addCategoryMode = null; // null | "picker" | "custom"

    // Per-item metadata-fetch result, kept outside currentInventory since
    // it's transient UI feedback, not saved data. Read by renderItem() on
    // every render so the message survives a commit()-triggered re-render
    // instead of being wiped by it — the whole point of this map is that
    // setting statusEl.textContent directly doesn't survive the next
    // render() call, but currentInventory has nowhere to hold "the last
    // fetch for this item found nothing."
    const itemMetadataStatus = new Map(); // itemId -> { type: "error" | "info", message }

    loadSavedCategories();

    updateVisibility(draft.category);
    render();

    categoryField.addEventListener("change", () => {
        updateVisibility(categoryField.value);
    });

    function updateVisibility(technologyId) {
        container.hidden = technologyId !== "setup";
    }

    async function loadSavedCategories() {
        try {
            savedCategories = await getMySavedSetupCategories(draft.user_id);
        } catch (error) {
            // Compatibility requirement: a saved-category load failure must
            // never block blueprint-local categories from working.
            console.error("Saved setup categories load error:", error);
            savedCategoriesLoadFailed = true;
        }
        render();
    }

    function commit() {
        currentInventory = normalizeInventory(currentInventory);
        autosave.scheduleSave({ setup_inventory: currentInventory });
        render();
    }

    // --- Category-level actions --------------------------------------
    function addCategory(name, templateId = null) {
        if (currentInventory.categories.length >= LIMITS.MAX_CATEGORIES) {
            showToast(`You can only have up to ${LIMITS.MAX_CATEGORIES} categories.`, "warning");
            return;
        }

        currentInventory.categories.push(
            createCategory({ name, templateId, sortOrder: currentInventory.categories.length })
        );
        addCategoryMode = null;
        commit();
    }

    async function addCustomCategory(rawName, saveToMyCategories) {
        const name = rawName.trim();

        if (!name) {
            showToast("Enter a category name.", "warning");
            return;
        }

        if (!saveToMyCategories) {
            addCategory(name);
            return;
        }

        try {
            const saved = await createSavedSetupCategory(draft.user_id, name);
            savedCategories = [...savedCategories, saved].sort((a, b) => a.name.localeCompare(b.name));
            addCategory(saved.name, saved.id);
        } catch (error) {
            console.error("Save category error:", error);
            showToast(error.message || "Could not save this category.", "error");
        }
    }

    function renameCategory(categoryId, name) {
        const category = currentInventory.categories.find(c => c.id === categoryId);
        if (!category) return;
        category.name = name.trim() || category.name;
        commit();
    }

    async function deleteCategory(categoryId) {
        const category = currentInventory.categories.find(c => c.id === categoryId);
        if (!category) return;

        if (category.items.length) {
            const confirmed = await confirmDialog({
                title: `Delete "${category.name}"?`,
                body: `This also removes ${category.items.length} product${category.items.length === 1 ? "" : "s"} in this category. This can't be undone.`,
                confirmLabel: "Delete",
                danger: true
            });
            if (!confirmed) return;
        }

        currentInventory.categories = currentInventory.categories
            .filter(c => c.id !== categoryId)
            .map((c, index) => ({ ...c, sortOrder: index }));
        commit();
    }

    function moveCategory(categoryId, direction) {
        const categories = currentInventory.categories;
        const index = categories.findIndex(c => c.id === categoryId);
        const targetIndex = index + direction;

        if (index === -1 || targetIndex < 0 || targetIndex >= categories.length) return;

        [categories[index], categories[targetIndex]] = [categories[targetIndex], categories[index]];
        categories.forEach((c, i) => { c.sortOrder = i; });
        commit();
    }

    // --- Item-level actions ---------------------------------------------
    // A completely untouched item — exactly what createItem() produces by
    // default. Deliberately doesn't check sourceType (defaults to "other"
    // either way) so a stray selection there alone doesn't count as
    // "filled in." Used to stop repeated Add Product clicks from piling
    // up multiple blank cards — see addItem() below.
    function isEffectivelyEmptyItem(item) {
        return !item.title
            && !item.originalUrl
            && item.pricePaid.cents === null
            && !item.pricePaid.isFree
            && !item.sourceName;
    }

    function focusItem(itemId, { scroll = false, flash = false } = {}) {
        const card = container.querySelector(`.setup-item[data-item-id="${cssEscape(itemId)}"]`);
        if (!card) return;

        if (scroll) card.scrollIntoView({ behavior: "smooth", block: "center" });

        card.querySelector('[data-action="edit-item-title"]')?.focus();

        if (flash) {
            // requestAnimationFrame so the browser registers the
            // pre-flash state first — same pattern already used for the
            // toast "show" transition in core/toast.js.
            requestAnimationFrame(() => {
                card.classList.add("setup-item-just-added");
                setTimeout(() => card.classList.remove("setup-item-just-added"), 1500);
            });
        }
    }

    function addItem(categoryId) {
        const category = currentInventory.categories.find(c => c.id === categoryId);
        if (!category) return;

        // A blank product card left over from an earlier click — reuse it
        // instead of creating a second, third, ... blank card. This is
        // what actually stops "Add Product" spam from producing a pile of
        // empty products; the button itself stays a normal, always-
        // enabled control (no artificial disable/debounce needed).
        const existingBlank = category.items.find(isEffectivelyEmptyItem);
        if (existingBlank) {
            showToast("Finish adding this product first.", "info");
            focusItem(existingBlank.id, { scroll: true });
            return;
        }

        if (category.items.length >= LIMITS.MAX_ITEMS_PER_CATEGORY) {
            showToast(`You can only have up to ${LIMITS.MAX_ITEMS_PER_CATEGORY} products per category.`, "warning");
            return;
        }

        const newItem = createItem({ sortOrder: category.items.length });
        category.items.push(newItem);
        commit();

        focusItem(newItem.id, { scroll: true, flash: true });
        showToast("Product added.", "success");
    }

    function findItem(itemId) {
        for (const category of currentInventory.categories) {
            const item = category.items.find(i => i.id === itemId);
            if (item) return { category, item };
        }
        return null;
    }

    function updateItem(itemId, patch) {
        const found = findItem(itemId);
        if (!found) return;
        Object.assign(found.item, patch);
        commit();
    }

    async function deleteItem(itemId) {
        const found = findItem(itemId);
        if (!found) return;

        const confirmed = await confirmDialog({
            title: `Delete "${found.item.title || "this product"}"?`,
            body: "This can't be undone.",
            confirmLabel: "Delete",
            danger: true
        });
        if (!confirmed) return;

        itemMetadataStatus.delete(itemId);
        found.category.items = found.category.items
            .filter(i => i.id !== itemId)
            .map((i, index) => ({ ...i, sortOrder: index }));
        commit();
    }

    function moveItem(itemId, direction) {
        const found = findItem(itemId);
        if (!found) return;

        const items = found.category.items;
        const index = items.findIndex(i => i.id === itemId);
        const targetIndex = index + direction;

        if (targetIndex < 0 || targetIndex >= items.length) return;

        [items[index], items[targetIndex]] = [items[targetIndex], items[index]];
        items.forEach((i, idx) => { i.sortOrder = idx; });
        commit();
    }

    function moveItemToCategory(itemId, targetCategoryId) {
        const found = findItem(itemId);
        if (!found || found.category.id === targetCategoryId) return;

        const targetCategory = currentInventory.categories.find(c => c.id === targetCategoryId);
        if (!targetCategory) return;

        if (targetCategory.items.length >= LIMITS.MAX_ITEMS_PER_CATEGORY) {
            showToast(`"${targetCategory.name}" already has the maximum number of products.`, "warning");
            return;
        }

        found.category.items = found.category.items.filter(i => i.id !== itemId);
        found.item.sortOrder = targetCategory.items.length;
        targetCategory.items.push(found.item);

        found.category.items.forEach((i, idx) => { i.sortOrder = idx; });
        commit();
    }

    // What we tell the builder once a fetch settles — reused for both the
    // "the request itself failed" case and the "it succeeded but found
    // nothing usable" case, since from the builder's side those look the
    // same: paste a link, nothing came back, fall back to typing it in.
    const NOTHING_FOUND_MESSAGE = "We couldn't fill in details from this link. You can enter them manually below.";
    const PARTIAL_SUCCESS_MESSAGE = "We filled in what we found. Complete any missing details below.";

    async function fetchMetadataForItem(itemId, url) {
        const found = findItem(itemId);
        if (!found) return;

        const button = container.querySelector(`[data-action="fetch-metadata"][data-item-id="${cssEscape(itemId)}"]`);

        itemMetadataStatus.delete(itemId);
        renderMetadataStatus(itemId);

        if (button) {
            button.disabled = true;
            button.textContent = "Filling in details...";
        }

        try {
            const result = await fetchProductMetadata(url);

            // Only fields the builder hasn't already edited are populated —
            // approximated here as "field is currently empty," which is
            // exactly the state a fresh item (or an item whose title/price
            // the builder never touched) is in. Once a builder types
            // something, this fetch (or a later one) never overwrites it.
            const patch = { originalUrl: url, metadataFetchedAt: new Date().toISOString() };

            if (!found.item.title && result.title) patch.title = result.title;
            if (result.retailerName) patch.retailerName = result.retailerName;

            let priceApplied = false;
            if (typeof result.priceCents === "number") {
                if (isCompatibleCurrency(currentInventory.currency, result.currency)) {
                    patch.listedPriceCents = result.priceCents;
                    patch.listedPriceCurrency = result.currency || currentInventory.currency;
                    priceApplied = true;
                    if (found.item.pricePaid.cents === null && !found.item.pricePaid.isFree) {
                        patch.pricePaid = { cents: result.priceCents, isFree: false };
                    }
                }
            }

            // Classify what the retailer actually gave us — never $0/Free
            // for a genuinely missing price, just "found nothing" or
            // "found some of it," matching the three-way outcome the
            // builder needs to see (nothing / partial / everything).
            const foundTitle = !!result.title;
            const foundPrice = priceApplied;
            const foundAnything = foundTitle || foundPrice || !!result.retailerName;

            if (!foundAnything) {
                itemMetadataStatus.set(itemId, { type: "error", message: NOTHING_FOUND_MESSAGE });
            } else if (!(foundTitle && foundPrice)) {
                itemMetadataStatus.set(itemId, { type: "info", message: PARTIAL_SUCCESS_MESSAGE });
            } else {
                itemMetadataStatus.delete(itemId);
            }

            updateItem(itemId, patch);
        } catch (error) {
            console.error("Product metadata fetch error:", error);
            // Never touch the item's data on failure — the pasted URL and
            // every manually-entered field stay exactly as they were.
            itemMetadataStatus.set(itemId, {
                type: "error",
                message: error instanceof Error && error.message ? error.message : NOTHING_FOUND_MESSAGE
            });
            renderMetadataStatus(itemId);
        } finally {
            const liveButton = container.querySelector(`[data-action="fetch-metadata"][data-item-id="${cssEscape(itemId)}"]`);
            if (liveButton) {
                liveButton.disabled = false;
                liveButton.textContent = "Fill details from link";
            }
        }
    }

    // Single source of truth for how a metadata status renders, shared by
    // the initial template (renderItem, below) and the in-place DOM patch
    // (renderMetadataStatus, right after this) so the two never drift.
    // The icon means the distinction isn't color-only, and role="alert" vs
    // role="status" gives assistive tech the right urgency for each case.
    function metadataStatusView(itemId) {
        const status = itemMetadataStatus.get(itemId);
        if (!status) {
            return { className: "setup-item-metadata-status", role: null, innerHTML: "" };
        }

        return {
            className: `setup-item-metadata-status setup-item-metadata-status-${status.type}`,
            role: status.type === "error" ? "alert" : "status",
            innerHTML: `
                <span class="setup-item-metadata-status-icon" aria-hidden="true">${icon(status.type === "error" ? "warning" : "info", 16)}</span>
                <span>${escapeHtml(status.message)}</span>
            `
        };
    }

    // Updates one item's status paragraph in place, without a full
    // commit()/render() — used for the failure path (nothing in
    // currentInventory changes, so a re-render would be pure churn) and
    // for clearing the message the instant a new fetch starts. The
    // success path still goes through commit()/render() via updateItem(),
    // which is fine because renderItem() reads itemMetadataStatus fresh
    // every time via the same metadataStatusView() — the map, not the
    // DOM, is the source of truth either way.
    function renderMetadataStatus(itemId) {
        const el = container.querySelector(`[data-metadata-status="${cssEscape(itemId)}"]`);
        if (!el) return;

        const view = metadataStatusView(itemId);
        el.className = view.className;
        if (view.role) el.setAttribute("role", view.role);
        else el.removeAttribute("role");
        el.innerHTML = view.innerHTML;
    }

    function cssEscape(value) {
        return typeof CSS !== "undefined" && CSS.escape ? CSS.escape(value) : value.replace(/["\\]/g, "\\$&");
    }

    // --- Render -----------------------------------------------------------
    function render() {
        const setupTotal = calculateSetupTotal(currentInventory);

        container.innerHTML = `
            <div class="section-heading">
                <h2>Setup Inventory</h2>
                <p>Group what's in your setup by category, with as much or as little pricing detail as you want to share.</p>
            </div>

            ${!isInventoryEmpty(currentInventory)
                ? `<div class="setup-inventory-total">
                        <span class="setup-inventory-total-label">${escapeHtml(setupTotal.label)}</span>
                        <span class="setup-inventory-total-value">${escapeHtml(formatCents(setupTotal.knownCents, currentInventory.currency))}</span>
                        ${setupTotal.hasUnknown ? `<span class="setup-inventory-total-note">One or more products don't have a price yet.</span>` : ""}
                   </div>`
                : ""
            }

            <div class="setup-inventory-categories">
                ${currentInventory.categories.map(renderCategory).join("")}
            </div>

            ${renderAddCategoryControl()}
        `;

        wireEvents();
    }

    function renderCategory(category, index) {
        const subtotal = calculateCategoryTotal(category);
        const isFirst = index === 0;
        const isLast = index === currentInventory.categories.length - 1;

        return `
            <section class="setup-category" data-category-id="${escapeAttribute(category.id)}">
                <header class="setup-category-header">
                    <input
                        type="text"
                        class="setup-category-name-input"
                        data-action="rename-category"
                        data-category-id="${escapeAttribute(category.id)}"
                        value="${escapeAttribute(category.name)}"
                        aria-label="Category name"
                        maxlength="${LIMITS.MAX_CATEGORY_NAME_LENGTH}"
                    >

                    <div class="setup-category-controls">
                        <button type="button" class="btn-icon" data-action="move-category-up" data-category-id="${escapeAttribute(category.id)}" ${isFirst ? "disabled" : ""} aria-label="Move ${escapeAttribute(category.name)} category up">
                            ${icon("chevron-up", 16)}
                        </button>
                        <button type="button" class="btn-icon" data-action="move-category-down" data-category-id="${escapeAttribute(category.id)}" ${isLast ? "disabled" : ""} aria-label="Move ${escapeAttribute(category.name)} category down">
                            ${icon("chevron-down", 16)}
                        </button>
                        <button type="button" class="btn btn-ghost btn-small" data-action="delete-category" data-category-id="${escapeAttribute(category.id)}">
                            Delete
                        </button>
                    </div>
                </header>

                <div class="setup-items">
                    ${category.items.map((item, itemIndex) => renderItem(item, category, itemIndex)).join("")}
                </div>

                <div class="setup-add-product-intro">
                    <p class="setup-add-product-heading">Add a product</p>
                    <p class="setup-add-product-description">Enter the product details yourself, or paste a product link and we'll fill in what we can.</p>
                </div>

                <div class="setup-category-footer">
                    <button type="button" class="btn btn-secondary btn-small" data-action="add-item" data-category-id="${escapeAttribute(category.id)}">
                        Add Product
                    </button>
                    ${category.items.length
                        ? `<span class="setup-category-subtotal">
                                Subtotal: ${escapeHtml(formatCents(subtotal.knownCents, currentInventory.currency))}${subtotal.hasUnknown ? " (known)" : ""}
                           </span>`
                        : ""
                    }
                </div>
            </section>
        `;
    }

    function renderItem(item, category, index) {
        const isFirst = index === 0;
        const isLast = index === category.items.length - 1;
        const otherCategories = currentInventory.categories.filter(c => c.id !== category.id);
        const metadataStatus = metadataStatusView(item.id);

        return `
            <div class="setup-item" data-item-id="${escapeAttribute(item.id)}">
                <div class="setup-item-row">
                    <input
                        type="text"
                        class="setup-item-title-input"
                        data-action="edit-item-title"
                        data-item-id="${escapeAttribute(item.id)}"
                        value="${escapeAttribute(item.title)}"
                        placeholder="Product title"
                        aria-label="Product title"
                        maxlength="${LIMITS.MAX_ITEM_TITLE_LENGTH}"
                    >

                    <div class="setup-item-move-controls">
                        <button type="button" class="btn-icon" data-action="move-item-up" data-item-id="${escapeAttribute(item.id)}" ${isFirst ? "disabled" : ""} aria-label="Move ${escapeAttribute(item.title || "this product")} up">
                            ${icon("chevron-up", 16)}
                        </button>
                        <button type="button" class="btn-icon" data-action="move-item-down" data-item-id="${escapeAttribute(item.id)}" ${isLast ? "disabled" : ""} aria-label="Move ${escapeAttribute(item.title || "this product")} down">
                            ${icon("chevron-down", 16)}
                        </button>
                        <button type="button" class="btn-icon" data-action="delete-item" data-item-id="${escapeAttribute(item.id)}" aria-label="Delete ${escapeAttribute(item.title || "this product")}">
                            ${icon("trash", 16)}
                        </button>
                    </div>
                </div>

                <div class="setup-item-fields-grid">
                    <div class="setup-item-field setup-item-field-link">
                        <label class="setup-item-link-label">
                            Product link (optional)
                            <input
                                type="url"
                                class="setup-item-url-input"
                                data-action="edit-item-url"
                                data-item-id="${escapeAttribute(item.id)}"
                                value="${escapeAttribute(item.originalUrl || "")}"
                                placeholder="Paste a retailer product link"
                                maxlength="${LIMITS.MAX_URL_LENGTH}"
                            >
                        </label>
                        <button type="button" class="btn btn-secondary btn-small" data-action="fetch-metadata" data-item-id="${escapeAttribute(item.id)}" ${item.originalUrl ? "" : "disabled"}>
                            Fill details from link
                        </button>
                        <p class="${metadataStatus.className}" data-metadata-status="${escapeAttribute(item.id)}"${metadataStatus.role ? ` role="${metadataStatus.role}"` : ""}>${metadataStatus.innerHTML}</p>
                        ${item.retailerName
                            ? `<p class="setup-item-suggested">Suggested from ${escapeHtml(item.retailerName)}${typeof item.listedPriceCents === "number" ? `: ${escapeHtml(formatCents(item.listedPriceCents, item.listedPriceCurrency || currentInventory.currency))}` : ""}</p>`
                            : ""
                        }
                    </div>

                    <div class="setup-item-field setup-item-field-price">
                        <label class="setup-item-price-label">
                            Price paid
                            <input
                                type="text"
                                inputmode="decimal"
                                class="setup-item-price-input"
                                data-action="edit-item-price"
                                data-item-id="${escapeAttribute(item.id)}"
                                value="${item.pricePaid.cents !== null ? escapeAttribute((item.pricePaid.cents / 100).toFixed(2)) : ""}"
                                placeholder="0.00"
                                ${item.pricePaid.isFree ? "disabled" : ""}
                            >
                        </label>
                    </div>

                    <div class="setup-item-field setup-item-field-free">
                        <label class="setup-item-free-toggle">
                            <input type="checkbox" data-action="toggle-item-free" data-item-id="${escapeAttribute(item.id)}" ${item.pricePaid.isFree ? "checked" : ""}>
                            Free
                        </label>
                    </div>

                    <div class="setup-item-field setup-item-field-source-type">
                        <label class="setup-item-source-type-label">
                            Where I found it
                            <select data-action="edit-item-source-type" data-item-id="${escapeAttribute(item.id)}">
                                ${SOURCE_TYPES.map(type => `<option value="${escapeAttribute(type.value)}" ${item.sourceType === type.value ? "selected" : ""}>${escapeHtml(type.label)}</option>`).join("")}
                            </select>
                        </label>
                    </div>

                    <div class="setup-item-field setup-item-field-source-name">
                        <label class="setup-item-source-name-label">
                            Source name
                            <input
                                type="text"
                                class="setup-item-source-name-input"
                                data-action="edit-item-source-name"
                                data-item-id="${escapeAttribute(item.id)}"
                                value="${escapeAttribute(item.sourceName || "")}"
                                placeholder="e.g. Goodwill, Best Buy"
                                maxlength="${LIMITS.MAX_SOURCE_NAME_LENGTH}"
                            >
                        </label>
                    </div>

                    ${otherCategories.length
                        ? `<div class="setup-item-field setup-item-field-move-category">
                                <label class="setup-item-move-category-label">
                                    Move to
                                    <select data-action="move-item-category" data-item-id="${escapeAttribute(item.id)}">
                                        <option value="">Move to category...</option>
                                        ${otherCategories.map(c => `<option value="${escapeAttribute(c.id)}">${escapeHtml(c.name)}</option>`).join("")}
                                    </select>
                                </label>
                           </div>`
                        : ""
                    }
                </div>
            </div>
        `;
    }

    function renderAddCategoryControl() {
        const existingNames = new Set(currentInventory.categories.map(c => c.name.toLowerCase()));
        const availableDefaults = DEFAULT_CATEGORY_NAMES.filter(name => !existingNames.has(name.toLowerCase()));
        const availableSaved = savedCategories.filter(c => !existingNames.has(c.name.toLowerCase()));

        if (addCategoryMode === "custom") {
            return `
                <div class="setup-add-category-form">
                    <input type="text" id="newCategoryNameInput" placeholder="Category name" maxlength="${LIMITS.MAX_CATEGORY_NAME_LENGTH}" aria-label="New category name">
                    <div class="setup-add-category-actions">
                        <button type="button" class="btn btn-secondary btn-small" data-action="confirm-add-custom-category" data-save="false">
                            Use in this blueprint only
                        </button>
                        <button type="button" class="btn btn-primary btn-small" data-action="confirm-add-custom-category" data-save="true">
                            Save to My Categories
                        </button>
                        <button type="button" class="btn btn-ghost btn-small" data-action="cancel-add-category">Cancel</button>
                    </div>
                </div>
            `;
        }

        return `
            <div class="setup-add-category-controls">
                ${availableDefaults.length || availableSaved.length
                    ? `<div class="setup-add-category-chips">
                            ${availableDefaults.map(name => `<button type="button" class="badge setup-add-category-chip" data-action="quick-add-category" data-name="${escapeAttribute(name)}">+ ${escapeHtml(name)}</button>`).join("")}
                            ${availableSaved.map(c => `<button type="button" class="badge setup-add-category-chip" data-action="quick-add-saved-category" data-template-id="${escapeAttribute(c.id)}" data-name="${escapeAttribute(c.name)}">+ ${escapeHtml(c.name)} (saved)</button>`).join("")}
                       </div>`
                    : ""
                }
                <button type="button" class="btn btn-secondary" data-action="start-add-custom-category">
                    Add Custom Category
                </button>
                ${savedCategoriesLoadFailed ? `<p class="setup-inventory-note">Your saved categories couldn't be loaded — blueprint-local categories still work.</p>` : ""}
            </div>
        `;
    }

    function wireEvents() {
        container.querySelectorAll('[data-action="move-category-up"]').forEach(el =>
            el.addEventListener("click", () => moveCategory(el.dataset.categoryId, -1)));
        container.querySelectorAll('[data-action="move-category-down"]').forEach(el =>
            el.addEventListener("click", () => moveCategory(el.dataset.categoryId, 1)));
        container.querySelectorAll('[data-action="delete-category"]').forEach(el =>
            el.addEventListener("click", () => deleteCategory(el.dataset.categoryId)));
        container.querySelectorAll('[data-action="rename-category"]').forEach(el =>
            el.addEventListener("change", () => renameCategory(el.dataset.categoryId, el.value)));

        container.querySelectorAll('[data-action="add-item"]').forEach(el =>
            el.addEventListener("click", () => addItem(el.dataset.categoryId)));
        container.querySelectorAll('[data-action="move-item-up"]').forEach(el =>
            el.addEventListener("click", () => moveItem(el.dataset.itemId, -1)));
        container.querySelectorAll('[data-action="move-item-down"]').forEach(el =>
            el.addEventListener("click", () => moveItem(el.dataset.itemId, 1)));
        container.querySelectorAll('[data-action="delete-item"]').forEach(el =>
            el.addEventListener("click", () => deleteItem(el.dataset.itemId)));

        container.querySelectorAll('[data-action="edit-item-title"]').forEach(el =>
            el.addEventListener("change", () => updateItem(el.dataset.itemId, { title: el.value })));
        container.querySelectorAll('[data-action="edit-item-url"]').forEach(el => {
            el.addEventListener("change", () => {
                // A changed link invalidates whatever the last fetch (or
                // failure) said about the previous one.
                itemMetadataStatus.delete(el.dataset.itemId);
                updateItem(el.dataset.itemId, { originalUrl: el.value.trim() || null });
            });
        });
        container.querySelectorAll('[data-action="fetch-metadata"]').forEach(el =>
            el.addEventListener("click", () => {
                const found = findItem(el.dataset.itemId);
                if (found?.item.originalUrl) fetchMetadataForItem(el.dataset.itemId, found.item.originalUrl);
            }));
        container.querySelectorAll('[data-action="edit-item-price"]').forEach(el =>
            el.addEventListener("change", () => {
                const cents = el.value.trim() ? parseDollarsToCents(el.value) : null;
                if (el.value.trim() && cents === null) {
                    showToast("Enter a valid price, like 64.99.", "warning");
                    return;
                }
                updateItem(el.dataset.itemId, { pricePaid: { cents, isFree: false } });
            }));
        container.querySelectorAll('[data-action="toggle-item-free"]').forEach(el =>
            el.addEventListener("change", () => {
                updateItem(el.dataset.itemId, { pricePaid: { cents: null, isFree: el.checked } });
            }));
        container.querySelectorAll('[data-action="edit-item-source-type"]').forEach(el =>
            el.addEventListener("change", () => updateItem(el.dataset.itemId, { sourceType: el.value })));
        container.querySelectorAll('[data-action="edit-item-source-name"]').forEach(el =>
            el.addEventListener("change", () => updateItem(el.dataset.itemId, { sourceName: el.value.trim() || null })));
        container.querySelectorAll('[data-action="move-item-category"]').forEach(el =>
            el.addEventListener("change", () => {
                if (el.value) moveItemToCategory(el.dataset.itemId, el.value);
            }));

        container.querySelectorAll('[data-action="quick-add-category"]').forEach(el =>
            el.addEventListener("click", () => addCategory(el.dataset.name)));
        container.querySelectorAll('[data-action="quick-add-saved-category"]').forEach(el =>
            el.addEventListener("click", () => addCategory(el.dataset.name, el.dataset.templateId)));
        container.querySelectorAll('[data-action="start-add-custom-category"]').forEach(el =>
            el.addEventListener("click", () => { addCategoryMode = "custom"; render(); }));
        container.querySelectorAll('[data-action="cancel-add-category"]').forEach(el =>
            el.addEventListener("click", () => { addCategoryMode = null; render(); }));
        container.querySelectorAll('[data-action="confirm-add-custom-category"]').forEach(el =>
            el.addEventListener("click", () => {
                const input = document.getElementById("newCategoryNameInput");
                addCustomCategory(input?.value || "", el.dataset.save === "true");
            }));
    }

    // Recovery pipeline hook (draftRecoveryBanner.js) — a buffered
    // setup_inventory field is applied the same way applyFields already
    // works for overview/specifications/resources.
    function applyFields(fields) {
        if (!("setup_inventory" in fields)) return;
        currentInventory = normalizeInventory(fields.setup_inventory);
        render();
    }

    return { applyFields };
}
