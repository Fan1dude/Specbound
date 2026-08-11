// Deno-native unit tests for supabase/functions/product-metadata's pure
// logic (SSRF destination checks + metadata parsing) — no network calls,
// no live retailer fixtures, matching the milestone's explicit
// "use local HTML fixtures rather than depending on live retailer
// websites" requirement.
//
// Run with: deno test supabase/functions/product-metadata/index.test.ts
// NOT executed in the authoring session (no local `deno` binary and no
// host-reachable local Supabase Functions gateway were available — see
// the milestone's final report for the exact environmental limitation).
// Every assertion below is written against pure, side-effect-free
// exported functions so `deno test` is the only thing needed to run
// them for real before this function is deployed.

import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
    isPrivateOrReservedIPv4,
    isPrivateOrReservedIPv6,
    getRegistrableDomain,
    extractFromJsonLd,
    extractFromOpenGraph,
    extractFromTitleTag,
    priceStringToCents
} from "./lib.ts";

// --- IPv4 destination checks ---------------------------------------------
Deno.test("IPv4: loopback is blocked", () => {
    assertEquals(isPrivateOrReservedIPv4("127.0.0.1"), true);
});

Deno.test("IPv4: 10.x private range is blocked", () => {
    assertEquals(isPrivateOrReservedIPv4("10.1.2.3"), true);
});

Deno.test("IPv4: 172.16-31.x private range is blocked", () => {
    assertEquals(isPrivateOrReservedIPv4("172.20.0.5"), true);
    assertEquals(isPrivateOrReservedIPv4("172.15.0.5"), false); // just outside the range
});

Deno.test("IPv4: 192.168.x private range is blocked", () => {
    assertEquals(isPrivateOrReservedIPv4("192.168.1.1"), true);
});

Deno.test("IPv4: link-local (including cloud metadata 169.254.169.254) is blocked", () => {
    assertEquals(isPrivateOrReservedIPv4("169.254.169.254"), true);
    assertEquals(isPrivateOrReservedIPv4("169.254.1.1"), true);
});

Deno.test("IPv4: unspecified 0.0.0.0 is blocked", () => {
    assertEquals(isPrivateOrReservedIPv4("0.0.0.0"), true);
});

Deno.test("IPv4: a genuine public address is not blocked", () => {
    assertEquals(isPrivateOrReservedIPv4("8.8.8.8"), false);
    assertEquals(isPrivateOrReservedIPv4("93.184.216.34"), false);
});

// --- IPv6 destination checks ----------------------------------------------
Deno.test("IPv6: loopback ::1 is blocked", () => {
    assertEquals(isPrivateOrReservedIPv6("::1"), true);
});

Deno.test("IPv6: link-local fe80::/10 is blocked", () => {
    assertEquals(isPrivateOrReservedIPv6("fe80::1"), true);
});

Deno.test("IPv6: unique-local fc00::/7 is blocked", () => {
    assertEquals(isPrivateOrReservedIPv6("fd12:3456:789a::1"), true);
});

Deno.test("IPv6: IPv4-mapped private address is blocked", () => {
    assertEquals(isPrivateOrReservedIPv6("::ffff:127.0.0.1"), true);
    assertEquals(isPrivateOrReservedIPv6("::ffff:10.0.0.5"), true);
});

Deno.test("IPv6: IPv4-mapped public address is not blocked", () => {
    assertEquals(isPrivateOrReservedIPv6("::ffff:8.8.8.8"), false);
});

Deno.test("IPv6: a genuine public address is not blocked", () => {
    assertEquals(isPrivateOrReservedIPv6("2001:4860:4860::8888"), false);
});

// --- Registrable domain -----------------------------------------------
Deno.test("getRegistrableDomain strips subdomains", () => {
    assertEquals(getRegistrableDomain("www.bestbuy.com"), "bestbuy.com");
    assertEquals(getRegistrableDomain("bestbuy.com"), "bestbuy.com");
    assertEquals(getRegistrableDomain("shop.internal.bestbuy.com"), "bestbuy.com");
});

// --- Metadata extraction (local fixtures, no network) --------------------
Deno.test("JSON-LD: extracts Product title and price", () => {
    const html = `
        <html><head>
        <script type="application/ld+json">
        {"@context":"https://schema.org","@type":"Product","name":"27-inch OLED Monitor","offers":{"@type":"Offer","price":"699.99","priceCurrency":"USD"}}
        </script>
        </head><body></body></html>
    `;
    const result = extractFromJsonLd(html);
    assertEquals(result?.title, "27-inch OLED Monitor");
    assertEquals(result?.priceCents, 69999);
    assertEquals(result?.currency, "USD");
});

Deno.test("JSON-LD: handles an @graph-wrapped Product", () => {
    const html = `
        <script type="application/ld+json">
        {"@graph":[{"@type":"WebPage"},{"@type":"Product","name":"Standing Desk","offers":{"price":420,"priceCurrency":"usd"}}]}
        </script>
    `;
    const result = extractFromJsonLd(html);
    assertEquals(result?.title, "Standing Desk");
    assertEquals(result?.priceCents, 42000);
    assertEquals(result?.currency, "USD");
});

Deno.test("JSON-LD: malformed JSON falls through cleanly (returns null, does not throw)", () => {
    const html = `<script type="application/ld+json">{ not valid json </script>`;
    assertEquals(extractFromJsonLd(html), null);
});

Deno.test("JSON-LD: no Product type present returns null", () => {
    const html = `<script type="application/ld+json">{"@type":"WebPage","name":"Home"}</script>`;
    assertEquals(extractFromJsonLd(html), null);
});

Deno.test("Open Graph: extracts title and site name when JSON-LD is absent", () => {
    const html = `
        <meta property="og:title" content="Mechanical Keyboard 75%">
        <meta property="og:site_name" content="Example Retailer">
    `;
    const result = extractFromOpenGraph(html);
    assertEquals(result?.title, "Mechanical Keyboard 75%");
    assertEquals(result?.retailerName, "Example Retailer");
});

Deno.test("Open Graph: missing price fields leave priceCents null (missing price behavior)", () => {
    const html = `<meta property="og:title" content="Desk Lamp">`;
    const result = extractFromOpenGraph(html);
    assertEquals(result?.priceCents, null);
});

Deno.test("Title fallback: used only when JSON-LD and OG both fail", () => {
    const html = `<html><head><title>  Generic Product Page  </title></head></html>`;
    const result = extractFromTitleTag(html);
    assertEquals(result?.title, "Generic Product Page");
});

Deno.test("Title fallback: never claims a price", () => {
    const html = `<title>Some Page</title>`;
    const result = extractFromTitleTag(html);
    assertEquals(result?.priceCents, null);
});

Deno.test("priceStringToCents: parses a plain decimal string", () => {
    assertEquals(priceStringToCents("64.99"), 6499);
});

Deno.test("priceStringToCents: strips currency symbols", () => {
    assertEquals(priceStringToCents("$1,299.00"), 129900);
});

Deno.test("priceStringToCents: a numeric JSON value is treated as major units", () => {
    assertEquals(priceStringToCents(19.99), 1999);
});

Deno.test("priceStringToCents: unparseable input returns null, never 0", () => {
    assertEquals(priceStringToCents("call for price"), null);
    assertEquals(priceStringToCents(undefined), null);
});
