// Milestone 23 — supabase/functions/product-metadata
//
// Best-effort product metadata extraction for the Setup-inventory
// link-assisted entry flow. See
// docs/milestones/MILESTONE_23_SETUP_INVENTORY_SEARCH_SPECIFICATION.md
// §5 for the full design rationale — this file implements exactly that
// spec, in the same order the twelve SSRF checks are documented there.
//
// Never fetches arbitrary retailer HTML on the browser's behalf without
// going through every check below first, never returns raw HTML, never
// executes page script (there is no headless browser anywhere in this
// function — extraction is regex/JSON-based text parsing only), and
// never requires success: every failure path returns the same generic
// { error } shape the client already treats as "fall back to manual
// entry."

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import {
    ALLOWED_RETAILER_DOMAINS,
    ipv4ToInt,
    isPrivateOrReservedIPv4,
    isPrivateOrReservedIPv6,
    getRegistrableDomain,
    extractMetadata
} from "./lib.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

const MAX_REDIRECTS = 3;
const FETCH_TIMEOUT_MS = 5000;
const MAX_RESPONSE_BYTES = 2 * 1024 * 1024; // 2 MB

// 12. Rate limiting — a simple fixed-window counter per user, held in
// this isolate's memory. Acceptable for beta scale (documented as a
// known limitation, not a distributed/production-hardened limiter) —
// see spec §5.2 item 12.
const RATE_LIMIT_WINDOW_MS = 60_000;
const RATE_LIMIT_MAX_REQUESTS = 20;
const rateLimitState = new Map<string, { windowStart: number; count: number }>();

function isRateLimited(userId: string): boolean {
    const now = Date.now();
    const entry = rateLimitState.get(userId);

    if (!entry || now - entry.windowStart > RATE_LIMIT_WINDOW_MS) {
        rateLimitState.set(userId, { windowStart: now, count: 1 });
        return false;
    }

    entry.count += 1;
    return entry.count > RATE_LIMIT_MAX_REQUESTS;
}

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

// Only the hostname and outcome are ever logged — never the full URL,
// which may carry tracking/session query parameters (spec §5.2 item 11).
function logOutcome(hostname: string, outcome: string) {
    console.log(`${hostname}: ${outcome}`);
}

// --- SSRF destination checks (spec §5.2, steps 1-5) ----------------------
// ipv4ToInt / isPrivateOrReservedIPv4 / isPrivateOrReservedIPv6 /
// getRegistrableDomain are pure and live in ./lib.ts (imported above) so
// index.test.ts can exercise them without Deno.resolveDns or network
// access. Only the genuinely I/O-dependent DNS lookup stays here.

async function resolvesToBlockedAddress(hostname: string): Promise<boolean> {
    const lower = hostname.toLowerCase();
    if (lower === "localhost" || lower.endsWith(".localhost")) return true;

    // A bare IP literal in the URL — check it directly without a DNS
    // lookup (Deno.resolveDns on a literal IP is unreliable across
    // record types).
    if (ipv4ToInt(hostname) !== null) return isPrivateOrReservedIPv4(hostname);
    if (hostname.includes(":")) return isPrivateOrReservedIPv6(hostname);

    try {
        const [aRecords, aaaaRecords] = await Promise.all([
            Deno.resolveDns(hostname, "A").catch(() => [] as string[]),
            Deno.resolveDns(hostname, "AAAA").catch(() => [] as string[])
        ]);

        if (aRecords.length === 0 && aaaaRecords.length === 0) return true; // unresolvable — never fetch blind

        return (
            aRecords.some(isPrivateOrReservedIPv4) ||
            aaaaRecords.some(isPrivateOrReservedIPv6)
        );
    } catch {
        return true; // DNS failure — fail closed, never fetch blind
    }
}

async function validateDestination(rawUrl: string): Promise<{ ok: true; url: URL } | { ok: false; reason: string }> {
    let parsed: URL;
    try {
        parsed = new URL(rawUrl);
    } catch {
        return { ok: false, reason: "invalid" };
    }

    // 1. Scheme.
    if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
        return { ok: false, reason: "invalid" };
    }

    // 2. Credentials in the URL.
    if (parsed.username || parsed.password) {
        return { ok: false, reason: "invalid" };
    }

    // 3. Port — only the scheme default, or none explicit.
    const defaultPort = parsed.protocol === "https:" ? "443" : "80";
    if (parsed.port && parsed.port !== defaultPort) {
        return { ok: false, reason: "invalid" };
    }

    // 4. Destination check (localhost/loopback/link-local/private/reserved).
    if (await resolvesToBlockedAddress(parsed.hostname)) {
        return { ok: false, reason: "blocked" };
    }

    // 10. Retailer allowlist.
    if (!ALLOWED_RETAILER_DOMAINS.has(getRegistrableDomain(parsed.hostname))) {
        return { ok: false, reason: "unsupported" };
    }

    return { ok: true, url: parsed };
}

// --- Fetch with manual redirect revalidation, timeout, size cap ---------

async function fetchHtml(startUrl: URL): Promise<{ ok: true; html: string; finalHost: string } | { ok: false; reason: string }> {
    let currentUrl = startUrl;

    for (let redirectCount = 0; redirectCount <= MAX_REDIRECTS; redirectCount++) {
        const controller = new AbortController();
        const timeout = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);

        let response: Response;
        try {
            response = await fetch(currentUrl.toString(), {
                redirect: "manual",
                signal: controller.signal,
                headers: { "User-Agent": "SpecboundBot/1.0 (+https://specboundapp.com)" }
            });
        } catch (error) {
            clearTimeout(timeout);
            if (error instanceof DOMException && error.name === "AbortError") {
                return { ok: false, reason: "timeout" };
            }
            return { ok: false, reason: "blocked" };
        }
        clearTimeout(timeout);

        // 5. Redirect handling — every hop is revalidated from scratch
        // (steps 1-4, 10 above) before being followed.
        if (response.status >= 300 && response.status < 400) {
            const location = response.headers.get("location");
            if (!location) return { ok: false, reason: "blocked" };

            let nextUrl: URL;
            try {
                nextUrl = new URL(location, currentUrl);
            } catch {
                return { ok: false, reason: "blocked" };
            }

            const revalidated = await validateDestination(nextUrl.toString());
            if (!revalidated.ok) return { ok: false, reason: revalidated.reason };

            currentUrl = revalidated.url;
            continue;
        }

        if (!response.ok) {
            return { ok: false, reason: "blocked" };
        }

        // 8. Content-Type.
        const contentType = response.headers.get("content-type") || "";
        if (!/^(text\/html|application\/xhtml\+xml)/i.test(contentType.trim())) {
            return { ok: false, reason: "unsupported" };
        }

        // 7. Response size cap — read the stream manually and abort once
        // the cap is exceeded, rather than buffering an unbounded body
        // first.
        const reader = response.body?.getReader();
        if (!reader) return { ok: false, reason: "blocked" };

        const chunks: Uint8Array[] = [];
        let totalBytes = 0;

        while (true) {
            const { done, value } = await reader.read();
            if (done) break;

            totalBytes += value.byteLength;
            if (totalBytes > MAX_RESPONSE_BYTES) {
                reader.cancel();
                return { ok: false, reason: "unsupported" };
            }
            chunks.push(value);
        }

        const html = new TextDecoder("utf-8").decode(concatUint8Arrays(chunks));
        return { ok: true, html, finalHost: currentUrl.hostname };
    }

    return { ok: false, reason: "blocked" }; // 6. redirect limit exceeded
}

function concatUint8Arrays(chunks: Uint8Array[]): Uint8Array {
    const total = chunks.reduce((sum, c) => sum + c.length, 0);
    const result = new Uint8Array(total);
    let offset = 0;
    for (const chunk of chunks) {
        result.set(chunk, offset);
        offset += chunk.length;
    }
    return result;
}

// --- Metadata extraction (spec §5.3) is pure text parsing with no script
// execution or DOM construction — lives in ./lib.ts (imported above as
// extractMetadata) alongside the JSON-LD/Open Graph/title-tag parsers so
// index.test.ts can exercise it against local HTML fixtures.

// --- Handler --------------------------------------------------------------

Deno.serve(async req => {
    if (req.method === "OPTIONS") {
        return new Response(null, { headers: CORS_HEADERS });
    }

    if (req.method !== "POST") {
        return jsonResponse({ error: "invalid" }, 405);
    }

    // Auth required — verified against the request's own JWT, never the
    // anon key alone (spec §5.1, §7 RLS/grants section — no service-role
    // key appears anywhere in this function or in browser code).
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
        return jsonResponse({ error: "auth_required" }, 401);
    }

    const supabaseClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
        global: { headers: { Authorization: authHeader } }
    });

    const { data: userData, error: authError } = await supabaseClient.auth.getUser();
    if (authError || !userData?.user) {
        return jsonResponse({ error: "auth_required" }, 401);
    }

    const user = userData.user;

    if (isRateLimited(user.id)) {
        return jsonResponse({ error: "rate_limited" }, 429);
    }

    let body: { url?: unknown };
    try {
        body = await req.json();
    } catch {
        return jsonResponse({ error: "invalid" }, 400);
    }

    if (typeof body.url !== "string" || !body.url.trim()) {
        return jsonResponse({ error: "invalid" }, 400);
    }

    const destination = await validateDestination(body.url.trim());
    if (!destination.ok) {
        logOutcome(safeHostnameForLog(body.url), `rejected(${destination.reason})`);
        return jsonResponse({ error: destination.reason }, 200);
    }

    const fetchResult = await fetchHtml(destination.url);
    if (!fetchResult.ok) {
        logOutcome(destination.url.hostname, `rejected(${fetchResult.reason})`);
        return jsonResponse({ error: fetchResult.reason }, 200);
    }

    const metadata = extractMetadata(fetchResult.html, fetchResult.finalHost);
    logOutcome(fetchResult.finalHost, "ok");

    return jsonResponse({
        title: metadata.title,
        retailerName: metadata.retailerName,
        priceCents: metadata.priceCents,
        currency: metadata.currency
    });
});

function safeHostnameForLog(rawUrl: string): string {
    try {
        return new URL(rawUrl).hostname;
    } catch {
        return "invalid-url";
    }
}
