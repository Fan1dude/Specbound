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
    info: '<circle cx="12" cy="12" r="9"/><line x1="12" y1="11" x2="12" y2="16"/><circle cx="12" cy="8" r="0.5" fill="currentColor" stroke="none"/>',

    // Milestone 20 (Builder Portfolio) additions — see
    // docs/milestones/MILESTONE_20_BUILDER_PORTFOLIO_SPECIFICATION.md §10.3.
    // "github" is a generic code-brackets mark, not the Octocat logo —
    // deliberately not a trademarked glyph, same reasoning as every other
    // icon here (geometric, stroke-based, no borrowed brand marks).
    link: '<path d="M10 13a5 5 0 0 0 7.54.54l2-2a5 5 0 0 0-7.07-7.07l-1.5 1.5"/><path d="M14 11a5 5 0 0 0-7.54-.54l-2 2a5 5 0 0 0 7.07 7.07l1.5-1.5"/>',
    github: '<polyline points="9 8 5 12 9 16"/><polyline points="15 8 19 12 15 16"/>',
    "location-pin": '<path d="M12 21s7-7.58 7-12a7 7 0 0 0-14 0c0 4.42 7 12 7 12Z"/><circle cx="12" cy="9" r="2.5"/>',
    calendar: '<rect x="4" y="5" width="16" height="16" rx="2"/><line x1="4" y1="10" x2="20" y2="10"/><line x1="8" y1="3" x2="8" y2="7"/><line x1="16" y1="3" x2="16" y2="7"/>',
    milestone: '<line x1="6" y1="21" x2="6" y2="4"/><path d="M6 5h11l-3 4 3 4H6"/>',
    "arrow-up-right": '<line x1="7" y1="17" x2="17" y2="7"/><polyline points="9 7 17 7 17 15"/>',

    // Milestone 22 (Community Foundation) addition — see
    // docs/milestones/MILESTONE_22_COMMUNITY_FOUNDATION_SPECIFICATION.md.
    // A generic speech-bubble mark for "connected chat community," not
    // Discord's logo — same "geometric, stroke-based, no borrowed brand
    // marks" rule "github" above already follows.
    discord: '<path d="M5 6h14a2 2 0 0 1 2 2v7a2 2 0 0 1-2 2h-9l-4 4v-4H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2Z"/>',

    // Connected Accounts redesign — a three-dot overflow-menu trigger.
    // Filled dots (stroke="none"), same sub-pattern the decorative dots
    // in "warning"/"info" above already use, since a kebab glyph reads
    // as three solid points, not three stroked rings.
    more: '<circle cx="5" cy="12" r="1.6" fill="currentColor" stroke="none"/><circle cx="12" cy="12" r="1.6" fill="currentColor" stroke="none"/><circle cx="19" cy="12" r="1.6" fill="currentColor" stroke="none"/>',

    // Milestone 23 (Setup Inventory) additions — keyboard-accessible
    // move-up/move-down/delete controls for category and product
    // reordering (explicit requirement: drag-and-drop must not be the
    // only reordering method). "chevron-up" mirrors "chevron-down"
    // exactly (same polyline, flipped vertically) rather than a CSS
    // transform on the existing icon, so both remain plain, cacheable,
    // orientation-explicit glyphs.
    "chevron-up": '<polyline points="6 15 12 9 18 15"/>',
    trash: '<path d="M4 7h16"/><path d="M9 7V4h6v3"/><path d="M6 7l1 13a2 2 0 0 0 2 2h6a2 2 0 0 0 2-2l1-13"/><line x1="10" y1="11" x2="10" y2="17"/><line x1="14" y1="11" x2="14" y2="17"/>'
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
