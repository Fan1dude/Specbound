// Pure, network-free helpers for supabase/functions/delete-account —
// separated from index.ts the same way product-metadata/lib.ts is, so
// index.test.ts can exercise this logic without Deno.serve/network/DB
// access.
//
// Security-review note (see this function's own history): recent
// password reauthentication is NOT checked here, and never was checked
// correctly via a JWT `iat` (issued-at) claim — Supabase's own
// refresh-token grant mints a new access token, with a new `iat`,
// WITHOUT re-verifying the password at all. The actual, GoTrue-native
// signal (the `amr` claim's per-method timestamp, which a token refresh
// does not touch for the `password` method) is checked entirely
// server-side in Postgres, via `auth.jwt() -> 'amr'` inside
// `request_account_deletion_challenge()`
// (supabase/migrations/0049_account_deletion_challenge.sql) — not here,
// and not by decoding the JWT in this Edge Function at all. This file
// intentionally contains no JWT-decoding or freshness logic; see
// index.ts for the two-RPC-call flow that replaces it.

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
