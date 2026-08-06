// A specifications entry's value used to always be a plain string, e.g.
// {cpu: "Ryzen 7800X3D"}. Every save path now writes a structured value
// instead — {cpu: {componentId, name}} — so a part can carry a stable
// catalog id (see supabase/migrations/0020_components_catalog.sql)
// alongside its display name. Existing published builds/drafts still
// have the old plain-string shape and always will (no backfill — see
// the architecture plan's Risks section), so every reader goes through
// these functions instead of assuming either shape directly.
export function normalizeSpecEntry(raw) {
    if (raw && typeof raw === "object" && !Array.isArray(raw)) {
        return { componentId: raw.componentId ?? null, name: String(raw.name ?? "").trim() };
    }

    if (typeof raw === "string") {
        return { componentId: null, name: raw.trim() };
    }

    return { componentId: null, name: "" };
}

export function getSpecDisplayName(raw) {
    return normalizeSpecEntry(raw).name;
}

export function getSpecComponentId(raw) {
    return normalizeSpecEntry(raw).componentId;
}

export function isSpecEntryFilled(raw) {
    return Boolean(getSpecDisplayName(raw));
}
