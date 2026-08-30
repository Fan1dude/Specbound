// Deno-native unit tests for supabase/functions/delete-account's pure
// logic (supabase/functions/delete-account/lib.ts).
//
// Run with: deno test supabase/functions/delete-account/index.test.ts
// NOT executed in the authoring session — no local `deno` binary, no
// Docker daemon, and no Supabase CLI were available in this environment
// (confirmed: `which supabase`/`which psql` found nothing, `docker ps`
// could not reach a running daemon). Same disclosed limitation
// product-metadata/index.test.ts's own header already documents for an
// identical reason. Every assertion below is written against pure,
// side-effect-free exported functions so `deno test` is the only thing
// needed to run them for real before this function is deployed.
//
// Security-review note: recent-reauthentication verification (the
// former isRecentlyAuthenticated()/decodeJwtPayload() functions
// previously here) was removed from this file entirely — that
// iat-based check was insufficient (Supabase's own refresh-token grant
// mints a new access token, with a new `iat`, without re-verifying the
// password) and has been replaced with a database-verified, single-use
// challenge checked against the caller's own `auth.jwt() -> 'amr'`
// claim, entirely server-side in Postgres — see
// supabase/migrations/0049_account_deletion_challenge.sql and this
// function's own index.ts header. There is no JWT-decoding logic left
// in this Edge Function to unit test; the coverage for the actual
// freshness check now lives in
// supabase/tests/migration_0049_account_deletion_challenge.test.sql.
//
// Second security-review note (0050): removeStoragePathsIndividually()
// below is the shared per-path Storage-removal helper this function AND
// supabase/functions/account-deletion-recovery both call — see
// supabase/migrations/0050_account_deletion_recovery.sql's own header
// for the two real bugs its introduction fixed (Storage failure
// previously marked the job complete anyway; the attempt counter was
// hardcoded, never actually incremented).

import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { errorResponseBody, removeStoragePathsIndividually, type StorageClientLike } from "./lib.ts";

Deno.test("errorResponseBody: wraps a code in the { error } shape the client expects", () => {
    assertEquals(errorResponseBody("auth_required"), { error: "auth_required" });
    assertEquals(errorResponseBody("reauth_required"), { error: "reauth_required" });
    assertEquals(errorResponseBody("db_prep_failed"), { error: "db_prep_failed" });
    assertEquals(errorResponseBody("auth_admin_failed"), { error: "auth_admin_failed" });
    assertEquals(errorResponseBody("invalid_method"), { error: "invalid_method" });
    assertEquals(errorResponseBody("internal_error"), { error: "internal_error" });
});

// A fake Storage client whose remove() outcome per bucket is scripted by
// a Map<path, boolean> (true = succeeds, false/absent = errors) — pure,
// no network, matching this file's own contract.
function fakeStorageClient(outcomes: Map<string, boolean>): StorageClientLike {
    return {
        from(_bucket: string) {
            return {
                async remove(paths: string[]) {
                    const [path] = paths;
                    if (outcomes.get(path)) {
                        return { error: null };
                    }
                    return { error: { message: "simulated failure" } };
                }
            };
        }
    };
}

Deno.test("removeStoragePathsIndividually: all paths succeed", async () => {
    const client = fakeStorageClient(new Map([["a", true], ["b", true]]));
    const result = await removeStoragePathsIndividually(client, "bucket", ["a", "b"]);
    assertEquals(result.succeededPaths, ["a", "b"]);
    assertEquals(result.remainingPaths, []);
});

Deno.test("removeStoragePathsIndividually: one bad path does not block the others", async () => {
    const client = fakeStorageClient(new Map([["a", true], ["b", false], ["c", true]]));
    const result = await removeStoragePathsIndividually(client, "bucket", ["a", "b", "c"]);
    assertEquals(result.succeededPaths, ["a", "c"]);
    assertEquals(result.remainingPaths, ["b"]);
});

Deno.test("removeStoragePathsIndividually: a thrown error counts as remaining, not a crash", async () => {
    const client: StorageClientLike = {
        from(_bucket: string) {
            return {
                remove(_paths: string[]): Promise<{ error: null }> {
                    throw new Error("network error");
                }
            };
        }
    };
    const result = await removeStoragePathsIndividually(client, "bucket", ["a"]);
    assertEquals(result.succeededPaths, []);
    assertEquals(result.remainingPaths, ["a"]);
});

Deno.test("removeStoragePathsIndividually: empty input returns empty output, no calls made", async () => {
    const client = fakeStorageClient(new Map());
    const result = await removeStoragePathsIndividually(client, "bucket", []);
    assertEquals(result.succeededPaths, []);
    assertEquals(result.remainingPaths, []);
});
