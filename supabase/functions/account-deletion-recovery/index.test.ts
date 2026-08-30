// Deno-native unit tests for supabase/functions/account-deletion-recovery's
// pure logic (supabase/functions/account-deletion-recovery/lib.ts).
//
// Run with: deno test supabase/functions/account-deletion-recovery/index.test.ts
// NOT executed in the authoring session — no local `deno` binary, no
// Docker daemon, and no Supabase CLI were available in this environment.
// Same disclosed limitation supabase/functions/delete-account/index.test.ts's
// own header already documents. Every assertion below is written against
// pure, side-effect-free exported functions so `deno test` is the only
// thing needed to run them for real before this function is deployed.
//
// This file deliberately does NOT test claim_account_deletion_jobs(),
// record_account_deletion_auth_result(), or
// record_account_deletion_storage_result() — those are SQL, covered by
// supabase/tests/migration_0050_account_deletion_recovery.test.sql
// instead, including the concurrent-claim, partial-path, repeated-
// execution, already-deleted-Auth-user, and final-completion coverage
// this PR's own review explicitly required.

import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { isAuthorizedRecoveryRequest, isUserAlreadyDeletedError, sanitizeRecoveryError, timingSafeEqual } from "./lib.ts";

Deno.test("timingSafeEqual: equal strings", () => {
    assertEquals(timingSafeEqual("secret-value", "secret-value"), true);
});

Deno.test("timingSafeEqual: different strings, same length", () => {
    assertEquals(timingSafeEqual("secret-value", "secret-VALUE"), false);
});

Deno.test("timingSafeEqual: different lengths", () => {
    assertEquals(timingSafeEqual("short", "a-much-longer-value"), false);
});

Deno.test("timingSafeEqual: empty strings are equal to each other", () => {
    assertEquals(timingSafeEqual("", ""), true);
});

Deno.test("isAuthorizedRecoveryRequest: correct secret is authorized", () => {
    assertEquals(isAuthorizedRecoveryRequest("the-real-secret", "the-real-secret"), true);
});

Deno.test("isAuthorizedRecoveryRequest: wrong secret is rejected", () => {
    assertEquals(isAuthorizedRecoveryRequest("a-guess", "the-real-secret"), false);
});

Deno.test("isAuthorizedRecoveryRequest: missing header is rejected", () => {
    assertEquals(isAuthorizedRecoveryRequest(null, "the-real-secret"), false);
});

Deno.test("isAuthorizedRecoveryRequest: empty header is rejected", () => {
    assertEquals(isAuthorizedRecoveryRequest("", "the-real-secret"), false);
});

Deno.test("isAuthorizedRecoveryRequest: unconfigured secret fails closed, even against itself", () => {
    // A misconfigured deployment (secret never set) must never fall
    // back to "no check" — an empty configured value rejects everything,
    // including an empty provided value.
    assertEquals(isAuthorizedRecoveryRequest("", undefined), false);
    assertEquals(isAuthorizedRecoveryRequest("anything", undefined), false);
    assertEquals(isAuthorizedRecoveryRequest("anything", ""), false);
});

Deno.test("isUserAlreadyDeletedError: 404 status counts as already-deleted", () => {
    assertEquals(isUserAlreadyDeletedError({ status: 404, message: "User not found" }), true);
});

Deno.test("isUserAlreadyDeletedError: user_not_found code counts as already-deleted", () => {
    assertEquals(isUserAlreadyDeletedError({ code: "user_not_found" }), true);
});

Deno.test("isUserAlreadyDeletedError: message text match, case-insensitive", () => {
    assertEquals(isUserAlreadyDeletedError({ message: "USER DOES NOT EXIST" }), true);
});

Deno.test("isUserAlreadyDeletedError: an unrelated failure is NOT idempotent success", () => {
    assertEquals(isUserAlreadyDeletedError({ status: 500, message: "internal server error" }), false);
});

Deno.test("isUserAlreadyDeletedError: null error is not a not-found", () => {
    assertEquals(isUserAlreadyDeletedError(null), false);
});

Deno.test("sanitizeRecoveryError: always returns the fixed fallback code, never raw error content", () => {
    assertEquals(sanitizeRecoveryError(new Error("some internal detail with a stack trace"), "auth_admin_failed"), "auth_admin_failed");
    assertEquals(sanitizeRecoveryError({ message: "leaky internal message" }, "storage_cleanup_partial"), "storage_cleanup_partial");
    assertEquals(sanitizeRecoveryError(undefined, "recovery_internal_error"), "recovery_internal_error");
});
