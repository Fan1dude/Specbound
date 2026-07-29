// Assembled skeleton-loading compositions — Milestone 10 brand refresh.
// See docs/milestones/MILESTONE_10_BRAND_REFRESH_ARCHITECTURE.md's Skeleton Loading
// section: css/components/skeleton.css already had the shimmer animation
// and atomic shape classes (skeleton-text/-title/-image/-avatar), but
// nothing assembled them into layouts matching this app's real content —
// several loading states fell back to a bare "Loading..." string instead.
// These functions are the assembly layer; callers pass the returned HTML
// straight into innerHTML, same pattern as every other render* helper in
// the app.
//
// Deliberately no inline style="width: ..." attributes anywhere below —
// width variation (so repeated lines don't look like identical duplicate
// bars) is done via :nth-child selectors in skeleton.css instead. An
// inline style attribute would be silently blocked under this app's CSP
// (confirmed the hard way earlier in this milestone — see
// js/utils/progressBar.js) if it ever needs to run with the real
// production _headers file rather than the permissive local dev server.

// Matches BlueprintCard's real layout (image, title, 2 text lines) so the
// loading and loaded states don't visually jump when content arrives.
// Used for feeds/grids and project/build card lists alike — one shared
// composition, not a separate one per page.
export function cardGridSkeleton(count = 6) {
    return Array.from({ length: count }, () => `
        <div class="card skeleton-card">
            <div class="skeleton skeleton-image"></div>
            <div class="skeleton-card-body">
                <div class="skeleton skeleton-title"></div>
                <div class="skeleton skeleton-text"></div>
                <div class="skeleton skeleton-text"></div>
            </div>
        </div>
    `).join("");
}

// A profile header: avatar, name, one bio line, a stats row.
export function profileSkeleton() {
    return `
        <div class="skeleton-profile">
            <div class="skeleton skeleton-avatar skeleton-avatar-lg"></div>
            <div class="skeleton-profile-body">
                <div class="skeleton skeleton-title skeleton-title-name"></div>
                <div class="skeleton skeleton-text"></div>
                <div class="skeleton-profile-stats">
                    <div class="skeleton skeleton-text"></div>
                    <div class="skeleton skeleton-text"></div>
                    <div class="skeleton skeleton-text"></div>
                </div>
            </div>
        </div>
    `;
}

// A repeated comment row: small avatar + two text lines of different
// widths (via CSS, see the file header), mimicking natural
// comment-length variation rather than two identical bars.
export function commentsSkeleton(count = 3) {
    return Array.from({ length: count }, () => `
        <div class="skeleton-row">
            <div class="skeleton skeleton-avatar skeleton-avatar-sm"></div>
            <div class="skeleton-row-body skeleton-row-body-comment">
                <div class="skeleton skeleton-text"></div>
                <div class="skeleton skeleton-text"></div>
            </div>
        </div>
    `).join("");
}

// Image-only tiles, for the editor's gallery grid — no title/text lines,
// since a gallery item is just an image.
export function imageGridSkeleton(count = 4) {
    return Array.from({ length: count }, () => `
        <div class="skeleton skeleton-image skeleton-gallery-tile"></div>
    `).join("");
}

// The simplest composition — a repeated avatar + single text line, for
// follower/following lists and notification rows.
export function listSkeleton(count = 4) {
    return Array.from({ length: count }, () => `
        <div class="skeleton-row">
            <div class="skeleton skeleton-avatar skeleton-avatar-sm"></div>
            <div class="skeleton-row-body">
                <div class="skeleton skeleton-text"></div>
            </div>
        </div>
    `).join("");
}
