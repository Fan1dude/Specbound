// Regression coverage for the security headers this app depends on for its
// entire threat model (clickjacking, MIME-sniffing, referrer leakage, and
// now transport security) all living in one plain-text file with no schema
// enforcement: _headers. A single typo'd header name, a dropped line during
// a future edit, or an accidentally-widened HSTS value would ship straight
// to production with nothing else catching it — none of the other CI
// checks parse this file at all.
//
// This check parses the REAL _headers file (not a hardcoded copy of its
// expected contents), so it fails the moment the shipped file drifts from
// what it asserts, rather than asserting against itself.
//
// Also enforces this PR's specific Stage 1 HSTS boundary: max-age=300,
// no includeSubDomains, no preload. See _headers' own comment for why
// those are deliberately excluded at this stage — this check exists so a
// later, well-intentioned "let's just bump this while we're in here" edit
// can't silently skip the staged rollout.
//
// Header-name matching is case-insensitive (HTTP header names are
// case-insensitive per spec; a shipped `x-content-type-options` line is
// exactly as effective as `X-Content-Type-Options` and this check must
// not report a working header as missing just because of casing). Every
// header name is normalized to lowercase for both storage and lookup.
//
// A header name that appears more than once within the /* block is
// treated as a hard failure, not "last one wins" — a duplicate is either
// a leftover line from a botched edit or a merge artifact, and silently
// picking whichever happened to land last (even if that value is the
// approved one) hides the fact that the file is in an ambiguous state a
// human needs to look at. This applies to every header this check cares
// about, not just HSTS.
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const ROOT = join(SCRIPT_DIR, "..", "..");
const STAGE_1_MAX_AGE = 300;

let failures = 0;

function fail(message) {
    failures++;
    console.error(`✗ ${message}`);
}

// Parses the /* block of a Cloudflare Pages _headers file. Cloudflare's
// _headers format is: a path line, then one or more indented "Name: value"
// lines belonging to that path, blank lines/comments ignored. Only the /*
// (applies-to-everything) block is relevant to these guarantees — a header
// scoped to /css/* or /js/* wouldn't actually protect the page responses
// this check cares about, so scoping to /* specifically (not "any block")
// is deliberate.
//
// Returns { headers, duplicates }: `headers` maps a lowercased header name
// to its value (case-preserved), using the LAST occurrence if the name
// wasn't duplicated (irrelevant once `duplicates` flags it — callers must
// treat a duplicated name as failed regardless of any value in `headers`).
// `duplicates` is a Set of lowercased header names that appeared more than
// once in the block.
function parseHeadersBlock(text, pathLine) {
    const lines = text.split(/\r?\n/);
    const startIndex = lines.findIndex((line) => line.trim() === pathLine);
    if (startIndex === -1) return null;

    const headers = {};
    const counts = {};
    for (let i = startIndex + 1; i < lines.length; i++) {
        const line = lines[i];
        if (line.trim() === "" || line.trim().startsWith("#")) continue;
        if (!/^\s/.test(line)) break; // next path block (or EOF) — un-indented line ends this one
        const match = line.match(/^\s+([A-Za-z-]+):\s*(.*)$/);
        if (!match) continue;
        const key = match[1].toLowerCase();
        headers[key] = match[2].trim();
        counts[key] = (counts[key] ?? 0) + 1;
    }
    const duplicates = new Set(Object.keys(counts).filter((key) => counts[key] > 1));
    return { headers, duplicates };
}

// Case-preserving display name for each lowercased key this check looks
// at, purely so failure messages read naturally regardless of how the
// real file happened to capitalize a duplicated line.
const DISPLAY_NAME = {
    "strict-transport-security": "Strict-Transport-Security",
    "x-content-type-options": "X-Content-Type-Options",
    "referrer-policy": "Referrer-Policy",
    "permissions-policy": "Permissions-Policy",
    "content-security-policy": "Content-Security-Policy"
};

// Self-test the parser against known-shape fixtures before relying on it
// below, so a future edit to the parsing logic can't silently regress
// coverage without a visible failure here.
const PARSE_FIXTURES = [
    {
        text: "/*\n  X-Content-Type-Options: nosniff\n  Referrer-Policy: strict-origin-when-cross-origin\n\n/css/*\n  Cache-Control: public, max-age=0\n",
        expectedHeaders: { "x-content-type-options": "nosniff", "referrer-policy": "strict-origin-when-cross-origin" },
        expectedDuplicates: []
    },
    {
        text: "/*\n  Strict-Transport-Security: max-age=300\n# a comment line\n  X-Content-Type-Options: nosniff\n",
        expectedHeaders: { "strict-transport-security": "max-age=300", "x-content-type-options": "nosniff" },
        expectedDuplicates: []
    },
    // Case-insensitivity: a differently-cased header name must still be
    // recognized as the same header.
    {
        text: "/*\n  x-content-type-options: nosniff\n  REFERRER-POLICY: strict-origin-when-cross-origin\n",
        expectedHeaders: { "x-content-type-options": "nosniff", "referrer-policy": "strict-origin-when-cross-origin" },
        expectedDuplicates: []
    },
    // Duplicate detection: same header name twice (even same casing) must
    // be flagged, regardless of whether the values agree.
    {
        text: "/*\n  Strict-Transport-Security: max-age=99999999\n  Strict-Transport-Security: max-age=300\n",
        expectedHeaders: { "strict-transport-security": "max-age=300" },
        expectedDuplicates: ["strict-transport-security"]
    },
    // Duplicate detection across different casing of the same header name —
    // still the same header as far as real HTTP is concerned.
    {
        text: "/*\n  strict-transport-security: max-age=300\n  Strict-Transport-Security: max-age=300\n",
        expectedHeaders: { "strict-transport-security": "max-age=300" },
        expectedDuplicates: ["strict-transport-security"]
    }
];

for (const { text, expectedHeaders, expectedDuplicates } of PARSE_FIXTURES) {
    const parsed = parseHeadersBlock(text, "/*");
    const gotDuplicates = [...parsed.duplicates].sort();
    if (JSON.stringify(parsed.headers) !== JSON.stringify(expectedHeaders)) {
        fail(`_headers parser self-test failed (headers) — expected ${JSON.stringify(expectedHeaders)}, got ${JSON.stringify(parsed.headers)}`);
    }
    if (JSON.stringify(gotDuplicates) !== JSON.stringify([...expectedDuplicates].sort())) {
        fail(`_headers parser self-test failed (duplicates) — expected ${JSON.stringify(expectedDuplicates)}, got ${JSON.stringify(gotDuplicates)}`);
    }
}

// --- Parse the real, shipped _headers file ------------------------------

const headersPath = join(ROOT, "_headers");
const headersText = readFileSync(headersPath, "utf8");
const parsed = parseHeadersBlock(headersText, "/*");

if (!parsed) {
    fail("_headers has no /* block — none of the security headers below apply to real pages");
} else {
    const { headers, duplicates } = parsed;

    // Fail immediately and loudly on any duplicated header name this check
    // cares about — a duplicate is ambiguous even if one occurrence is the
    // approved value, so this doesn't try to "recover" a good reading from
    // an unreliable file.
    const RELEVANT = ["strict-transport-security", "x-content-type-options", "referrer-policy", "permissions-policy", "content-security-policy"];
    const duplicatedRelevant = RELEVANT.filter((key) => duplicates.has(key));
    for (const key of duplicatedRelevant) {
        fail(`_headers has ${DISPLAY_NAME[key]} defined more than once on /* — remove the duplicate; a repeated header name is ambiguous even if one occurrence has the approved value`);
    }

    // --- HSTS: present, numeric non-zero max-age, and within this PR's
    // approved Stage 1 boundary (no includeSubDomains/preload, max-age
    // capped at 300). Skipped if already flagged as duplicated above —
    // there's no single trustworthy value to validate further in that
    // case. -----------------------------------------------------------
    if (!duplicates.has("strict-transport-security")) {
        const hsts = headers["strict-transport-security"];
        if (!hsts) {
            fail("_headers is missing Strict-Transport-Security on /*");
        } else {
            const maxAgeMatch = hsts.match(/max-age=(\d+)/);
            if (!maxAgeMatch) {
                fail(`Strict-Transport-Security has no numeric max-age: "${hsts}"`);
            } else {
                const maxAge = Number(maxAgeMatch[1]);
                if (!(maxAge > 0)) {
                    fail(`Strict-Transport-Security max-age must be non-zero, got ${maxAge}`);
                } else if (maxAge > STAGE_1_MAX_AGE) {
                    fail(
                        `Strict-Transport-Security max-age=${maxAge} exceeds the approved Stage 1 value of ` +
                        `${STAGE_1_MAX_AGE} — raising this is a deliberate later-milestone decision, not a drive-by edit`
                    );
                }
            }
            if (/includeSubDomains/i.test(hsts)) {
                fail("Strict-Transport-Security must not include includeSubDomains in Stage 1 — see _headers' own comment");
            }
            if (/preload/i.test(hsts)) {
                fail("Strict-Transport-Security must not include preload in Stage 1 — see _headers' own comment");
            }
        }
    }

    // --- The other standing guarantees. Each skipped if already flagged
    // as duplicated above, for the same reason as HSTS. ---------------
    if (!duplicates.has("x-content-type-options")) {
        if (headers["x-content-type-options"] !== "nosniff") {
            fail(`X-Content-Type-Options must be exactly "nosniff", got ${JSON.stringify(headers["x-content-type-options"] ?? null)}`);
        }
    }

    if (!duplicates.has("referrer-policy")) {
        if (!headers["referrer-policy"]) {
            fail("_headers is missing Referrer-Policy on /*");
        }
    }

    if (!duplicates.has("permissions-policy")) {
        if (!headers["permissions-policy"]) {
            fail("_headers is missing Permissions-Policy on /*");
        }
    }

    if (!duplicates.has("content-security-policy")) {
        const csp = headers["content-security-policy"];
        if (!csp) {
            fail("_headers is missing Content-Security-Policy on /*");
        } else if (!/frame-ancestors\s+'none'/.test(csp)) {
            fail("Content-Security-Policy is missing frame-ancestors 'none' (clickjacking protection)");
        }
    }
}

if (failures > 0) {
    console.error(`\n${failures} security-header issue(s) found.`);
    process.exit(1);
}

console.log(
    "Security headers OK — HSTS present with a valid Stage 1 max-age (non-zero, <= " +
    `${STAGE_1_MAX_AGE}, no includeSubDomains/preload), X-Content-Type-Options: nosniff, ` +
    "Referrer-Policy, Permissions-Policy, and CSP with frame-ancestors 'none' all present on /*, " +
    "no header name duplicated, header-name casing handled case-insensitively."
);
