// The one shared "is this safe to treat as an outbound http(s) link"
// check in this app. Matches the exact rule js/services/productMetadata.js
// established for link-assisted product entry (Milestone 23 spec §5.2,
// steps 1-2) -- extracted here so both that file and
// js/utils/affiliateLink.js reference a single implementation instead of
// two independently-maintained copies that could quietly drift apart.
//
// Rule: must parse as an absolute URL (the URL constructor throws on
// anything relative, including a bare protocol-relative "//host/path" --
// no base is ever passed here, so that string is rejected the same way a
// malformed one is, not silently treated as https:), and its scheme must
// be exactly "http:" or "https:". This rejects javascript:, data:,
// mailto:, vbscript:, file:, and every other scheme -- HTML-attribute
// escaping alone (escapeAttribute() in escapeHtml.js) only stops markup
// injection; it does nothing to stop a syntactically-valid javascript:/
// data: URL from ending up as a live, clickable href.
export function isSafeHttpUrl(url) {
    let parsed;

    try {
        parsed = new URL(url);
    } catch {
        return false;
    }

    return parsed.protocol === "http:" || parsed.protocol === "https:";
}
