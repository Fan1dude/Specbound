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

import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { errorResponseBody } from "./lib.ts";

Deno.test("errorResponseBody: wraps a code in the { error } shape the client expects", () => {
    assertEquals(errorResponseBody("auth_required"), { error: "auth_required" });
    assertEquals(errorResponseBody("reauth_required"), { error: "reauth_required" });
    assertEquals(errorResponseBody("db_prep_failed"), { error: "db_prep_failed" });
    assertEquals(errorResponseBody("auth_admin_failed"), { error: "auth_admin_failed" });
    assertEquals(errorResponseBody("invalid_method"), { error: "invalid_method" });
    assertEquals(errorResponseBody("internal_error"), { error: "internal_error" });
});
