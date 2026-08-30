// Pure, network-free helpers for supabase/functions/delete-account —
// separated from index.ts the same way product-metadata/lib.ts is, so
// index.test.ts can exercise this logic without Deno.serve/network/DB
// access. Also imported by supabase/functions/account-deletion-recovery,
// which must retry the exact same Storage-removal logic this function's
// own first attempt uses — duplicating it in two places would let the
// two paths drift out of sync (e.g. one path counting a "not found"
// object as success and the other not), so it is written once here.
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

// Minimal shape of the two Supabase client surfaces this helper touches
// — kept intentionally narrow (not the real supabase-js types) so
// index.test.ts can pass a plain mock object without importing the real
// client, matching this file's own "network-free" test contract.
export interface StorageRemoveResult {
    error: { message?: string; status?: number } | null;
}

export interface StorageBucketClient {
    remove(paths: string[]): Promise<StorageRemoveResult>;
}

export interface StorageClientLike {
    from(bucket: string): StorageBucketClient;
}

export interface StorageCleanupOutcome {
    // Paths confirmed removed (or confirmed already gone) this attempt —
    // never re-attempted by a later retry.
    succeededPaths: string[];
    // Paths that still need to be retried — this is what a caller must
    // persist as the job's new storage_paths, NOT the original full
    // list, and NOT an empty array unless this is itself empty.
    remainingPaths: string[];
}

// Object-storage delete is conventionally idempotent at the backend
// level (removing a key that is already gone is not an error for most
// S3-compatible backends, Supabase Storage included) — but this
// function does not assume that silently. Per-path removal reports each
// path's outcome individually, on the honest assumption that
// `storage.from(bucket).remove([path])` returning no `error` means that
// one path is now confirmed absent (whether it was actually removed
// just now or was already gone), and any `error` means the path must be
// retried later. This has not been verified against a live Supabase
// Storage instance in this environment (no reachable project) — see
// this repository's own PR history for that disclosed limitation; if a
// live check later shows Storage returns an `error` for an
// already-missing object instead of silent success, this function's
// per-path try/catch already treats that as "still remaining" (safe:
// over-retries a no-op, never silently drops a real failure).
//
// Removed one path at a time, not as a single batched call, specifically
// so ONE bad path (already gone in an unexpected way, a transient
// per-object error, a path with characters the backend rejects) cannot
// cause the whole batch to be reported as failed and block progress on
// every OTHER path that would have succeeded — the exact "Preserve
// paths that still failed instead of marking the entire job complete"
// requirement this helper exists to satisfy.
export async function removeStoragePathsIndividually(
    storageClient: StorageClientLike,
    bucket: string,
    paths: string[]
): Promise<StorageCleanupOutcome> {
    const succeededPaths: string[] = [];
    const remainingPaths: string[] = [];

    for (const path of paths) {
        try {
            const { error } = await storageClient.from(bucket).remove([path]);
            if (error) {
                remainingPaths.push(path);
            } else {
                succeededPaths.push(path);
            }
        } catch {
            // A thrown network/client error is treated identically to a
            // returned `error` — still remaining, safe to retry later.
            remainingPaths.push(path);
        }
    }

    return { succeededPaths, remainingPaths };
}
