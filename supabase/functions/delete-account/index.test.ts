// Deno-native unit tests for supabase/functions/delete-account's pure
// logic (JWT payload decoding, recent-authentication enforcement) — no
// network calls, no live Supabase project.
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

import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { decodeJwtPayload, isRecentlyAuthenticated, MAX_REAUTH_AGE_SECONDS } from "./lib.ts";

// A minimal, unsigned JWT-shaped string for payload-decoding tests only
// — decodeJwtPayload() never verifies a signature (that already
// happened via supabase.auth.getUser() before this is ever called; see
// lib.ts's own header), so a fixture with no real signature is
// sufficient and appropriate here.
function fakeJwt(payload: Record<string, unknown>): string {
    const base64url = (obj: unknown) =>
        btoa(JSON.stringify(obj)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

    return `${base64url({ alg: "HS256", typ: "JWT" })}.${base64url(payload)}.fake-signature`;
}

// --- decodeJwtPayload ------------------------------------------------------

Deno.test("decodeJwtPayload: decodes a well-formed payload", () => {
    const jwt = fakeJwt({ sub: "user-1", iat: 1000 });
    assertEquals(decodeJwtPayload(jwt), { sub: "user-1", iat: 1000 });
});

Deno.test("decodeJwtPayload: returns null for a malformed token (wrong segment count)", () => {
    assertEquals(decodeJwtPayload("not-a-jwt"), null);
    assertEquals(decodeJwtPayload("only.two"), null);
});

Deno.test("decodeJwtPayload: returns null for invalid base64/JSON in the payload segment", () => {
    assertEquals(decodeJwtPayload("header.not-valid-base64!!!.sig"), null);
});

// --- isRecentlyAuthenticated -----------------------------------------------

Deno.test("isRecentlyAuthenticated: true for a token issued just now", () => {
    const now = 1_000_000;
    const jwt = fakeJwt({ iat: now });
    assertEquals(isRecentlyAuthenticated(jwt, now), true);
});

Deno.test("isRecentlyAuthenticated: true at exactly the MAX_REAUTH_AGE_SECONDS boundary", () => {
    const now = 1_000_000;
    const jwt = fakeJwt({ iat: now - MAX_REAUTH_AGE_SECONDS });
    assertEquals(isRecentlyAuthenticated(jwt, now), true);
});

Deno.test("isRecentlyAuthenticated: false one second past the boundary", () => {
    const now = 1_000_000;
    const jwt = fakeJwt({ iat: now - MAX_REAUTH_AGE_SECONDS - 1 });
    assertEquals(isRecentlyAuthenticated(jwt, now), false);
});

Deno.test("isRecentlyAuthenticated: false for a token with no iat claim", () => {
    const jwt = fakeJwt({ sub: "user-1" });
    assertEquals(isRecentlyAuthenticated(jwt, 1_000_000), false);
});

Deno.test("isRecentlyAuthenticated: false for a malformed token", () => {
    assertEquals(isRecentlyAuthenticated("garbage", 1_000_000), false);
});

// A token whose iat is in the future (clock skew, or a forged/replayed
// claim) is rejected, not treated as "even more recent than now" —
// never widen the acceptance window past what a real, freshly-issued
// token could produce.
Deno.test("isRecentlyAuthenticated: false for a token with iat in the future", () => {
    const now = 1_000_000;
    const jwt = fakeJwt({ iat: now + 60 });
    assertEquals(isRecentlyAuthenticated(jwt, now), false);
});
