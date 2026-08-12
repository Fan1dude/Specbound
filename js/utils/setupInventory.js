// Milestone 23 — normalization, validation, and totals math for the
// Setup-technology product inventory (setup_inventory jsonb — see
// docs/milestones/MILESTONE_23_SETUP_INVENTORY_SEARCH_SPECIFICATION.md
// §3 for the full shape rationale). Pure, no I/O — the same "validate at
// the application boundary" posture js/utils/specifications.js already
// established for the older per-technology specifications field.
//
// Every write path (editor autosave, publish snapshot, revision
// restore) is expected to run its value through normalizeInventory()
// before it's ever persisted or rendered — this is what makes a
// hand-edited or legacy-shaped payload safe to load without special
// casing at every call site.

export const SETUP_INVENTORY_SCHEMA_VERSION = 1;
export const DEFAULT_CURRENCY = "USD";

export const DEFAULT_CATEGORY_NAMES = [
    "Desk",
    "Displays",
    "Peripherals",
    "Audio",
    "Lighting",
    "Furniture",
    "Cable Management",
    "Other"
];

export const SOURCE_TYPES = [
    { value: "retailer", label: "Retailer" },
    { value: "thrift_store", label: "Thrift Store" },
    { value: "marketplace", label: "Marketplace" },
    { value: "gifted", label: "Gifted" },
    { value: "other", label: "Other" }
];

const SOURCE_TYPE_VALUES = new Set(SOURCE_TYPES.map(t => t.value));

// Limits — deliberately generous for real-world desk setups (a builder
// with 20 categories and 50 items each is already an extreme outlier)
// while still bounding worst-case payload size/render cost for a single
// jsonb column with no pagination.
export const LIMITS = {
    MAX_CATEGORIES: 20,
    MAX_ITEMS_PER_CATEGORY: 50,
    MAX_CATEGORY_NAME_LENGTH: 60,
    MAX_ITEM_TITLE_LENGTH: 120,
    MAX_URL_LENGTH: 2000,
    MAX_SOURCE_NAME_LENGTH: 80,
    MAX_RETAILER_NAME_LENGTH: 80
};

function makeId() {
    return crypto.randomUUID();
}

export function createEmptyInventory(currency = DEFAULT_CURRENCY) {
    return {
        schemaVersion: SETUP_INVENTORY_SCHEMA_VERSION,
        currency: normalizeCurrency(currency),
        categories: []
    };
}

export function createDefaultCategories() {
    return DEFAULT_CATEGORY_NAMES.map((name, index) => createCategory({ name, sortOrder: index }));
}

export function createCategory({ name, templateId = null, sortOrder = 0 } = {}) {
    return {
        id: makeId(),
        name: normalizeCategoryName(name),
        templateId: templateId || null,
        sortOrder,
        items: []
    };
}

export function createItem({ title = "", sortOrder = 0 } = {}) {
    return {
        id: makeId(),
        title: clampString(title, LIMITS.MAX_ITEM_TITLE_LENGTH),
        originalUrl: null,
        retailerName: null,
        listedPriceCents: null,
        listedPriceCurrency: null,
        metadataFetchedAt: null,
        pricePaid: { cents: null, isFree: false },
        sourceType: "other",
        sourceName: null,
        sortOrder
    };
}

function clampString(value, maxLength) {
    if (typeof value !== "string") return "";
    return value.trim().slice(0, maxLength);
}

function normalizeCategoryName(value) {
    const trimmed = clampString(value, LIMITS.MAX_CATEGORY_NAME_LENGTH);
    return trimmed || "Untitled Category";
}

function normalizeCurrency(value) {
    if (typeof value !== "string") return DEFAULT_CURRENCY;
    const trimmed = value.trim().toUpperCase();
    // ISO 4217 codes are exactly 3 letters — this app only ever writes
    // "USD" today, but the check stays generic rather than hardcoding a
    // single-value enum, since the shape itself is meant to support any
    // one currency per inventory (see spec §6 — never converted, never
    // mixed within one inventory).
    return /^[A-Z]{3}$/.test(trimmed) ? trimmed : DEFAULT_CURRENCY;
}

function isPlainObject(value) {
    return typeof value === "object" && value !== null && !Array.isArray(value);
}

// Integer cents or null — never a float, never NaN, never a negative
// number (a negative "price paid" has no real meaning here).
function normalizeCents(value) {
    if (value === null || value === undefined) return null;
    const num = typeof value === "number" ? value : Number(value);
    if (!Number.isFinite(num)) return null;
    const rounded = Math.round(num);
    if (rounded < 0) return null;
    return rounded;
}

function normalizeUrl(value) {
    if (typeof value !== "string") return null;
    const trimmed = value.trim().slice(0, LIMITS.MAX_URL_LENGTH);
    if (!trimmed) return null;

    try {
        const parsed = new URL(trimmed);
        if (parsed.protocol !== "http:" && parsed.protocol !== "https:") return null;
        return trimmed;
    } catch {
        return null;
    }
}

function normalizeSourceType(value) {
    return SOURCE_TYPE_VALUES.has(value) ? value : "other";
}

function normalizeIsoTimestamp(value) {
    if (typeof value !== "string") return null;
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

// Accepts either this module's own nested { cents, isFree } shape, or
// the flat { pricePaidCents, isFree } shape from the milestone's
// illustrative contract — see spec §3.1 for why the nested shape is
// what's actually persisted going forward. isFree always wins over a
// simultaneously-set cents value (a contradictory legacy/malformed
// payload is resolved as "free", the more specific, more deliberate of
// the two claims).
function normalizePricePaid(rawItem) {
    const isFree = Boolean(rawItem?.pricePaid?.isFree ?? rawItem?.isFree);
    if (isFree) return { cents: null, isFree: true };

    const cents = normalizeCents(rawItem?.pricePaid?.cents ?? rawItem?.pricePaidCents);
    return { cents, isFree: false };
}

function normalizeItem(raw, index) {
    if (!isPlainObject(raw)) raw = {};

    return {
        id: typeof raw.id === "string" && raw.id.trim() ? raw.id : makeId(),
        title: clampString(raw.title, LIMITS.MAX_ITEM_TITLE_LENGTH),
        originalUrl: normalizeUrl(raw.originalUrl),
        retailerName: raw.retailerName ? clampString(raw.retailerName, LIMITS.MAX_RETAILER_NAME_LENGTH) : null,
        listedPriceCents: normalizeCents(raw.listedPriceCents),
        listedPriceCurrency: raw.listedPriceCurrency ? normalizeCurrency(raw.listedPriceCurrency) : null,
        metadataFetchedAt: normalizeIsoTimestamp(raw.metadataFetchedAt),
        pricePaid: normalizePricePaid(raw),
        sourceType: normalizeSourceType(raw.sourceType),
        sourceName: raw.sourceName ? clampString(raw.sourceName, LIMITS.MAX_SOURCE_NAME_LENGTH) : null,
        sortOrder: Number.isFinite(raw.sortOrder) ? raw.sortOrder : index
    };
}

function normalizeCategory(raw, index) {
    if (!isPlainObject(raw)) raw = {};

    const rawItems = Array.isArray(raw.items) ? raw.items : [];

    return {
        id: typeof raw.id === "string" && raw.id.trim() ? raw.id : makeId(),
        name: normalizeCategoryName(raw.name),
        templateId: typeof raw.templateId === "string" && raw.templateId.trim() ? raw.templateId : null,
        sortOrder: Number.isFinite(raw.sortOrder) ? raw.sortOrder : index,
        items: rawItems.slice(0, LIMITS.MAX_ITEMS_PER_CATEGORY).map(normalizeItem)
    };
}

// The one function every read AND write path must call. Never throws —
// a malformed/legacy/adversarial payload is repaired into the closest
// valid shape rather than rejected outright, since this runs on load
// (an editor must still open even if a previous save was somehow
// invalid) as well as before save.
export function normalizeInventory(raw) {
    if (!isPlainObject(raw)) return createEmptyInventory();

    const rawCategories = Array.isArray(raw.categories) ? raw.categories : [];

    return {
        schemaVersion: SETUP_INVENTORY_SCHEMA_VERSION,
        currency: normalizeCurrency(raw.currency),
        categories: rawCategories.slice(0, LIMITS.MAX_CATEGORIES).map(normalizeCategory)
    };
}

// "Empty" means no actual products anywhere — not "no categories." A
// category (including an empty saved-category template) with zero
// items contributes nothing to inventory and must not, by itself, make
// this return false; a single item, regardless of price/Free/unknown
// state, makes it non-empty.
export function isInventoryEmpty(inventory) {
    return !inventory?.categories?.some(category => category?.items?.length > 0);
}

// --- Totals -----------------------------------------------------------
// Sum of pricePaid.cents across known-price items, plus isFree items
// (counted as a known $0) — missing prices are excluded from the sum
// entirely (never treated as 0), and separately flagged via hasUnknown
// so the caller can choose the "Setup total" vs "Known total" label.
export function calculateCategoryTotal(category) {
    let knownCents = 0;
    let hasUnknown = false;

    for (const item of category?.items || []) {
        if (item.pricePaid?.isFree) continue; // contributes 0, already known
        if (item.pricePaid?.cents === null || item.pricePaid?.cents === undefined) {
            hasUnknown = true;
            continue;
        }
        knownCents += item.pricePaid.cents;
    }

    return { knownCents, hasUnknown };
}

export function calculateSetupTotal(inventory) {
    let knownCents = 0;
    let hasUnknown = false;

    for (const category of inventory?.categories || []) {
        const subtotal = calculateCategoryTotal(category);
        knownCents += subtotal.knownCents;
        if (subtotal.hasUnknown) hasUnknown = true;
    }

    return {
        knownCents,
        hasUnknown,
        label: hasUnknown ? "Known total" : "Setup total"
    };
}

// Intl.NumberFormat handles locale-appropriate grouping/decimal marks;
// cents -> major-unit division is the only arithmetic here, and it's
// display-only — never round-tripped back into storage.
export function formatCents(cents, currency = DEFAULT_CURRENCY) {
    if (cents === null || cents === undefined) return "—";

    try {
        return new Intl.NumberFormat(undefined, { style: "currency", currency }).format(cents / 100);
    } catch {
        return `$${(cents / 100).toFixed(2)}`;
    }
}

// Parses a builder-typed price string ("64.99", "$64.99", "64") into
// integer cents. Returns null for anything that isn't a plain
// non-negative decimal number — never throws, never silently coerces
// garbage input into 0.
export function parseDollarsToCents(value) {
    if (typeof value !== "string") return null;

    const cleaned = value.trim().replace(/^\$/, "");
    if (!/^\d+(\.\d{1,2})?$/.test(cleaned)) return null;

    return Math.round(Number(cleaned) * 100);
}

// A fetched metadata price is only usable if its currency matches the
// inventory's own currency exactly — never converted (spec §6).
export function isCompatibleCurrency(inventoryCurrency, suggestedCurrency) {
    if (!suggestedCurrency) return true; // no currency claimed, nothing to conflict with
    return normalizeCurrency(inventoryCurrency) === normalizeCurrency(suggestedCurrency);
}
