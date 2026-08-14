// Regression guard for the exact bug this hotfix fixed: a requireAuth()
// call site whose literal redirect path resolves correctly for one page's
// serving depth but not another. requireAuth() (js/core/auth.js) does a
// plain `window.location.href = redirectPath`, so a relative path like
// "../login.html" is only ever correct for pages at the one specific
// directory depth its author was thinking about when they wrote it — a
// page one level deeper or shallower silently gets a dead link instead of
// a build-time or type error.
//
// This can't be caught by check-references.js: that script validates HTML
// src/href, CSS url(), and JS import specifiers, but a string literal
// passed as a plain function argument is none of those.
//
// Approach: for every requireAuth(...) call site with a string-literal
// argument, find every HTML page that actually serves the JS file it's in
// (by resolving each page's <script type="module"> entry point and then
// following that entry's static import graph, mirroring how a browser
// would actually load it), then resolve the redirect path against each
// such page's real directory and confirm it points at a file that exists
// — the identical case-sensitive-on-Linux existence check
// check-references.js already uses, for the same reason (Cloudflare
// Pages' production host is case-sensitive; this dev machine may not be).
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { dirname, extname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";
import { walk } from "./lib/walk.js";

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const ROOT = join(SCRIPT_DIR, "..", "..");

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

function resolveLocalRef(sourceFile, ref) {
    const clean = ref.split("#")[0].split("?")[0].trim();
    if (!clean || !(clean.startsWith(".") || clean.startsWith("/"))) return null; // external/bare specifier
    const baseDir = clean.startsWith("/") ? ROOT : dirname(sourceFile);
    const relTarget = clean.startsWith("/") ? clean.slice(1) : clean;
    return join(baseDir, relTarget);
}

// --- Build the real page -> transitively-imported-JS-file graph --------

const htmlFiles = walk(ROOT, (name) => name.endsWith(".html")).sort();
const jsFiles = walk(ROOT, (name) => name.endsWith(".js")).sort();

const importRegex = /\bfrom\s+["']([^"']+)["']/g;
const importsCache = new Map(); // jsFile -> string[] of resolved local import targets

function getLocalImports(jsFile) {
    if (importsCache.has(jsFile)) return importsCache.get(jsFile);
    let text;
    try {
        text = readFileSync(jsFile, "utf8");
    } catch {
        importsCache.set(jsFile, []);
        return [];
    }
    const targets = [];
    for (const m of text.matchAll(importRegex)) {
        const resolved = resolveLocalRef(jsFile, m[1]);
        if (resolved) targets.push(resolved);
    }
    importsCache.set(jsFile, targets);
    return targets;
}

const scriptSrcRegex = /<script\b[^>]*\bsrc\s*=\s*"([^"]+)"[^>]*>/g;

// jsFile -> Set<htmlFile> of every page that actually serves it.
const servedBy = new Map();

for (const htmlFile of htmlFiles) {
    const text = readFileSync(htmlFile, "utf8");
    const entryPoints = [];
    for (const m of text.matchAll(scriptSrcRegex)) {
        const resolved = resolveLocalRef(htmlFile, m[1]);
        if (resolved && resolved.endsWith(".js")) entryPoints.push(resolved);
    }

    const visited = new Set();
    const queue = [...entryPoints];
    while (queue.length > 0) {
        const current = queue.pop();
        if (visited.has(current)) continue;
        visited.add(current);

        if (!servedBy.has(current)) servedBy.set(current, new Set());
        servedBy.get(current).add(htmlFile);

        for (const dep of getLocalImports(current)) {
            if (!visited.has(dep)) queue.push(dep);
        }
    }
}

// --- Find every requireAuth(...) call site ------------------------------

// Only string-literal arguments are checked — anything dynamically built
// (a template literal, a variable) isn't a redirect-path typo this check
// can meaningfully catch, and none of this codebase's real call sites do
// that today.
const callRegex = /requireAuth\(\s*(?:"([^"]*)")?\s*\)/g;

const authFile = join(ROOT, "js", "core", "auth.js");
const authSrc = readFileSync(authFile, "utf8");
const defaultMatch = authSrc.match(/function\s+requireAuth\(\s*redirectPath\s*=\s*"([^"]*)"/);
const DEFAULT_REDIRECT_PATH = defaultMatch ? defaultMatch[1] : null;

const problems = [];
let callSitesChecked = 0;

for (const jsFile of jsFiles) {
    if (jsFile === authFile) continue; // the definition itself, not a call site
    const text = readFileSync(jsFile, "utf8");
    for (const m of text.matchAll(callRegex)) {
        const redirectPath = m[1] ?? DEFAULT_REDIRECT_PATH;
        if (redirectPath === null) continue; // couldn't determine a path to check

        const pages = servedBy.get(jsFile);
        if (!pages || pages.size === 0) continue; // not reachable from any real page (e.g. dead code, or only referenced from tests)

        for (const page of pages) {
            callSitesChecked++;
            const baseDir = redirectPath.startsWith("/") ? ROOT : dirname(page);
            const relTarget = redirectPath.startsWith("/") ? redirectPath.slice(1) : redirectPath;
            const target = join(baseDir, relTarget);
            if (!existsCaseSensitive(target)) {
                problems.push({
                    jsFile: relative(ROOT, jsFile),
                    page: relative(ROOT, page),
                    redirectPath,
                    resolvedTo: relative(ROOT, target)
                });
            }
        }
    }
}

if (problems.length > 0) {
    console.error(`Found ${problems.length} broken requireAuth() redirect path(s):\n`);
    for (const p of problems) {
        console.error(
            `  ${p.jsFile}\n` +
            `    requireAuth("${p.redirectPath}") served from ${p.page}\n` +
            `    -> resolves to ${p.resolvedTo}, which does not exist\n`
        );
    }
    process.exit(1);
}

console.log(
    `All requireAuth() redirect paths OK — ${callSitesChecked} (call site x serving page) combination(s) checked ` +
    `across ${htmlFiles.length} HTML pages.`
);
