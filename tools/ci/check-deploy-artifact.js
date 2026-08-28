// Validates the actual deployment artifact (dist/), not just the repository.
//
// Runs the real build.sh, then asserts:
//   1. dist/ exists and its top-level entries are EXACTLY the approved
//      public-runtime allowlist — nothing missing, nothing extra.
//   2. None of the excluded, repository-only categories (docs/, supabase/,
//      tests/, tools/, .github/, .claude/, README.md, build.sh, package
//      files) exist anywhere in dist/, at any depth.
//   3. The required baseline files (_headers, 404.html, robots.txt,
//      sitemap.xml, manifest.webmanifest) are present.
//   4. Every local HTML src/href, CSS url(), and JS import/export reference
//      inside dist/ resolves to a real file WITHIN dist/ — not merely
//      somewhere in the repository root — so a reference into an excluded
//      category (which would resolve against the repo but 404 in
//      production) is caught here, not discovered live.
//
// This is what actually ships to Cloudflare Pages, so this check — not
// check-references.js's repo-root scan — is the source of truth for what
// production will serve.
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync, readdirSync, rmSync } from "node:fs";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const ROOT = join(SCRIPT_DIR, "..", "..");
const DIST = join(ROOT, "dist");

const problems = [];

// --- 1. Run the real build ---------------------------------------------
console.log("Running build.sh...");
try {
    execFileSync("sh", ["build.sh"], { cwd: ROOT, stdio: "inherit" });
} catch (err) {
    console.error("build.sh failed:", err.message);
    process.exit(1);
}

if (!existsSync(DIST)) {
    console.error(`✗ ${DIST} does not exist after running build.sh.`);
    process.exit(1);
}

// --- 2. Exact top-level allowlist ---------------------------------------
// Kept independent of build.sh's own allowlist constant so drift between
// what build.sh copies and what this check expects is itself a failure,
// not silently assumed consistent.
const EXPECTED_TOP_LEVEL = [
    "404.html",
    "_headers",
    "assets",
    "css",
    "design-system.html",
    "index.html",
    "js",
    "manifest.webmanifest",
    "pages",
    "robots.txt",
    "sitemap.xml"
].sort();

const actualTopLevel = readdirSync(DIST).sort();

for (const expected of EXPECTED_TOP_LEVEL) {
    if (!actualTopLevel.includes(expected)) {
        problems.push(`Missing required top-level entry in dist/: ${expected}`);
    }
}
for (const actual of actualTopLevel) {
    if (!EXPECTED_TOP_LEVEL.includes(actual)) {
        problems.push(`Unexpected top-level entry in dist/: ${actual} (not on the approved allowlist)`);
    }
}

// --- 3. Excluded categories absent anywhere in dist/ ---------------------
const FORBIDDEN_NAMES = new Set([
    "docs",
    "supabase",
    "tests",
    "tools",
    ".github",
    ".claude",
    "README.md",
    "build.sh",
    "package.json",
    "package-lock.json",
    ".gitignore",
    ".git"
]);

function walkAll(dir, results = []) {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
        const full = join(dir, entry.name);
        if (FORBIDDEN_NAMES.has(entry.name)) {
            problems.push(`Excluded/repository-only entry found in dist/: ${relative(DIST, full)}`);
            // Still descend in case something forbidden is nested inside
            // another forbidden entry — report every occurrence found.
        }
        if (entry.isDirectory()) {
            walkAll(full, results);
        } else {
            results.push(full);
        }
    }
    return results;
}

const distFiles = walkAll(DIST);

// --- 4. Required baseline files present ----------------------------------
for (const required of ["_headers", "404.html", "robots.txt", "sitemap.xml", "manifest.webmanifest"]) {
    if (!existsSync(join(DIST, required))) {
        problems.push(`Required baseline file missing from dist/: ${required}`);
    }
}

// --- 5. Every local reference resolves WITHIN dist/ -----------------------
// Same reference-extraction approach as check-references.js, but rooted at
// dist/ so a reference that only resolves against the repo root (e.g. into
// docs/ or supabase/) is caught here as a real production-breaking bug.
function isExternalOrSkippable(ref) {
    return (
        ref === "" ||
        /^[a-z][a-z0-9+.-]*:/i.test(ref) ||
        ref.startsWith("//") ||
        ref.startsWith("#")
    );
}

function stripSuffix(ref) {
    return ref.split("#")[0].split("?")[0];
}

function existsCaseSensitive(fullPath) {
    if (!existsSync(fullPath)) return false;
    const dir = dirname(fullPath);
    const base = fullPath.slice(dir.length + 1);
    try {
        return readdirSync(dir).includes(base);
    } catch {
        return false;
    }
}

const FORBIDDEN_PATH_SEGMENTS = ["docs/", "supabase/", "tests/", "tools/", ".github/", ".claude/"];

function checkRef(sourceFile, ref, context) {
    const clean = stripSuffix(ref.trim());
    if (isExternalOrSkippable(clean)) return;

    for (const segment of FORBIDDEN_PATH_SEGMENTS) {
        if (clean.includes(segment)) {
            problems.push(
                `${relative(DIST, sourceFile)}: reference "${ref}" points into an excluded category (${segment}) — ${context.trim()}`
            );
        }
    }

    const baseDir = clean.startsWith("/") ? DIST : dirname(sourceFile);
    const relTarget = clean.startsWith("/") ? clean.slice(1) : clean;
    const target = join(baseDir, relTarget);
    if (!existsCaseSensitive(target)) {
        problems.push(
            `${relative(DIST, sourceFile)}: reference "${ref}" does not resolve within dist/ — ${context.trim()}`
        );
    }
}

const htmlFiles = distFiles.filter((f) => f.endsWith(".html")).sort();
const attrRegex = /\b(?:src|href)\s*=\s*"([^"]*)"/g;
for (const file of htmlFiles) {
    const text = readFileSync(file, "utf8");
    for (const m of text.matchAll(attrRegex)) checkRef(file, m[1], m[0]);
}

const cssFiles = distFiles.filter((f) => f.endsWith(".css")).sort();
const urlRegex = /url\(\s*["']?([^"')]+)["']?\s*\)/g;
for (const file of cssFiles) {
    const text = readFileSync(file, "utf8");
    for (const m of text.matchAll(urlRegex)) checkRef(file, m[1], m[0]);
}

const jsFiles = distFiles.filter((f) => f.endsWith(".js")).sort();
const importRegex = /\bfrom\s+["']([^"']+)["']|\bimport\(\s*["']([^"']+)["']\s*\)/g;
for (const file of jsFiles) {
    const text = readFileSync(file, "utf8");
    for (const m of text.matchAll(importRegex)) {
        const spec = m[1] ?? m[2];
        if (!spec.startsWith(".") && !spec.startsWith("/")) continue;
        checkRef(file, spec, m[0]);
    }
}

// --- Report ----------------------------------------------------------------
if (problems.length > 0) {
    console.error(`\nFound ${problems.length} deployment-artifact problem(s):\n`);
    for (const p of problems) console.error(`  ✗ ${p}`);
    console.error("");
    process.exit(1);
}

console.log(
    `\ndist/ artifact OK — ${actualTopLevel.length} top-level entries match the approved allowlist exactly, ` +
        `no excluded categories found, ${htmlFiles.length} HTML / ${cssFiles.length} CSS / ${jsFiles.length} JS files ` +
        `scanned with every local reference resolving inside dist/.`
);

// Clean up: this check regenerates dist/ itself, so leave no build output
// behind for a local run to accidentally rely on or commit.
rmSync(DIST, { recursive: true, force: true });
