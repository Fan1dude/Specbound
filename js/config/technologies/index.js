import pcBuild from "./pc-build.js";
import setup from "./setup.js";
import arduino from "./arduino.js";
import robotics from "./robotics.js";
import homelab from "./homelab.js";
import printing from "./printing.js";

export const TECHNOLOGIES = [
    pcBuild,
    setup,
    arduino,
    robotics,
    printing,
    homelab
];

export function getTechnology(id) {
    return TECHNOLOGIES.find(
        technology => technology.id === id
    ) || null;
}

export function getTechnologyFilters(id) {
    return getTechnology(id)?.filters || [];
}

export function getTechnologySpecifications(id) {
    return getTechnology(id)?.specifications || [];
}

// Milestone 23 §5 — Category-scoped search matches against this
// top-level technology list only (human-readable title or stored
// identifier), never the internal Setup-inventory groups (Desk,
// Lighting, ...) a builder defines inside a single Setup blueprint —
// those are a per-blueprint organizational detail, not a site-wide
// blueprint category.
export function searchTechnologies(query) {
    const trimmed = query.trim().toLowerCase();
    if (!trimmed) return [];

    return TECHNOLOGIES.filter(
        technology =>
            technology.title.toLowerCase().includes(trimmed) ||
            technology.id.toLowerCase().includes(trimmed)
    );
}