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

// Parses the /* block of a Cloudflare Pages _headers file into a
// { headerName: rawValue } map. Cloudflare's _headers format is: a path
// line, then one or more indented "Name: value" lines belonging to that
// path, blank lines/comments ignored. Only the /* (applies-to-everything)
// block is relevant to these guarantees — a header scoped to /css/* or
// /js/* wouldn't actually protect the page responses this check cares
// about, so scoping to /* specifically (not "any block") is deliberate.
function parseHeadersBlock(text, pathLine) {
    const lines = text.split(/\r?\n/);
    const startIndex = lines.findIndex((line) => line.trim() === pathLine);
    if (startIndex === -1) return null;

    const headers = {};
    for (let i = startIndex + 1; i < lines.length; i++) {
        const line = lines[i];
        if (line.trim() === "" || line.trim().startsWith("#")) continue;
        if (!/^\s/.test(line)) break; // next path block (or EOF) — un-indented line ends this one
        const match = line.match(/^\s+([A-Za-z-]+):\s*(.*)$/);
        if (!match) continue;
        headers[match[1]] = match[2].trim();
    }
    return headers;
}

// Self-test the parser against known-shape fixtures before relying on it
// below, so a future edit to the parsing logic can't silently regress
// coverage without a visible failure here.
const PARSE_FIXTURES = [
    {
        text: "/*\n  X-Content-Type-Options: nosniff\n  Referrer-Policy: strict-origin-when-cross-origin\n\n/css/*\n  Cache-Control: public, max-age=0\n",
        expected: { "X-Content-Type-Options": "nosniff", "Referrer-Policy": "strict-origin-when-cross-origin" }
    },
    {
        text: "/*\n  Strict-Transport-Security: max-age=300\n# a comment line\n  X-Content-Type-Options: nosniff\n",
        expected: { "Strict-Transport-Security": "max-age=300", "X-Content-Type-Options": "nosniff" }
    }
];

for (const { text, expected } of PARSE_FIXTURES) {
    const parsed = parseHeadersBlock(text, "/*");
    if (JSON.stringify(parsed) !== JSON.stringify(expected)) {
        fail(`_headers parser self-test failed — expected ${JSON.stringify(expected)}, got ${JSON.stringify(parsed)}`);
    }
}

// --- Parse the real, shipped _headers file ------------------------------

const headersPath = join(ROOT, "_headers");
const headersText = readFileSync(headersPath, "utf8");
const headers = parseHeadersBlock(headersText, "/*");

if (!headers) {
    fail("_headers has no /* block — none of the security headers below apply to real pages");
} else {
    // --- HSTS: present, numeric non-zero max-age, and within this PR's
    // approved Stage 1 boundary (no includeSubDomains/preload, max-age
    // capped at 300). -----------------------------------------------------
    const hsts = headers["Strict-Transport-Security"];
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

    // --- The other standing guarantees. ------------------------------------
    if (headers["X-Content-Type-Options"] !== "nosniff") {
        fail(`X-Content-Type-Options must be exactly "nosniff", got ${JSON.stringify(headers["X-Content-Type-Options"] ?? null)}`);
    }

    if (!headers["Referrer-Policy"]) {
        fail("_headers is missing Referrer-Policy on /*");
    }

    if (!headers["Permissions-Policy"]) {
        fail("_headers is missing Permissions-Policy on /*");
    }

    const csp = headers["Content-Security-Policy"];
    if (!csp) {
        fail("_headers is missing Content-Security-Policy on /*");
    } else if (!/frame-ancestors\s+'none'/.test(csp)) {
        fail("Content-Security-Policy is missing frame-ancestors 'none' (clickjacking protection)");
    }
}

if (failures > 0) {
    console.error(`\n${failures} security-header issue(s) found.`);
    process.exit(1);
}

console.log(
    "Security headers OK — HSTS present with a valid Stage 1 max-age (non-zero, <= " +
    `${STAGE_1_MAX_AGE}, no includeSubDomains/preload), X-Content-Type-Options: nosniff, ` +
    "Referrer-Policy, Permissions-Policy, and CSP with frame-ancestors 'none' all present on /*."
);
