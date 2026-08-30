// supabase/functions/account-deletion-recovery
//
// Restricted, server-only worker that resumes unfinished
// public.account_deletion_jobs rows (0047) after the original
// delete-account Edge Function can no longer touch them — specifically
// the case its own header discloses as a real, previously-unaddressed
// gap: once auth.admin.deleteUser() has succeeded, the former user has
// no valid session, so delete-account can never be invoked again on
// their behalf to finish (or retry) Storage cleanup, or to retry Auth
// deletion itself if that step failed. This function exists ONLY to
// close that gap — it does nothing a normal user's session could ever
// trigger, and is never reachable through one.
//
// --- Security boundary, read this before changing anything below ---
//
// There is no concept of "the caller" here at all — this function is
// never invoked with a user's JWT, never calls userClient.auth.getUser(),
// and never derives anything from auth.uid(). The ONLY question this
// function's own authorization check answers is "does the caller know
// ACCOUNT_DELETION_RECOVERY_SECRET" — a long, random value set once via
// `supabase secrets set ACCOUNT_DELETION_RECOVERY_SECRET=<value>
// --project-ref <project-ref>` (see docs/DEPLOYMENT.md §8.2), read here
// only from Deno.env, compared in constant time
// (isAuthorizedRecoveryRequest(), lib.ts) against the `x-recovery-secret`
// request header, and never logged or echoed anywhere. A request
// missing that header, or presenting the wrong value, is rejected with a
// generic 401 before a single database call is made — including before
// the service-role client is even constructed.
//
// This is deliberately the ONLY gate, not a second layer on top of
// Supabase's normal `verify_jwt` Edge Function setting: this function's
// own supabase/config.toml entry sets `verify_jwt = false`, because
// requiring a valid Supabase Auth JWT here would be both unnecessary
// (this secret is a strictly stronger check — nothing about being a
// signed-in user, of any role, grants access) and actively misleading —
// it would suggest a signed-in user's session is a relevant credential
// for this function, when it is not.
//
// Underneath this function's own gate, `claim_account_deletion_jobs()`
// and `record_account_deletion_auth_result()`/
// `record_account_deletion_storage_result()` (all supabase/migrations/
// 0050_account_deletion_recovery.sql) are themselves granted EXECUTE
// only to the `service_role` Postgres role — `revoke all ... from
// public` first, matching every other privileged function in this
// codebase. Even if this Edge Function's own secret check were somehow
// bypassed, an ordinary `anon`/`authenticated` PostgREST caller still
// could not invoke those RPCs directly: permission denied at the
// database level, a second, independent boundary below the first.
//
// --- Invocation / scheduling ---
//
// Not invoked by any browser code, and not linked from anywhere in
// js/. Intended to run on an operator-controlled schedule, not
// on-demand from user activity. Two supported ways to trigger it, both
// documented in full in docs/DEPLOYMENT.md §8.2:
//
//   1. Supabase's own scheduled Cron (Postgres `pg_cron` + `pg_net`,
//      configured once in the Supabase dashboard's Database > Cron
//      Jobs, or via a migration using `cron.schedule()`), calling this
//      function's deployed URL via `net.http_post()` with the
//      `x-recovery-secret` header sourced from Supabase Vault — never
//      hardcoded into the scheduled job definition itself.
//   2. A manual, operator-run invocation (e.g. from a trusted machine,
//      never from this repository's own client code) — a `curl` command
//      with the secret entered directly at the command line, the same
//      "never through an intermediate file" posture docs/DEPLOYMENT.md
//      already requires for the service-role key itself.
//
// Safe to invoke concurrently or more often than scheduled — every unit
// of work is claimed via `FOR UPDATE SKIP LOCKED` (0050's own header),
// so two overlapping runs can never process the same job.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { removeStoragePathsIndividually } from "../delete-account/lib.ts";
import { isAuthorizedRecoveryRequest, isUserAlreadyDeletedError, sanitizeRecoveryError } from "./lib.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
// Never SUPABASE_SERVICE_ROLE_KEY by any other name, never hardcoded,
// never logged, never returned in any response — same posture as
// supabase/functions/delete-account/index.ts's own adminClient.
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
// The one secret that gates this entire function — see this file's own
// header. Read once; never included in any response body or log line.
const RECOVERY_SECRET = Deno.env.get("ACCOUNT_DELETION_RECOVERY_SECRET");

const PROJECT_IMAGES_BUCKET = "project-images";

// Bounded, small batch per invocation — a scheduled run that finds more
// work than this simply leaves the remainder for its next scheduled
// firing (or a concurrent run, safely, per the claim mechanism above)
// rather than this single invocation trying to process an unbounded
// number of jobs against Edge Function execution time limits.
const JOBS_PER_RUN = 10;
// A claim older than this is treated as an abandoned worker (crashed or
// timed out mid-job) and becomes reclaimable by anyone — see 0050's own
// header for why this is a lease, not the actual concurrency guarantee.
const LEASE_SECONDS = 120;
// Shared bound for both the Auth-phase (recovery_attempts) and
// Storage-phase (storage_cleanup_attempts) retry counters — a job that
// exhausts either moves to 'failed' (0047's existing "requires manual
// attention" terminal state), never retried forever.
const MAX_ATTEMPTS = 20;

interface AccountDeletionJob {
    id: string;
    former_user_id: string;
    state: string;
    storage_paths: string[];
}

function logInternal(stage: string, error: unknown) {
    console.error(`account-deletion-recovery: ${stage} failed:`, error);
}

function jsonResponse(body: unknown, status = 200): Response {
    return new Response(JSON.stringify(body), {
        status,
        headers: { "Content-Type": "application/json" }
    });
}

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
            p_error_code: errorCode,
            p_max_attempts: MAX_ATTEMPTS
        });
        if (error) logInternal("record_account_deletion_auth_result", error);
    } catch (error) {
        logInternal("record_account_deletion_auth_result", error);
    }
}

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
            p_error_code: errorCode,
            p_max_attempts: MAX_ATTEMPTS
        });
        if (error) logInternal("record_account_deletion_storage_result", error);
    } catch (error) {
        logInternal("record_account_deletion_storage_result", error);
    }
}

// One claimed job's worth of work — the Auth-deletion retry for a
// 'db_prepared' job, OR the Storage-cleanup retry for an 'auth_deleted'
// job (claim_account_deletion_jobs() never returns any other state, see
// 0050's own header). Deliberately does NOT chain from one phase into
// the other within a single pass, even for a job whose Auth deletion
// this same invocation just completed — record_account_deletion_auth_result()
// clears the claim as part of recording success, so continuing to treat
// this invocation as still "holding" the job past that point would be
// exactly the kind of unguarded concurrent access the claim mechanism
// exists to prevent. The job simply becomes claimable again (by this
// same worker's next batch iteration, or a concurrent one, or the next
// scheduled run) in its new 'auth_deleted' state.
async function processJob(adminClient: ReturnType<typeof createClient>, job: AccountDeletionJob) {
    if (job.state === "db_prepared") {
        try {
            const { error } = await adminClient.auth.admin.deleteUser(job.former_user_id);

            if (!error) {
                await recordAuthResult(adminClient, job.id, true, null);
                return { jobId: job.id, phase: "auth", outcome: "succeeded" };
            }

            if (isUserAlreadyDeletedError(error)) {
                // Idempotent success — see lib.ts's own disclosed
                // reasoning for this classification.
                await recordAuthResult(adminClient, job.id, true, null);
                return { jobId: job.id, phase: "auth", outcome: "already_deleted" };
            }

            logInternal("admin.deleteUser", error);
            await recordAuthResult(adminClient, job.id, false, sanitizeRecoveryError(error, "auth_admin_failed"));
            return { jobId: job.id, phase: "auth", outcome: "failed" };
        } catch (error) {
            logInternal("admin.deleteUser", error);
            await recordAuthResult(adminClient, job.id, false, sanitizeRecoveryError(error, "auth_admin_failed"));
            return { jobId: job.id, phase: "auth", outcome: "failed" };
        }
    }

    // job.state === "auth_deleted" — Storage-cleanup retry. An empty
    // storage_paths array (nothing was ever captured, or a previous pass
    // already reduced it to empty but the completing update itself
    // somehow didn't land) is still handled correctly here: zero paths
    // means zero remaining, which record_account_deletion_storage_result()
    // treats as completion.
    const outcome = await removeStoragePathsIndividually(adminClient.storage, PROJECT_IMAGES_BUCKET, job.storage_paths);

    const errorCode = outcome.remainingPaths.length > 0 ? "storage_cleanup_partial" : null;
    await recordStorageResult(adminClient, job.id, outcome.remainingPaths, errorCode);

    return {
        jobId: job.id,
        phase: "storage",
        outcome: outcome.remainingPaths.length === 0 ? "completed" : "partial",
        remaining: outcome.remainingPaths.length
    };
}

Deno.serve(async req => {
    if (req.method !== "POST") {
        return jsonResponse({ error: "invalid_method" }, 405);
    }

    // The one and only gate — see this file's own header. Fails closed,
    // touches no database or Auth Admin API call, before this point.
    const providedSecret = req.headers.get("x-recovery-secret");
    if (!isAuthorizedRecoveryRequest(providedSecret, RECOVERY_SECRET)) {
        return jsonResponse({ error: "unauthorized" }, 401);
    }

    const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const workerId = crypto.randomUUID();

    let claimed: AccountDeletionJob[];
    try {
        const { data, error } = await adminClient.rpc("claim_account_deletion_jobs", {
            p_worker_id: workerId,
            p_limit: JOBS_PER_RUN,
            p_lease_seconds: LEASE_SECONDS,
            p_max_attempts: MAX_ATTEMPTS
        });

        if (error) {
            logInternal("claim_account_deletion_jobs", error);
            return jsonResponse({ error: "claim_failed" }, 500);
        }

        claimed = Array.isArray(data) ? data : [];
    } catch (error) {
        logInternal("claim_account_deletion_jobs", error);
        return jsonResponse({ error: "claim_failed" }, 500);
    }

    const results = [];
    for (const job of claimed) {
        try {
            results.push(await processJob(adminClient, job));
        } catch (error) {
            // A single job's own unexpected failure must never abort
            // the rest of the batch — each job is independent, and this
            // job's claim will simply expire (LEASE_SECONDS) and become
            // reclaimable again.
            logInternal("processJob", error);
            results.push({ jobId: job.id, phase: "unknown", outcome: "error" });
        }
    }

    // Deliberately a minimal summary only — job ids (opaque, no PII) and
    // outcomes, never former_user_id, storage paths, or any raw error
    // text. This response is intended for operator/cron logs, not a
    // client.
    return jsonResponse({ claimed: claimed.length, results });
});
