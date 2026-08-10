// Regression coverage for the CSP/bootstrap defect that left all 6
// category pages and all 4 static legal pages blank in production: their
// bootstrap was a bare inline `<script type="module">` block, which this
// app's own CSP (script-src has no 'unsafe-inline', no nonce, no hash)
// silently blocks. Fixed by moving to the same external
// `<script type="module" src="...">` pattern every other page already
// uses. This script proves, statically, that the fix holds and that the
// CSP widening added alongside it (for Cloudflare's injected Web
// Analytics beacon) stayed narrow. See _headers' own comment for why
// each origin below is there.
import { readFileSync } from "node:fs";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";
import { walk } from "./lib/walk.js";

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const ROOT = join(SCRIPT_DIR, "..", "..");

let failures = 0;

function fail(message) {
    failures++;
    console.error(`✗ ${message}`);
}

// --- 1. No page anywhere in pages/ relies on a bare inline module
// script. A <script type="module"> with no src attribute is exactly
// the pattern CSP blocks; this is a repo-wide check, not just the 10
// pages already known to have used it, so a future page can't
// reintroduce the same defect unnoticed.
//
// Detection is attribute-order- and whitespace-independent: it parses
// each <script ...> opening tag's full attribute list rather than
// matching one fixed literal sequence, so `<script defer type="module">`,
// `<script type="module" defer>`, extra whitespace, single quotes, etc.
// are all still caught — CSP itself doesn't care what order the
// attributes are in, so the check can't either. A script only escapes
// the check by having a `src` attribute (i.e. actually being external).
// ---------------------------------------------------------------------
const SCRIPT_OPEN_TAG = /<script\b([^>]*)>/gi;

function findBlockedInlineModuleScripts(html) {
    const found = [];
    SCRIPT_OPEN_TAG.lastIndex = 0;
    let match;
    while ((match = SCRIPT_OPEN_TAG.exec(html))) {
        const attrs = match[1];
        if (/(?:^|\s)src\s*=/i.test(attrs)) continue;
        const typeMatch = attrs.match(/(?:^|\s)type\s*=\s*(?:["']([^"']*)["']|(\S+))/i);
        const typeValue = typeMatch ? (typeMatch[1] ?? typeMatch[2]).trim().toLowerCase() : null;
        if (typeValue === "module") {
            found.push(match[0]);
        }
    }
    return found;
}

// Self-test the detector itself against known attribute-order/whitespace
// variants before relying on it below — so a future edit to the parsing
// logic can't silently regress coverage without a visible failure here.
const INLINE_MODULE_SCRIPT_FIXTURES = [
    { html: '<script type="module"></script>', blocked: true },
    { html: "<script type='module'></script>", blocked: true },
    { html: '<script  type="module" ></script>', blocked: true },
    { html: '<script defer type="module"></script>', blocked: true },
    { html: '<script type="module" defer></script>', blocked: true },
    { html: '<script async defer type="module" id="x"></script>', blocked: true },
    { html: '<script\n    type="module"\n></script>', blocked: true },
    { html: "<script type=module></script>", blocked: true },
    { html: '<script type="module" src="./bootstrap.js"></script>', blocked: false },
    { html: '<script defer src="./bootstrap.js" type="module"></script>', blocked: false },
    { html: '<script src="./bootstrap.js"></script>', blocked: false },
    { html: '<script data-type="module"></script>', blocked: false },
    { html: '<script src="./data-src.js" type="module"></script>', blocked: false },
    { html: "<script>console.log(1)</script>", blocked: false },
    { html: '<script type="text/javascript"></script>', blocked: false }
];

for (const { html, blocked } of INLINE_MODULE_SCRIPT_FIXTURES) {
    const isBlocked = findBlockedInlineModuleScripts(html).length > 0;
    if (isBlocked !== blocked) {
        fail(`inline-module-script detector self-test failed for ${JSON.stringify(html)} — expected blocked=${blocked}, got ${isBlocked}`);
    }
}

const htmlFiles = walk(join(ROOT, "pages"), (name) => name.endsWith(".html")).sort();

for (const file of htmlFiles) {
    const html = readFileSync(file, "utf8");
    if (findBlockedInlineModuleScripts(html).length > 0) {
        fail(`${relative(ROOT, file)} bootstraps via a bare inline <script type="module"> — CSP's script-src blocks this; use <script type="module" src="..."> instead`);
    }
}

// --- 2. The 6 category pages and 4 legal pages specifically reference
// the new shared external entry points (not just "some" external
// script — the *right* one, so drift back to a per-page duplicate is
// also caught). --------------------------------------------------------
const CATEGORY_PAGES = [
    "pc-builds", "desk-setups", "arduino", "robotics", "3d-printing", "home-labs"
].map((name) => join(ROOT, "pages", "categories", `${name}.html`));

const LEGAL_PAGES = [
    "terms", "privacy", "community-guidelines", "affiliate-disclosure"
].map((name) => join(ROOT, "pages", "legal", `${name}.html`));

for (const file of CATEGORY_PAGES) {
    const html = readFileSync(file, "utf8");
    if (!html.includes('src="../../js/pages/categories/bootstrap.js"')) {
        fail(`${relative(ROOT, file)} does not reference js/pages/categories/bootstrap.js`);
    }
}

for (const file of LEGAL_PAGES) {
    const html = readFileSync(file, "utf8");
    if (!html.includes('src="../../js/pages/legal/bootstrap.js"')) {
        fail(`${relative(ROOT, file)} does not reference js/pages/legal/bootstrap.js`);
    }
}

// --- 3. The shared bootstrap files themselves exist and call the
// expected functions with a sane path prefix (a lightweight structural
// check — tests/categoryAndLegalBootstrap.test.html covers actual
// call behavior against a real DOM). -----------------------------------
const categoryBootstrap = readFileSync(join(ROOT, "js", "pages", "categories", "bootstrap.js"), "utf8");
for (const needle of ['loadNavbar("../../")', 'loadFooter("../../")', 'renderCategoryPage("../../")']) {
    if (!categoryBootstrap.includes(needle)) {
        fail(`js/pages/categories/bootstrap.js is missing ${needle}`);
    }
}

const legalBootstrap = readFileSync(join(ROOT, "js", "pages", "legal", "bootstrap.js"), "utf8");
for (const needle of ['loadNavbar("../../")', 'loadFooter("../../")']) {
    if (!legalBootstrap.includes(needle)) {
        fail(`js/pages/legal/bootstrap.js is missing ${needle}`);
    }
}
if (legalBootstrap.includes("renderCategoryPage")) {
    fail("js/pages/legal/bootstrap.js should not reference renderCategoryPage — legal pages have no per-category rendering");
}

// --- 4. The navbar search input has an explicit, visible
// :focus-visible treatment. -------------------------------------------
const navbarCss = readFileSync(join(ROOT, "css", "layout", "navbar.css"), "utf8");
const searchFocusMatch = navbarCss.match(/\.search-bar:focus-visible\s*\{([^}]*)\}/);

if (!searchFocusMatch) {
    fail("css/layout/navbar.css has no .search-bar:focus-visible rule");
} else if (!/box-shadow\s*:\s*var\(--focus-ring\)/.test(searchFocusMatch[1])) {
    fail(".search-bar:focus-visible does not set box-shadow: var(--focus-ring)");
}

// --- 5. CSP contains only the intended, narrow analytics allowances —
// present where required, absent of anything broader. -------------------
const headers = readFileSync(join(ROOT, "_headers"), "utf8");
const cspLine = headers.split("\n").find((line) => line.includes("Content-Security-Policy:"));

if (!cspLine) {
    fail("_headers has no Content-Security-Policy line");
} else {
    const directives = Object.fromEntries(
        cspLine
            .slice(cspLine.indexOf("Content-Security-Policy:") + "Content-Security-Policy:".length)
            .split(";")
            .map((part) => part.trim())
            .filter(Boolean)
            .map((part) => {
                const [name, ...values] = part.split(/\s+/);
                return [name, values];
            })
    );

    const scriptSrc = directives["script-src"] ?? [];
    const connectSrc = directives["connect-src"] ?? [];

    if (!scriptSrc.includes("https://static.cloudflareinsights.com")) {
        fail("script-src is missing https://static.cloudflareinsights.com (Cloudflare Web Analytics beacon script)");
    }
    if (!connectSrc.includes("https://cloudflareinsights.com")) {
        fail("connect-src is missing https://cloudflareinsights.com (Cloudflare Web Analytics beacon reporting)");
    }
    if (scriptSrc.some((v) => v.includes("unsafe-inline"))) {
        fail("script-src contains 'unsafe-inline' — this defeats the point of the bootstrap-script fix");
    }
    if (scriptSrc.some((v) => v === "*" || v.startsWith("*."))) {
        fail("script-src contains an unjustified wildcard");
    }
    // Sanity: confirm the pre-existing directives weren't accidentally
    // dropped while widening these two.
    for (const [directive, expected] of [
        ["script-src", "'self'"],
        ["script-src", "https://cdn.jsdelivr.net"],
        ["connect-src", "'self'"],
        ["connect-src", "https://xpxjqyraizntbtijzoyp.supabase.co"]
    ]) {
        if (!(directives[directive] ?? []).includes(expected)) {
            fail(`${directive} lost its existing ${expected} allowance`);
        }
    }

    const styleSrc = directives["style-src"] ?? [];
    if (styleSrc.some((v) => v.includes("unsafe-inline"))) {
        fail("style-src contains 'unsafe-inline' — the renderTechnologyBreakdown.js fix exists specifically to avoid needing this");
    }
}

// --- 6. No JS file anywhere in js/ sets inline styles through any
// CSP-blocked pathway: a literal style="..."/style='...' HTML
// attribute in a template string, setAttribute("style", ...), or
// .style.cssText assignment. All three populate the same style-src-attr-
// governed attribute a static style="" would, and were empirically
// confirmed blocked under the real production CSP (see
// renderTechnologyBreakdown.js's own header comment for the exact
// verification). Deliberately does NOT flag `.style.setProperty(...)`
// or `.style.<camelCasedProperty> = value` — confirmed NOT blocked by
// the same test, and this is the pattern the fix (and this repo's
// established convention — see renderCategoryPage.js,
// renderSpecificationsSection.js) uses instead. Repo-wide, not just
// renderTechnologyBreakdown.js, so this can't quietly regress anywhere
// else either. ------------------------------------------------------
const STYLE_ATTR_PATTERNS = [
    { name: "style=\"...\"/style='...' HTML attribute", regex: /\bstyle\s*=\s*["'`]/ },
    { name: "setAttribute(\"style\", ...)", regex: /setAttribute\(\s*["'`]style["'`]/i },
    { name: ".style.cssText assignment", regex: /\.style\.cssText\s*=/ }
];

const jsFiles = walk(join(ROOT, "js"), (name) => name.endsWith(".js")).sort();

for (const file of jsFiles) {
    const lines = readFileSync(file, "utf8").split("\n");
    lines.forEach((line, i) => {
        const codeOnly = line.split("//")[0];
        for (const { name, regex } of STYLE_ATTR_PATTERNS) {
            if (regex.test(codeOnly)) {
                fail(`${relative(ROOT, file)}:${i + 1} uses ${name} — CSP's style-src blocks this; use element.style.setProperty()/element.style.<property> = value instead`);
            }
        }
    });
}

if (failures > 0) {
    console.error(`\n${failures} CSP/bootstrap check(s) failed.`);
    process.exit(1);
}

console.log(
    `CSP/bootstrap checks passed — ${htmlFiles.length} pages scanned for inline bootstrap scripts, ` +
    `${CATEGORY_PAGES.length} category + ${LEGAL_PAGES.length} legal pages verified on the shared entry points, ` +
    `${jsFiles.length} JS files scanned for CSP-blocked inline-style patterns, ` +
    "search-input focus-visible rule present, CSP analytics allowances narrow and complete."
);
