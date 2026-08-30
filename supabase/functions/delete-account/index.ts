// supabase/functions/delete-account
//
// Self-service account deletion — the orchestration half. The
// transactional database work happens entirely inside
// public.self_delete_account(uuid) (migration 0049, replacing 0048's
// zero-argument version); this function's job is everything that RPC
// cannot do itself: verify the caller, request a short-lived deletion
// challenge, consume it via the RPC, then call Supabase Auth's Admin
// API (service-role only — never reachable from browser code) to
// actually remove the auth.users row, then best-effort clean up
// Storage. See docs/OPERATIONS.md §10.7/§10.8/§10.11/§10.14 for the
// underlying non-atomicity/recovery reasoning this function's
// sequencing mirrors.
//
// Security-review note: recent password reauthentication is verified
// entirely server-side in Postgres — request_account_deletion_challenge()
// (0049) checks the caller's own auth.jwt() -> 'amr' claim for a
// `password` entry within the last 5 minutes, a signal Supabase's own
// refresh-token grant does not touch (unlike the JWT's top-level `iat`,
// which DOES advance on every routine token refresh and was
// insufficient — see 0049's own header). This function does not decode
// or inspect the JWT for freshness at all; it only forwards the
// caller's own authenticated context to the two RPCs below, which do
// the real verification.
//
// Never exposes: the service-role key itself (read once from
// Deno.env, never echoed anywhere), legal-hold status or existence
// (self_delete_account() already collapses that into the same generic
// error every other failure produces), raw database/Storage/Auth error
// text (every failure surfaces one of lib.ts's sanitized
// DeleteAccountErrorCode values only), or any detail about a user other
// than the verified caller.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { errorResponseBody, removeStoragePathsIndividually, type DeleteAccountErrorCode } from "./lib.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
// Never SUPABASE_SERVICE_ROLE_KEY by any other name, never hardcoded,
// never logged, never returned in any response — read once, used only
// to construct adminClient below, which never leaves this server-side
// runtime.
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const PROJECT_IMAGES_BUCKET = "project-images";

const CORS_HEADERS = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type"
};

function jsonResponse(body: unknown, status = 200): Response {
    return new Response(JSON.stringify(body), {
        status,
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" }
    });
}

function fail(code: DeleteAccountErrorCode, status: number): Response {
    return jsonResponse(errorResponseBody(code), status);
}

// Every internal exception is logged server-side only (hostname-style
// safe logging, matching product-metadata/index.ts's own
// logOutcome() convention) — never echoed to the client, which only
// ever receives one of lib.ts's sanitized codes.
function logInternal(stage: string, error: unknown) {
    console.error(`delete-account: ${stage} failed:`, error);
}

// Records an Auth-deletion outcome via record_account_deletion_auth_result()
// (0050) — the same service-role-only RPC the account-deletion-recovery
// worker uses for its own retries, so a job's state transitions happen
// through exactly one code path regardless of which caller drove them.
// Never throws — a failure to update job bookkeeping must never mask or
// override the actual deletion outcome it's trying to record.
async function recordAuthResult(
    adminClient: ReturnType<typeof createClient>,
    jobId: string,
    success: boolean,
    errorCode: string | null
) {
    try {
        const { error } = await adminClient.rpc("record_account_deletion_auth_result", {
            p_job_id: jobId,
            p_success: success,
            p_error_code: errorCode
        });
        if (error) logInternal("record_account_deletion_auth_result", error);
    } catch (error) {
        logInternal("record_account_deletion_auth_result", error);
    }
}

// Records a Storage-cleanup outcome via
// record_account_deletion_storage_result() (0050) — `remainingPaths` is
// the full set still outstanding after this attempt, not a delta; the
// RPC only marks the job complete when this is empty, and only
// increments storage_cleanup_attempts here, never anywhere else. Never
// throws, for the same reason as recordAuthResult() above.
async function recordStorageResult(
    adminClient: ReturnType<typeof createClient>,
    jobId: string,
    remainingPaths: string[],
    errorCode: string | null
) {
    try {
        const { error } = await adminClient.rpc("record_account_deletion_storage_result", {
            p_job_id: jobId,
            p_remaining_paths: remainingPaths,
            p_error_code: errorCode
        });
        if (error) logInternal("record_account_deletion_storage_result", error);
    } catch (error) {
        logInternal("record_account_deletion_storage_result", error);
    }
}

Deno.serve(async req => {
    if (req.method === "OPTIONS") {
        return new Response(null, { headers: CORS_HEADERS });
    }

    if (req.method !== "POST") {
        return fail("invalid_method", 405);
    }

    // Auth required — verified against the request's own JWT, never a
    // target id from the request body. There is no request-body field
    // anywhere in this function that could name a different user.
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
        return fail("auth_required", 401);
    }

    // User-authenticated client — carries the caller's own JWT, so
    // auth.uid() (and auth.jwt(), for the challenge RPC's own amr
    // check) resolve correctly inside both RPCs below, and their
    // security model (SECURITY DEFINER, deriving the target exclusively
    // from auth.uid()) applies exactly as it does for any other
    // authenticated client call. This client is never used for anything
    // requiring elevated privilege — see adminClient below for that.
    const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
        global: { headers: { Authorization: authHeader } }
    });

    const { data: userData, error: authError } = await userClient.auth.getUser();
    if (authError || !userData?.user) {
        return fail("auth_required", 401);
    }

    const userId = userData.user.id;

    // Recent reauthentication — enforced entirely server-side in
    // Postgres, against the caller's own verified `auth.jwt() -> 'amr'`
    // claim (0049_account_deletion_challenge.sql), never a client-
    // supplied flag and never a JWT field this function inspects
    // itself. The client is expected to have called
    // supabase.auth.signInWithPassword() immediately before this
    // request; if it didn't (or only a routinely-refreshed session is
    // presented), this RPC rejects outright regardless of what the
    // client claims — see this function's own header.
    let challengeToken: string;

    try {
        const { data, error } = await userClient.rpc("request_account_deletion_challenge");

        if (error) {
            logInternal("request_account_deletion_challenge", error);
            return fail("reauth_required", 401);
        }

        if (typeof data !== "string") {
            logInternal("request_account_deletion_challenge", new Error("missing/invalid token in response"));
            return fail("reauth_required", 401);
        }

        challengeToken = data;
    } catch (error) {
        logInternal("request_account_deletion_challenge", error);
        return fail("reauth_required", 401);
    }

    // Service-role client — constructed once, used only for the two
    // steps that genuinely require it (Auth Admin API, job-row updates
    // after this point, and Storage cleanup once the user's own session
    // is no longer reliable). Never receives the caller's own JWT.
    const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // --- Step 1: database preparation (transactional, inside the RPC) ---
    // Passes the just-issued challenge token, consumed atomically inside
    // this same RPC call (0049) before any other work happens — a
    // missing/expired/foreign/already-used token is rejected identically
    // to any other db_prep_failed cause here, never distinguished.
    let jobId: string;
    let storagePaths: string[];

    try {
        const { data, error } = await userClient.rpc("self_delete_account", {
            p_challenge_token: challengeToken
        });

        if (error) {
            logInternal("self_delete_account", error);
            return fail("db_prep_failed", 500);
        }

        const row = Array.isArray(data) ? data[0] : data;
        if (!row?.job_id) {
            logInternal("self_delete_account", new Error("missing job_id in response"));
            return fail("db_prep_failed", 500);
        }

        jobId = row.job_id;
        storagePaths = Array.isArray(row.storage_paths) ? row.storage_paths : [];
    } catch (error) {
        logInternal("self_delete_account", error);
        return fail("db_prep_failed", 500);
    }

    // --- Step 2: Auth Admin deletion — irreversible, the point of no ---
    // --- return. Only reached after step 1 has genuinely committed. ---
    try {
        const { error } = await adminClient.auth.admin.deleteUser(userId);

        if (error) {
            logInternal("admin.deleteUser", error);
            // record_account_deletion_auth_result() (0050) leaves the
            // job in 'db_prepared' with recovery_attempts incremented
            // (moving to 'failed' only once its own bound is reached) —
            // this function's own first attempt counts as attempt 1 of
            // that same bound, not a separate, uncounted try. The
            // database side already committed and is safely retryable
            // (self_delete_account() resolves to the same job row on a
            // second call, per 0049's own header) — the caller's session
            // is still valid at this point, since Auth deletion did not
            // succeed, so a retry from the client is a legitimate
            // recovery path, not a dead end; the account-deletion-
            // recovery worker (0050) is a second, independent path that
            // does not require the client to retry at all. A client
            // retry will request and consume a fresh challenge token
            // (the one used here is already gone) — that's expected, not
            // a problem, since the underlying account still exists and a
            // fresh `amr` password entry is still required either way.
            await recordAuthResult(adminClient, jobId, false, "auth_admin_failed");
            return fail("auth_admin_failed", 500);
        }
    } catch (error) {
        logInternal("admin.deleteUser", error);
        await recordAuthResult(adminClient, jobId, false, "auth_admin_failed");
        return fail("auth_admin_failed", 500);
    }

    await recordAuthResult(adminClient, jobId, true, null);

    // --- Step 3: Storage cleanup — best-effort, never blocks or ---
    // --- reverses the deletion above, which has already succeeded. ---
    // Removes each path individually (removeStoragePathsIndividually(),
    // lib.ts) so one bad path cannot make every OTHER path look like it
    // also failed, then records ONLY the genuinely still-outstanding
    // remainder — record_account_deletion_storage_result() (0050) is
    // what decides whether the job is actually complete, never this
    // function directly, and it only reaches 'storage_cleaned' when that
    // remainder is empty. If anything remains, the job stays in
    // 'auth_deleted' and account-deletion-recovery (0050) will retry it
    // on its own schedule — this function does not loop or block on
    // that itself, matching its own "best-effort, never blocks" success
    // response below.
    let remainingPaths: string[] = [];
    let storageErrorCode: string | null = null;

    if (storagePaths.length > 0) {
        const outcome = await removeStoragePathsIndividually(
            adminClient.storage,
            PROJECT_IMAGES_BUCKET,
            storagePaths
        );
        remainingPaths = outcome.remainingPaths;
        if (remainingPaths.length > 0) {
            logInternal("storage.remove", new Error(`${remainingPaths.length} path(s) still outstanding`));
            storageErrorCode = "storage_cleanup_partial";
        }
    }

    await recordStorageResult(adminClient, jobId, remainingPaths, storageErrorCode);

    // Success is reported once Auth deletion has succeeded, regardless
    // of Storage outcome — an orphaned Storage object is a disclosed,
    // low-severity, already-accepted limitation elsewhere in this
    // codebase (0043_delete_build.sql's identical posture), never a
    // reason to tell the user their account deletion failed when it
    // did not.
    return jsonResponse({ success: true });
});
