// Pure, network-free helpers for supabase/functions/delete-account —
// separated from index.ts the same way product-metadata/lib.ts is, so
// index.test.ts can exercise this logic without Deno.serve/network/DB
// access.

// Decodes a JWT's payload segment ONLY — this is never used as a
// substitute for signature verification. By the time this is called,
// the token has already been cryptographically verified by Supabase
// Auth itself (via supabaseClient.auth.getUser(), which round-trips to
// Supabase's own verification endpoint) — this function exists purely
// to read the `iat` claim out of an already-verified-valid token, so
// the server can independently enforce how recently it was issued
// (see requireRecentAuthentication below). Never trust a value decoded
// here from an unverified token.
export function decodeJwtPayload(jwt: string): Record<string, unknown> | null {
    const parts = jwt.split(".");
    if (parts.length !== 3) return null;

    try {
        const base64url = parts[1].replace(/-/g, "+").replace(/_/g, "/");
        const padded = base64url + "=".repeat((4 - (base64url.length % 4)) % 4);
        const json = atob(padded);
        const parsed = JSON.parse(json);
        return typeof parsed === "object" && parsed !== null ? parsed : null;
    } catch {
        return null;
    }
}

// Server-side enforcement of "recent authentication" — never trusts a
// client-side claim that password reauthentication happened. The
// client re-authenticates via supabase.auth.signInWithPassword()
// immediately before calling this function, which mints a genuinely
// fresh session/access token; this checks that FRESH token's own `iat`
// (issued-at) claim is actually recent, independent of anything the
// client asserts. A caller that skips reauthentication and sends an
// old, otherwise-still-valid access token is rejected here, not merely
// discouraged by client-side UI.
export const MAX_REAUTH_AGE_SECONDS = 300; // 5 minutes

export function isRecentlyAuthenticated(jwt: string, nowSeconds: number = Math.floor(Date.now() / 1000)): boolean {
    const payload = decodeJwtPayload(jwt);
    const iat = payload?.iat;

    if (typeof iat !== "number") return false;

    return nowSeconds - iat <= MAX_REAUTH_AGE_SECONDS && nowSeconds - iat >= 0;
}

// Sanitized, enum-like error codes only — never a raw exception
// message, which could carry internal Postgres/Storage/Auth detail.
// Mirrors the reason-code pattern js/services/productMetadata.js's
// REASON_MESSAGES already establishes client-side for a different
// function.
export type DeleteAccountErrorCode =
    | "auth_required"
    | "reauth_required"
    | "invalid_method"
    | "db_prep_failed"
    | "auth_admin_failed"
    | "internal_error";

export function errorResponseBody(code: DeleteAccountErrorCode) {
    return { error: code };
}
