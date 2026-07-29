// Validates local references resolve to real files on disk:
//   - HTML  src and href attributes
//   - CSS   url() functions, including @import url()
//   - JS    static import/export specifiers and dynamic import() calls
//
// This is a regex-based scan, not a full HTML/CSS/JS parser, so it won't catch
// paths built at runtime (e.g. template-literal imports or `${var}`-constructed
// asset URLs). It skips anything external (http(s)://, //, mailto:, tel:,
// data:, javascript:, bare "#" anchors) and any bare module specifier in JS
// (package names, CDN URLs like the Supabase ESM import) since those aren't
// local files to check.
//
// Existence checks are case-sensitive even on this case-insensitive dev
// filesystem, because the production host (Cloudflare Pages, on Linux) is
// case-sensitive — a reference that only "works" on Windows/macOS by case
// coincidence would 404 in production.
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { dirname, extname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";
import { walk } from "./lib/walk.js";

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const ROOT = join(SCRIPT_DIR, "..", "..");

function isExternalOrSkippable(ref) {
    return (
        ref === "" ||
        /^[a-z][a-z0-9+.-]*:/i.test(ref) || // any URL scheme: http:, https:, mailto:, tel:, data:, javascript:, etc.
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

const problems = [];

function checkRef(sourceFile, ref, context) {
    const clean = stripSuffix(ref.trim());
    if (isExternalOrSkippable(clean)) return;
    const baseDir = clean.startsWith("/") ? ROOT : dirname(sourceFile);
    const relTarget = clean.startsWith("/") ? clean.slice(1) : clean;
    const target = join(baseDir, relTarget);
    if (!existsCaseSensitive(target)) {
        problems.push({ file: relative(ROOT, sourceFile), context: context.trim(), ref });
    }
}

const htmlFiles = walk(ROOT, (name) => name.endsWith(".html")).sort();
const attrRegex = /\b(?:src|href)\s*=\s*"([^"]*)"/g;
for (const file of htmlFiles) {
    const text = readFileSync(file, "utf8");
    for (const m of text.matchAll(attrRegex)) {
        checkRef(file, m[1], m[0]);
    }
}

const cssFiles = walk(ROOT, (name) => name.endsWith(".css")).sort();
const urlRegex = /url\(\s*["']?([^"')]+)["']?\s*\)/g;
for (const file of cssFiles) {
    const text = readFileSync(file, "utf8");
    for (const m of text.matchAll(urlRegex)) {
        checkRef(file, m[1], m[0]);
    }
}

const jsFiles = walk(ROOT, (name) => name.endsWith(".js")).sort();
const importRegex = /\bfrom\s+["']([^"']+)["']|\bimport\(\s*["']([^"']+)["']\s*\)/g;
for (const file of jsFiles) {
    const text = readFileSync(file, "utf8");
    for (const m of text.matchAll(importRegex)) {
        const spec = m[1] ?? m[2];
        if (!spec.startsWith(".") && !spec.startsWith("/")) continue; // bare specifier / CDN import, not a local file
        checkRef(file, spec, m[0]);
    }
}

if (problems.length > 0) {
    console.error(`Found ${problems.length} broken local reference(s):\n`);
    for (const p of problems) {
        console.error(`  ${p.file}\n    ${p.context}  ->  not found: ${p.ref}\n`);
    }
    process.exit(1);
}

console.log(
    `All local references OK — ${htmlFiles.length} HTML, ${cssFiles.length} CSS, ${jsFiles.length} JS files scanned.`
);
