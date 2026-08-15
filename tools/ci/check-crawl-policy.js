// Regression coverage for the crawl/noindex policy: which pages this app
// declares private (because they show only signed-in content, or exist
// purely as an auth-flow utility with no unique indexable content) must
// consistently carry BOTH <meta name="robots" content="noindex"> AND a
// matching robots.txt Disallow entry — this app's established combination
// (see robots.txt's own history: workshop/settings/notifications/
// moderation/login/signup/build-edit already do both). Before this PR,
// pages/feedback.html and pages/my-feedback.html had the noindex meta tag
// but no robots.txt entry — an inconsistency this check exists to catch
// and prevent from recurring.
//
// IMPORTANT SEO SEMANTICS NOTE — this check enforces Specbound's chosen
// policy, it does NOT claim robots.txt Disallow by itself de-indexes a
// page. Those are different mechanisms: Disallow tells a well-behaved
// crawler not to *fetch* a URL at all (saving crawl budget, and for a
// client-side-rendered SPA shell, preventing a crawler from ever seeing
// what an anonymous visitor sees before the auth redirect fires); noindex
// tells a crawler that DID fetch the page not to include it in search
// results. A URL that is Disallow'd can still end up listed by a search
// engine with a bare URL (no title/snippet) if something else links to
// it, precisely BECAUSE Disallow prevented the crawler from ever reading
// its noindex tag. Specbound accepts that known tradeoff deliberately for
// these specific pages (none of them are meant to be linked from outside
// the signed-in app, and none render meaningful content for a logged-out
// visitor to snippet in the first place) — this check verifies the
// declared policy is applied consistently, not that it is the only
// theoretically possible one.
//
// Three explicit, human-reviewed classifications below, plus one
// auto-detection pass so a genuinely new gated page can't quietelly slip
// through unclassified (see part 2).
import { existsSync, readFileSync, readdirSync } from "node:fs";
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

// --- Explicit, reviewable policy lists ----------------------------------
//
// GATED_PAGES: requireAuth() is called unconditionally as part of the
// page's own load sequence (not deferred to a later user action), so an
// anonymous visitor — or crawler — never sees real content, only a
// redirect to login.html. Verified by hand for each entry below by
// reading the page's bootstrap JS; see the comment on each.
const GATED_PAGES = [
    "pages/workshop.html",       // js/pages/workshop/loadWorkshop.js calls requireAuth() at module top level
    "pages/feedback.html",       // js/pages/feedback/loadFeedbackQueue.js calls requireAuth() at module top level
    "pages/my-feedback.html",    // js/pages/myFeedback/loadMyFeedback.js calls requireAuth() at module top level
    "pages/moderation.html",     // js/pages/moderation/loadModerationQueue.js calls requireAuth() at module top level
    "pages/notifications.html",  // js/pages/notifications/loadNotifications.js calls requireAuth() at module top level
    "pages/settings.html",       // js/pages/settings/app.js calls requireAuth() at module top level
    "pages/build/edit.html"      // js/pages/editor/app.js's initEditor() calls requireAuth() before any draft loads
];

// ACTION_GATED_PUBLIC_PAGES: requireAuth() appears somewhere in the page's
// script graph, but only inside a user-action handler (e.g. a form submit
// listener) — the page itself renders real, meaningful content for an
// anonymous visitor and is deliberately kept public/crawlable (it carries
// a real <link rel="canonical"> and OG tags, unlike every GATED_PAGES
// entry). Only sign-in is required to actually *use* the page's action,
// not to view it.
const ACTION_GATED_PUBLIC_PAGES = [
    "pages/upload.html" // requireAuth() only runs inside the createDraftForm submit handler
];

// PRIVATE_UTILITY_PAGES: not auth-gated at all (usable while signed out,
// by definition), but declared non-indexable because they're transient
// auth-flow utility pages with no unique content worth ranking — the same
// category login.html/signup.html were already in.
const PRIVATE_UTILITY_PAGES = [
    "pages/login.html",
    "pages/signup.html",
    "pages/forgotPassword.html",
    "pages/updatePassword.html"
];

// NOINDEX_WITHOUT_DISALLOW: pages that must carry noindex but must NOT be
// listed in robots.txt. 404.html is Cloudflare Pages' custom error-page
// template — real requests that hit it already receive an HTTP 404
// status, which is itself sufficient signal to any crawler; disallowing
// the template file would serve no purpose (nothing ever legitimately
// links to /404.html as a URL) and could only ever cause confusion.
const NOINDEX_WITHOUT_DISALLOW = ["404.html"];

// A representative sample of pages that must always stay public/
// crawlable — this check fails loudly if robots.txt ever ends up
// Disallow-ing any of these, which would otherwise be a silent,
// easy-to-miss SEO regression (an overly broad Disallow line added for
// one gated page accidentally matching real content).
const MUST_STAY_PUBLIC = [
    "index.html",
    "pages/explore.html",
    "pages/search.html",
    "pages/profile.html",
    "pages/upload.html",
    "pages/followers.html",
    "pages/following.html",
    "pages/build/build.html",
    "pages/categories/pc-builds.html",
    "pages/categories/desk-setups.html",
    "pages/categories/arduino.html",
    "pages/categories/robotics.html",
    "pages/categories/3d-printing.html",
    "pages/categories/home-labs.html",
    "pages/legal/terms.html",
    "pages/legal/privacy.html",
    "pages/legal/community-guidelines.html",
    "pages/legal/affiliate-disclosure.html"
];

// --- Helpers -------------------------------------------------------------

function toSitePath(repoRelativePath) {
    return "/" + repoRelativePath.replace(/\\/g, "/");
}

const NOINDEX_REGEX = /<meta\s+name=["']robots["']\s+content=["'][^"']*\bnoindex\b[^"']*["']/i;

function hasNoindexMeta(html) {
    return NOINDEX_REGEX.test(html);
}

// Self-test the noindex detector against known-shape fixtures before
// relying on it below, so a future edit to the regex can't silently
// regress coverage without a visible failure here.
const NOINDEX_FIXTURES = [
    { html: '<meta name="robots" content="noindex">', matches: true },
    { html: "<meta name='robots' content='noindex'>", matches: true },
    { html: '<meta name="robots" content="noindex, nofollow">', matches: true },
    { html: '<meta name="ROBOTS" content="NOINDEX">', matches: true },
    { html: '<meta name="robots" content="index, follow">', matches: false },
    { html: '<meta name="description" content="noindex mentioned in prose, not as a directive">', matches: false },
    { html: "<title>No robots meta on this page</title>", matches: false }
];

for (const { html, matches } of NOINDEX_FIXTURES) {
    if (hasNoindexMeta(html) !== matches) {
        fail(`noindex detector self-test failed for ${JSON.stringify(html)} — expected matches=${matches}`);
    }
}

// --- Parse robots.txt's Disallow lines -----------------------------------

const robotsTxt = readFileSync(join(ROOT, "robots.txt"), "utf8");
const disallowedPaths = new Set(
    robotsTxt
        .split(/\r?\n/)
        .map((line) => line.match(/^Disallow:\s*(\S+)/i))
        .filter(Boolean)
        .map((m) => m[1])
);

// --- Part 1: every explicitly declared private page has noindex AND a
// matching robots.txt Disallow entry; every declared-public page is
// confirmed NOT disallowed. --------------------------------------------

for (const relPath of [...GATED_PAGES, ...PRIVATE_UTILITY_PAGES]) {
    const fullPath = join(ROOT, relPath);
    if (!existsSync(fullPath)) {
        fail(`declared private page ${relPath} no longer exists — remove it from check-crawl-policy.js's policy lists`);
        continue;
    }
    const html = readFileSync(fullPath, "utf8");
    const sitePath = toSitePath(relPath);

    if (!hasNoindexMeta(html)) {
        fail(`${relPath} is declared private but has no <meta name="robots" content="noindex">`);
    }
    if (!disallowedPaths.has(sitePath)) {
        fail(`${relPath} is declared private but robots.txt has no "Disallow: ${sitePath}" line`);
    }
}

for (const relPath of NOINDEX_WITHOUT_DISALLOW) {
    const fullPath = join(ROOT, relPath);
    const html = readFileSync(fullPath, "utf8");
    if (!hasNoindexMeta(html)) {
        fail(`${relPath} is expected to carry noindex (see NOINDEX_WITHOUT_DISALLOW) but doesn't`);
    }
}

for (const relPath of [...MUST_STAY_PUBLIC, ...ACTION_GATED_PUBLIC_PAGES]) {
    const sitePath = toSitePath(relPath);
    if (disallowedPaths.has(sitePath)) {
        fail(`${relPath} must stay crawlable but robots.txt disallows "${sitePath}" — this looks like an accidental over-broad Disallow`);
    }
    const fullPath = join(ROOT, relPath);
    if (existsSync(fullPath) && hasNoindexMeta(readFileSync(fullPath, "utf8"))) {
        fail(`${relPath} must stay indexable but carries <meta name="robots" content="noindex">`);
    }
}

// --- Part 2: auto-detect any page whose script graph calls requireAuth()
// but isn't classified in GATED_PAGES or ACTION_GATED_PUBLIC_PAGES above —
// this is what lets the check catch a genuinely new gated page, not just
// regressions on the ones already known about. Mirrors the page -> JS
// resolution approach tools/ci/check-auth-redirects.js already uses. ------

function resolveLocalRef(sourceFile, ref) {
    const clean = ref.split("#")[0].split("?")[0].trim();
    if (!clean || !(clean.startsWith(".") || clean.startsWith("/"))) return null;
    const baseDir = clean.startsWith("/") ? ROOT : dirname(sourceFile);
    const relTarget = clean.startsWith("/") ? clean.slice(1) : clean;
    return join(baseDir, relTarget);
}

const htmlFiles = walk(join(ROOT, "pages"), (name) => name.endsWith(".html")).sort();
const jsFiles = walk(join(ROOT, "js"), (name) => name.endsWith(".js")).sort();

const importRegex = /\bfrom\s+["']([^"']+)["']/g;
const importsCache = new Map();

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
const AUTH_FILE = join(ROOT, "js", "core", "auth.js");

function pageUsesRequireAuth(htmlFile) {
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

        if (current === AUTH_FILE) continue; // the definition itself (matches its own name in the function signature), not a call site

        let jsText;
        try {
            jsText = readFileSync(current, "utf8");
        } catch {
            continue;
        }
        if (/\brequireAuth\s*\(/.test(jsText)) return true;

        for (const dep of getLocalImports(current)) {
            if (!visited.has(dep)) queue.push(dep);
        }
    }
    return false;
}

const CLASSIFIED = new Set([...GATED_PAGES, ...ACTION_GATED_PUBLIC_PAGES]);

let pagesScanned = 0;
for (const htmlFile of htmlFiles) {
    pagesScanned++;
    const relPath = relative(ROOT, htmlFile).replace(/\\/g, "/");
    if (!pageUsesRequireAuth(htmlFile)) continue;
    if (!CLASSIFIED.has(relPath)) {
        fail(
            `${relPath} reaches a requireAuth() call somewhere in its script graph but isn't classified in ` +
            "check-crawl-policy.js's GATED_PAGES or ACTION_GATED_PUBLIC_PAGES — review whether requireAuth() " +
            "blocks the page's own load (add to GATED_PAGES, then give it noindex + a robots.txt Disallow line) " +
            "or only gates a later user action (add to ACTION_GATED_PUBLIC_PAGES)"
        );
    }
}

// Self-check: every page this script previously classified as gated must
// still actually exist under pages/ and still be found by the walk above
// — guards against a classified path being silently stale (e.g. a rename)
// where the Part 1 loop above would otherwise just report "no longer
// exists" without this extra cross-check ever running its Part 2 half.
for (const relPath of GATED_PAGES) {
    if (!htmlFiles.some((f) => relative(ROOT, f).replace(/\\/g, "/") === relPath)) {
        fail(`GATED_PAGES lists ${relPath}, but no such file was found under pages/`);
    }
}

if (failures > 0) {
    console.error(`\n${failures} crawl/noindex policy issue(s) found.`);
    process.exit(1);
}

console.log(
    `Crawl/noindex policy OK — ${GATED_PAGES.length} gated pages and ${PRIVATE_UTILITY_PAGES.length} private ` +
    `utility pages verified (noindex + robots.txt Disallow both present), ${NOINDEX_WITHOUT_DISALLOW.length} ` +
    `noindex-only exception confirmed, ${MUST_STAY_PUBLIC.length + ACTION_GATED_PUBLIC_PAGES.length} public ` +
    `pages confirmed crawlable, ${pagesScanned} pages/ HTML files scanned for unclassified requireAuth() usage.`
);
