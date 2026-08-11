// Pure, side-effect-free logic for supabase/functions/product-metadata —
// split out from index.ts specifically so index.test.ts can import and
// unit-test this without needing network access, Deno.serve, or
// Deno.resolveDns. See index.ts for the request handler and the parts of
// the SSRF pipeline that genuinely require I/O (DNS resolution, the
// fetch/redirect/size-cap loop).

export const MAX_TITLE_LENGTH = 200;
export const MAX_RETAILER_NAME_LENGTH = 80;

export const ALLOWED_RETAILER_DOMAINS = new Set([
    "amazon.com",
    "bestbuy.com",
    "target.com",
    "walmart.com",
    "newegg.com",
    "ikea.com",
    "wayfair.com",
    "homedepot.com",
    "staples.com",
    "officedepot.com",
    "bhphotovideo.com",
    "microcenter.com"
]);

export function ipv4ToInt(ip: string): number | null {
    const parts = ip.split(".");
    if (parts.length !== 4) return null;

    let value = 0;
    for (const part of parts) {
        const n = Number(part);
        if (!Number.isInteger(n) || n < 0 || n > 255) return null;
        value = (value << 8) | n;
    }
    return value >>> 0;
}

// Every non-globally-routable IPv4 block relevant to SSRF: unspecified,
// private (RFC1918), loopback, link-local (which covers the
// 169.254.169.254 cloud-metadata address), IETF protocol assignments,
// benchmarking, multicast, and reserved.
export function isPrivateOrReservedIPv4(ip: string): boolean {
    const value = ipv4ToInt(ip);
    if (value === null) return false;

    const inRange = (base: string, maskBits: number) => {
        const baseValue = ipv4ToInt(base)!;
        const mask = maskBits === 0 ? 0 : (0xffffffff << (32 - maskBits)) >>> 0;
        return (value & mask) === (baseValue & mask);
    };

    return (
        inRange("0.0.0.0", 8) ||
        inRange("10.0.0.0", 8) ||
        inRange("127.0.0.0", 8) ||
        inRange("169.254.0.0", 16) ||
        inRange("172.16.0.0", 12) ||
        inRange("192.168.0.0", 16) ||
        inRange("192.0.0.0", 24) ||
        inRange("198.18.0.0", 15) ||
        inRange("224.0.0.0", 4) ||
        inRange("240.0.0.0", 4)
    );
}

export function isPrivateOrReservedIPv6(ip: string): boolean {
    const normalized = ip.toLowerCase();

    if (normalized === "::1" || normalized === "::") return true;
    if (/^fe[89ab]/.test(normalized)) return true; // link-local fe80::/10
    if (normalized.startsWith("fc") || normalized.startsWith("fd")) return true; // unique local fc00::/7

    const mapped = normalized.match(/^::ffff:(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})$/);
    if (mapped) return isPrivateOrReservedIPv4(mapped[1]);

    return false;
}

export function getRegistrableDomain(hostname: string): string {
    const parts = hostname.toLowerCase().split(".");
    return parts.length <= 2 ? hostname.toLowerCase() : parts.slice(-2).join(".");
}

function decodeHtmlEntities(value: string): string {
    return value
        .replace(/&amp;/g, "&")
        .replace(/&lt;/g, "<")
        .replace(/&gt;/g, ">")
        .replace(/&quot;/g, '"')
        .replace(/&#39;/g, "'")
        .replace(/&nbsp;/g, " ");
}

function cleanText(value: string, maxLength: number): string {
    return decodeHtmlEntities(value).replace(/\s+/g, " ").trim().slice(0, maxLength);
}

export interface ExtractedMetadata {
    title: string | null;
    retailerName: string | null;
    priceCents: number | null;
    currency: string | null;
}

export function priceStringToCents(value: unknown): number | null {
    if (typeof value === "number" && Number.isFinite(value)) return Math.round(value * 100);
    if (typeof value === "string") {
        const cleaned = value.replace(/[^0-9.]/g, "");
        const num = Number(cleaned);
        return Number.isFinite(num) && cleaned !== "" ? Math.round(num * 100) : null;
    }
    return null;
}

export function extractFromJsonLd(html: string): ExtractedMetadata | null {
    const scriptMatches = html.matchAll(/<script[^>]*type=["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi);

    for (const match of scriptMatches) {
        let parsed: unknown;
        try {
            parsed = JSON.parse(match[1]);
        } catch {
            continue;
        }

        const candidates = Array.isArray(parsed) ? parsed : [parsed];

        for (const candidate of candidates) {
            const node = candidate && typeof candidate === "object" && "@graph" in (candidate as Record<string, unknown>)
                ? (candidate as { "@graph": unknown[] })["@graph"]
                : [candidate];

            for (const item of Array.isArray(node) ? node : [node]) {
                if (!item || typeof item !== "object") continue;
                const record = item as Record<string, unknown>;
                const type = record["@type"];
                const isProduct = type === "Product" || (Array.isArray(type) && type.includes("Product"));
                if (!isProduct) continue;

                const name = typeof record.name === "string" ? cleanText(record.name, MAX_TITLE_LENGTH) : null;

                let offer = record.offers;
                if (Array.isArray(offer)) offer = offer[0];
                const offerRecord = offer && typeof offer === "object" ? (offer as Record<string, unknown>) : null;

                const priceCents = offerRecord ? priceStringToCents(offerRecord.price) : null;
                const currency = offerRecord && typeof offerRecord.priceCurrency === "string"
                    ? offerRecord.priceCurrency.toUpperCase()
                    : null;

                if (name || priceCents !== null) {
                    return { title: name, retailerName: null, priceCents, currency };
                }
            }
        }
    }

    return null;
}

function extractMetaContent(html: string, property: string): string | null {
    const pattern = new RegExp(
        `<meta[^>]+(?:property|name)=["']${property}["'][^>]+content=["']([^"']*)["']`,
        "i"
    );
    const match = html.match(pattern) || html.match(
        new RegExp(`<meta[^>]+content=["']([^"']*)["'][^>]+(?:property|name)=["']${property}["']`, "i")
    );
    return match ? cleanText(match[1], MAX_TITLE_LENGTH) : null;
}

export function extractFromOpenGraph(html: string): ExtractedMetadata | null {
    const title = extractMetaContent(html, "og:title");
    const priceAmount = extractMetaContent(html, "product:price:amount") || extractMetaContent(html, "og:price:amount");
    const priceCurrency = extractMetaContent(html, "product:price:currency") || extractMetaContent(html, "og:price:currency");

    if (!title && !priceAmount) return null;

    return {
        title,
        retailerName: extractMetaContent(html, "og:site_name"),
        priceCents: priceAmount ? priceStringToCents(priceAmount) : null,
        currency: priceCurrency ? priceCurrency.toUpperCase() : null
    };
}

export function extractFromTitleTag(html: string): ExtractedMetadata | null {
    const match = html.match(/<title[^>]*>([\s\S]*?)<\/title>/i);
    if (!match) return null;

    const title = cleanText(match[1], MAX_TITLE_LENGTH);
    return title ? { title, retailerName: null, priceCents: null, currency: null } : null;
}

export function extractMetadata(html: string, hostname: string): ExtractedMetadata {
    const result = extractFromJsonLd(html) || extractFromOpenGraph(html) || extractFromTitleTag(html) || {
        title: null,
        retailerName: null,
        priceCents: null,
        currency: null
    };

    if (!result.retailerName) {
        result.retailerName = cleanText(getRegistrableDomain(hostname), MAX_RETAILER_NAME_LENGTH);
    }

    return result;
}
