// Pure, network-free helpers for supabase/functions/account-deletion-recovery
// — separated the same way supabase/functions/delete-account/lib.ts is,
// so index.test.ts can exercise this logic without Deno.serve/network/DB
// access.
//
// This function has no client-facing "user" at all — everything here
// exists to (a) gate the function itself behind a server-held secret,
// never a user's session, and (b) sanitize whatever Auth Admin API /
// Storage errors it sees before they ever touch account_deletion_jobs.last_error_code,
// the same "sanitized code only, never a raw exception message" posture
// supabase/functions/delete-account/lib.ts's DeleteAccountErrorCode
// already establishes for the user-facing function.

// Constant-time string comparison — deliberately not `a === b`, so
// comparing the caller-supplied secret against the real one does not
// leak how many leading characters matched via response-timing
// differences. Both inputs are hashed to a fixed length first via a
// simple, non-cryptographic per-byte XOR fold is NOT used here — this
// compares equal-length byte sequences directly and pads/rejects length
// mismatches without an early return, which is the actual timing-attack
// surface for a secret-comparison loop.
export function timingSafeEqual(a: string, b: string): boolean {
    const bytesA = new TextEncoder().encode(a);
    const bytesB = new TextEncoder().encode(b);

    // A length mismatch is itself safe to reveal immediately (it does
    // not narrow down any character of the real secret) — only the
    // per-byte comparison below needs to run in constant time once
    // lengths are known to match.
    if (bytesA.length !== bytesB.length) {
        return false;
    }

    let diff = 0;
    for (let i = 0; i < bytesA.length; i++) {
        diff |= bytesA[i] ^ bytesB[i];
    }
    return diff === 0;
}

// The one and only gate for this entire function — see index.ts's own
// header for why this is deliberately the sole authorization mechanism
// (no user JWT is ever involved). Fails closed on every ambiguous case:
// a missing configured secret (misconfigured deployment), a missing
// provided header, or an empty value of either, are all treated as
// unauthorized, never as "no check configured, allow through."
export function isAuthorizedRecoveryRequest(
    providedSecret: string | null,
    configuredSecret: string | undefined
): boolean {
    if (!configuredSecret || configuredSecret.length === 0) return false;
    if (!providedSecret || providedSecret.length === 0) return false;
    return timingSafeEqual(providedSecret, configuredSecret);
}

// Sanitized, enum-like error codes only — stored in
// account_deletion_jobs.last_error_code, mirroring
// delete-account/lib.ts's DeleteAccountErrorCode. Never the raw
// Auth Admin API / Storage error message, which could carry internal
// detail (request ids, backend hostnames, etc.) into a column with no
// access control beyond "service_role only," but which this function's
// own JSON response summary also never echoes verbatim either.
export type RecoveryErrorCode = "auth_admin_failed" | "storage_cleanup_partial" | "recovery_internal_error";

export function sanitizeRecoveryError(_error: unknown, fallback: RecoveryErrorCode): RecoveryErrorCode {
    // Deliberately ignores the actual error content for the STORED code
    // — only ever one of the fixed values above ever reaches the
    // database or this function's own summary response. The real
    // error is still passed to logInternal() by the caller (index.ts)
    // for server-side-only logs.
    return fallback;
}

// Best-effort classification of an Auth Admin API deleteUser() failure
// as "the user is already gone" (idempotent success — see this
// function's own index.ts header for why a recovery pass must treat a
// missing auth.users row as a success, not a failure) versus a genuine
// failure that should count against the job's bounded retry budget.
//
// NOT verified against a live Supabase project in this environment (no
// reachable instance — see this PR's own report for the disclosed
// limitation). Supabase's GoTrue Admin API is documented to return a
// 404-shaped error for an unknown user id; this checks both an explicit
// `status`/`code` of 404 and a case-insensitive "not found" in the
// message, so it degrades safely either way this actually renders in
// practice. If it never matches (message text differs from what this
// expects on the real deployed GoTrue version), the practical effect is
// only that a follow-up-of-a-follow-up deletion is retried a bounded
// number of extra times before landing in 'failed' for manual review —
// never silent data loss, never a false "success."
export function isUserAlreadyDeletedError(error: { message?: string; status?: number; code?: string } | null): boolean {
    if (!error) return false;
    if (error.status === 404) return true;
    if (error.code === "user_not_found") return true;
    const message = (error.message ?? "").toLowerCase();
    return message.includes("not found") || message.includes("does not exist");
}
