// The one shared "is this ?redirect= value safe to navigate to" check in
// this app — mirrors js/utils/safeUrl.js's exact reasoning (a single
// implementation two pages import, instead of two independently-
// maintained copies that could quietly drift apart) for a different
// threat: safeUrl.js decides whether an OUTBOUND link is a genuine
// http(s) URL; this decides whether a query-string value read back from
// this app's OWN address bar is a genuine same-origin, application-
// relative destination, not an open-redirect payload.
//
// Rule: reject anything that declares its own scheme ("https:",
// "javascript:", "mailto:", ...) up front, reject protocol-relative
// ("//host/...") and its backslash equivalent up front too (the WHATWG
// URL parser normalizes a leading backslash to "/" for http(s) bases,
// so "/\evil.com" is a real bypass attempt, not a typo) — then resolve
// against the current page's own URL and require the result to still be
// this exact origin. A same-origin absolute URL (typed out in full)
// still fails the scheme check above: this app's contract is
// "relative," not merely "happens to resolve same-origin."
export function getSafeRedirectTarget(rawValue, fallback) {
    if (typeof rawValue !== "string") return fallback;

    const candidate = rawValue.trim();
    if (!candidate) return fallback;

    if (/^[a-z][a-z0-9+.-]*:/i.test(candidate)) return fallback;

    if (candidate.startsWith("//") || candidate.startsWith("/\\") || candidate.startsWith("\\")) {
        return fallback;
    }

    let resolved;

    try {
        resolved = new URL(candidate, window.location.href);
    } catch {
        return fallback;
    }

    if (resolved.origin !== window.location.origin) return fallback;

    return resolved.pathname + resolved.search + resolved.hash;
}
