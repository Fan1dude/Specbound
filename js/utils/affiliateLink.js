import { escapeHtml, escapeAttribute } from "./escapeHtml.js";
import { isSafeHttpUrl } from "./safeUrl.js";

// The exact, required visible text — not "Sponsored" or "Ad" (both too
// vague on their own, and this app may also show ordinary user-submitted
// links that happen to point at a retailer Specbound has an affiliate
// relationship with elsewhere, which must never be labeled this way).
export const AFFILIATE_LINK_LABEL_TEXT = "Affiliate link";

let labelIdCounter = 0;

// Single shared way to render an outbound link, matching this app's
// existing external-link convention (target="_blank" rel="noopener
// noreferrer" -- see renderResources.js/renderSetupInventory.js) with one
// addition: an explicit, opt-in affiliate disclosure.
//
// isAffiliate must be set true ONLY for a link Specbound itself controls
// and has actually enrolled in an affiliate program (e.g. a real, approved
// Amazon Associates link). Never derive it from the URL itself (matching
// against "amazon.com" or similar) -- this app can also contain ordinary
// user-submitted Amazon links (resources, setup-inventory product links)
// that are not Specbound's own affiliate links, and mislabeling those
// would be its own compliance problem. The caller — the one place that
// actually knows whether a given link is a real, enrolled affiliate link —
// makes that call explicitly, once, at render time.
//
// When isAffiliate is true, a visible "Affiliate link" label renders next
// to the anchor (not inside it, so the link's own accessible name/visible
// text is never changed by this) and is tied to it via aria-describedby,
// so the disclosure reaches screen-reader users too, not only sighted
// ones, and works without a hover or tooltip -- required by the Amazon
// Associates Operating Agreement's "clear and conspicuous" disclosure
// rule. See loadFooter() in js/core/layout.js for the required sitewide
// "As an Amazon Associate..." disclosure sentence this label complements.
//
// HTML-attribute escaping (escapeAttribute() above) only stops markup
// injection -- it does nothing to stop a syntactically-valid
// javascript:/data: URL from becoming a live, clickable href, since
// neither scheme needs a quote or angle bracket to work. isSafeHttpUrl()
// (js/utils/safeUrl.js -- the same check js/services/productMetadata.js
// uses) is checked first and independently of escaping, not as a
// substitute for it. A URL that fails this check is never turned into an
// <a> at all: this function neutralizes it by rendering the (still
// escaped) text as plain, non-interactive content instead -- no href to
// click, nothing to disclose, so no affiliate label either, regardless of
// what isAffiliate was passed.
export function renderExternalLink({ url, text, className = "", isAffiliate = false }) {
    const linkText = escapeHtml(text);
    const classAttr = className ? ` class="${escapeAttribute(className)}"` : "";

    if (!isSafeHttpUrl(url)) {
        const unsafeClass = className ? `${className} external-link-unsafe` : "external-link-unsafe";
        return `<span class="${escapeAttribute(unsafeClass)}">${linkText}</span>`;
    }

    const href = escapeAttribute(url);

    if (!isAffiliate) {
        return `<a${classAttr} href="${href}" target="_blank" rel="noopener noreferrer">${linkText}</a>`;
    }

    const labelId = `affiliateLinkLabel${++labelIdCounter}`;

    return (
        `<span class="affiliate-link">` +
            `<a${classAttr} href="${href}" target="_blank" rel="noopener noreferrer" aria-describedby="${labelId}">${linkText}</a>` +
            `<span class="affiliate-link-label" id="${labelId}">${escapeHtml(AFFILIATE_LINK_LABEL_TEXT)}</span>` +
        `</span>`
    );
}
