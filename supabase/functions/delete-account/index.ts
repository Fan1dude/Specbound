// supabase/functions/delete-account
//
// Self-service account deletion — the orchestration half. The
// transactional database work happens entirely inside
// public.self_delete_account() (migration 0048); this function's job is
// everything that RPC cannot do itself: verify the caller, enforce
// recent reauthentication, call it, then call Supabase Auth's Admin API
// (service-role only — never reachable from browser code) to actually
// remove the auth.users row, then best-effort clean up Storage. See
// docs/OPERATIONS.md §10.7/§10.8/§10.11/§10.14 for the underlying
// non-atomicity/recovery reasoning this function's sequencing mirrors.
//
// Never exposes: the service-role key itself (read once from
// Deno.env, never echoed anywhere), legal-hold status or existence
// (self_delete_account() already collapses that into the same generic
// error every other failure produces), raw database/Storage/Auth error
// text (every failure surfaces one of lib.ts's sanitized
// DeleteAccountErrorCode values only), or any detail about a user other
// than the verified caller.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { errorResponseBody, isRecentlyAuthenticated, type DeleteAccountErrorCode } from "./lib.ts";

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

// Updates the durable job row via the service-role client, which
// bypasses RLS by Supabase's own default posture for that role —
// account_deletion_jobs has zero client policies (0047), so this is the
// only way any of these updates can happen at all. Never throws — a
// failure to update job bookkeeping must never mask or override the
// actual deletion outcome it's trying to record.
async function updateJob(
    adminClient: ReturnType<typeof createClient>,
    jobId: string,
    fields: Record<string, unknown>
) {
    try {
        await adminClient.from("account_deletion_jobs").update(fields).eq("id", jobId);
    } catch (error) {
        logInternal("updateJob", error);
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

    const jwt = authHeader.replace(/^Bearer\s+/i, "");

    // User-authenticated client — carries the caller's own JWT, so
    // auth.uid() resolves correctly inside self_delete_account() and
    // that RPC's own security model (SECURITY DEFINER, deriving the
    // target exclusively from auth.uid()) applies exactly as it does
    // for any other authenticated client call. This client is never
    // used for anything requiring elevated privilege — see adminClient
    // below for that.
    const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
        global: { headers: { Authorization: authHeader } }
    });

    const { data: userData, error: authError } = await userClient.auth.getUser();
    if (authError || !userData?.user) {
        return fail("auth_required", 401);
    }

    const userId = userData.user.id;

    // Recent reauthentication — enforced server-side against the
    // verified token's own `iat` claim (lib.ts), never a client-supplied
    // flag. The client is expected to have called
    // supabase.auth.signInWithPassword() immediately before this
    // request, which mints a fresh access token; if it didn't (or an
    // old token is replayed), this rejects outright regardless of what
    // the client claims.
    if (!isRecentlyAuthenticated(jwt)) {
        return fail("reauth_required", 401);
    }

    // Service-role client — constructed once, used only for the two
    // steps that genuinely require it (Auth Admin API, job-row updates
    // after this point, and Storage cleanup once the user's own session
    // is no longer reliable). Never receives the caller's own JWT.
    const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // --- Step 1: database preparation (transactional, inside the RPC) ---
    let jobId: string;
    let storagePaths: string[];

    try {
        const { data, error } = await userClient.rpc("self_delete_account");

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
            await updateJob(adminClient, jobId, {
                state: "failed",
                last_error_code: "auth_admin_failed"
            });
            // The database side already committed and is safely
            // retryable (self_delete_account() resolves to the same job
            // row on a second call, per 0048's own header) — the
            // caller's session is still valid at this point, since Auth
            // deletion did not succeed, so a retry from the client is a
            // legitimate recovery path, not a dead end.
            return fail("auth_admin_failed", 500);
        }
    } catch (error) {
        logInternal("admin.deleteUser", error);
        await updateJob(adminClient, jobId, {
            state: "failed",
            last_error_code: "auth_admin_failed"
        });
        return fail("auth_admin_failed", 500);
    }

    await updateJob(adminClient, jobId, { state: "auth_deleted" });

    // --- Step 3: Storage cleanup — best-effort, never blocks or ---
    // --- reverses the deletion above, which has already succeeded. ---
    let storageErrorCode: string | null = null;

    if (storagePaths.length > 0) {
        try {
            const { error } = await adminClient.storage.from(PROJECT_IMAGES_BUCKET).remove(storagePaths);
            if (error) {
                logInternal("storage.remove", error);
                storageErrorCode = "storage_cleanup_partial";
            }
        } catch (error) {
            logInternal("storage.remove", error);
            storageErrorCode = "storage_cleanup_partial";
        }
    }

    await updateJob(adminClient, jobId, {
        state: "storage_cleaned",
        last_error_code: storageErrorCode,
        storage_cleanup_attempts: 1,
        completed_at: new Date().toISOString()
    });

    // Success is reported once Auth deletion has succeeded, regardless
    // of Storage outcome — an orphaned Storage object is a disclosed,
    // low-severity, already-accepted limitation elsewhere in this
    // codebase (0043_delete_build.sql's identical posture), never a
    // reason to tell the user their account deletion failed when it
    // did not.
    return jsonResponse({ success: true });
});
