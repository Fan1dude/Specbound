// Shared icon system — Milestone 10 brand refresh.
// See docs/milestones/MILESTONE_10_BRAND_REFRESH_ARCHITECTURE.md's Iconography
// Standards section: stroke-based construction only, 1.5px stroke at the
// 20px base size (scaled proportionally at the other 3 allowed sizes),
// rounded joins/caps, currentColor fill — never a hardcoded color, never a
// filled/solid glyph, never a Unicode text character standing in for an
// icon. This is the one shared source every icon in the app should render
// from, rather than each call site inlining its own <svg>.

const BASE_SIZE = 20;
const BASE_STROKE_WIDTH = 1.5;

// 16 / 20 / 24 / 32 are the only sizes this system defines — see the
// architecture doc for why a closed set, not an arbitrary range.
const SIZES = [16, 20, 24, 32];

const PATHS = {
    "arrow-right": '<line x1="4" y1="12" x2="20" y2="12"/><polyline points="13 5 20 12 13 19"/>',
    "chevron-down": '<polyline points="6 9 12 15 18 9"/>',
    check: '<polyline points="4 12 9 17 20 6"/>',
    circle: '<circle cx="12" cy="12" r="8"/>',
    close: '<line x1="6" y1="6" x2="18" y2="18"/><line x1="18" y1="6" x2="6" y2="18"/>',
    document: '<path d="M7 3h7l4 4v14H7z"/><line x1="10" y1="12" x2="15" y2="12"/><line x1="10" y1="16" x2="15" y2="16"/>',
    search: '<circle cx="10.5" cy="10.5" r="6.5"/><line x1="19" y1="19" x2="15.2" y2="15.2"/>',
    bell: '<path d="M6 10a6 6 0 0 1 12 0c0 4 1.5 5.5 1.5 5.5H4.5S6 14 6 10Z"/><path d="M10 19a2 2 0 0 0 4 0"/>',
    users: '<circle cx="9" cy="8" r="3.2"/><path d="M3.5 19c0-3 2.5-5.2 5.5-5.2s5.5 2.2 5.5 5.2"/><circle cx="17" cy="9" r="2.6"/><path d="M15.2 13.5c2.4.3 4.3 2.3 4.3 5"/>',
    warning: '<path d="M12 4 L22 20 L2 20 Z"/><line x1="12" y1="10" x2="12" y2="15"/><circle cx="12" cy="17.5" r="0.5" fill="currentColor" stroke="none"/>',
    info: '<circle cx="12" cy="12" r="9"/><line x1="12" y1="11" x2="12" y2="16"/><circle cx="12" cy="8" r="0.5" fill="currentColor" stroke="none"/>'
};

// Returns an inline <svg> string built to the shared standard. `size` must
// be one of the 4 allowed values; `name` must be a key in PATHS above.
export function icon(name, size = BASE_SIZE) {
    const path = PATHS[name];
    if (!path) throw new Error(`icons.js: unknown icon "${name}"`);
    if (!SIZES.includes(size)) throw new Error(`icons.js: size ${size} is not one of the 4 allowed sizes (${SIZES.join(", ")})`);

    const strokeWidth = (BASE_STROKE_WIDTH * (size / BASE_SIZE)).toFixed(2);

    return `<svg class="icon icon-${name}" width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="${strokeWidth}" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${path}</svg>`;
}
