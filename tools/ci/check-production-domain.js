// Regression coverage for the obsolete `specbound.app` placeholder domain
// reappearing in production-facing metadata. `docs/DEPLOYMENT.md` documents
// it as a pre-launch placeholder that needed a one-time find-and-replace to
// the real production domain, `https://specboundapp.com` — this script
// makes sure that replacement can't silently regress (a page copy-pasted
// from an older page, a new page authored from a stale template, etc.).
//
// Scope is deliberately narrow: every real HTML entry point (all of
// pages/**, plus the three root-level pages) and the two crawler-facing
// files, sitemap.xml and robots.txt. Historical documentation that
// legitimately still describes the old placeholder (docs/DEPLOYMENT.md,
// docs/milestones/MILESTONE_9_PHASE_9E_ARCHITECTURE.md) is intentionally
// out of scope — this check is about what ships to users and crawlers, not
// about rewriting project history.
import { readFileSync } from "node:fs";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";
import { walk } from "./lib/walk.js";

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const ROOT = join(SCRIPT_DIR, "..", "..");

const OBSOLETE_DOMAIN = /specbound\.app/i;

let failures = 0;

function fail(message) {
    failures++;
    console.error(`✗ ${message}`);
}

// Matches obsolete-domain references, line by line, in a block of text.
// Returns [{ line, text }] for every offending line — empty if clean.
// Deliberately requires a literal "." right before "app", so it can never
// match the real domain, specboundapp.com (no dot precedes "app" there).
function findObsoleteDomainRefs(text) {
    return text
        .split("\n")
        .map((line, i) => ({ line: i + 1, text: line }))
        .filter(({ text: line }) => OBSOLETE_DOMAIN.test(line));
}

// Self-test the detector against known obsolete and allowed forms before
// relying on it below, so a future edit to the regex can't silently regress
// coverage (or start false-positiving on the real domain) without a visible
// failure here.
const FIXTURES = [
    { text: '<link rel="canonical" href="https://specbound.app/">', blocked: true },
    { text: '<meta property="og:url" content="https://specbound.app/pages/explore.html">', blocked: true },
    { text: "Sitemap: https://specbound.app/sitemap.xml", blocked: true },
    { text: "SPECBOUND.APP", blocked: true },
    { text: "bare host, no protocol: specbound.app/pages/x", blocked: true },
    { text: '<link rel="canonical" href="https://specboundapp.com/">', blocked: false },
    { text: '<meta property="og:image" content="https://specboundapp.com/assets/brand/og/og-image.png">', blocked: false },
    { text: "Sitemap: https://specboundapp.com/sitemap.xml", blocked: false },
    { text: "no domain mentioned here at all", blocked: false }
];

for (const { text, blocked } of FIXTURES) {
    const isBlocked = findObsoleteDomainRefs(text).length > 0;
    if (isBlocked !== blocked) {
        fail(`obsolete-domain detector self-test failed for ${JSON.stringify(text)} — expected blocked=${blocked}, got ${isBlocked}`);
    }
}

const targets = [
    ...walk(join(ROOT, "pages"), (name) => name.endsWith(".html")).sort(),
    join(ROOT, "index.html"),
    join(ROOT, "404.html"),
    join(ROOT, "design-system.html"),
    join(ROOT, "sitemap.xml"),
    join(ROOT, "robots.txt")
];

for (const file of targets) {
    const text = readFileSync(file, "utf8");
    for (const { line, text: lineText } of findObsoleteDomainRefs(text)) {
        fail(`${relative(ROOT, file)}:${line} still references the obsolete domain — production is https://specboundapp.com: ${lineText.trim()}`);
    }
}

if (failures > 0) {
    console.error(`\n${failures} obsolete-domain issue(s) found.`);
    process.exit(1);
}

console.log(
    `No obsolete "specbound.app" domain references found — ${targets.length} public-facing files scanned ` +
    "(pages/**/*.html, index.html, 404.html, design-system.html, sitemap.xml, robots.txt)."
);
