// Regression coverage for the crawl/noindex policy. This app has TWO
// distinct categories of <meta name="robots" content="noindex"> page, and
// they get different robots.txt treatment on purpose — conflating them
// into one blanket rule was a real bug this check now prevents:
//
// - GATED APPLICATION PAGES (Workshop, Settings, Notifications, Moderation,
//   Feedback, My Feedback, the draft editor): require sign-in to show any
//   real content, and their links only ever render in the AUTHENTICATED
//   branch of the navbar (js/core/layout.js) — an anonymous visitor or
//   crawler never sees an <a href> to any of these anywhere on the public
//   site. Disallow-ing them has no discoverability downside, since nothing
//   ever offers a crawler the URL in the first place. These get BOTH
//   noindex AND a robots.txt Disallow line.
//
// - AUTH-FLOW UTILITY PAGES (Login, Sign Up, Forgot Password, Update
//   Password): usable while signed out by definition, and genuinely linked
//   from crawlable surfaces — the navbar's "Sign In" link renders on EVERY
//   public page for a signed-out visitor, and the four pages are statically
//   cross-linked to each other. These get noindex but must NOT be
//   Disallow'd: blocking a page real links point to prevents a crawler
//   from ever fetching it to read its noindex tag, which can leave a bare,
//   snippet-less URL sitting in search results instead of a clean
//   exclusion — the opposite of the intended effect. See
//   docs/DEPLOYMENT.md §11 for the full writeup of why an earlier version
//   of this policy got this wrong (it Disallow'd these four too, on the
//   incorrect claim that nothing outside the signed-in app links to them).
//
// Neither noindex nor Disallow is a security boundary — both are
// voluntary conventions a well-behaved crawler chooses to respect. Every
// page's real content is still gated server-side by Supabase Auth/RLS
// regardless of what any crawler does or doesn't fetch.
//
// Three explicit, human-reviewed classifications below, plus one
// auto-detection pass so a genuinely new gated page can't quietly slip
// through unclassified (see part 2).
import { existsSync, readFileSync } from "node:fs";
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
// reading the page's bootstrap JS; see the comment on each. Policy:
// noindex AND Disallow.
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
// not to view it. Policy: same as MUST_STAY_PUBLIC below.
const ACTION_GATED_PUBLIC_PAGES = [
    "pages/upload.html" // requireAuth() only runs inside the createDraftForm submit handler
];

// AUTH_UTILITY_PAGES: not auth-gated at all (usable while signed out, by
// definition), genuinely linked from crawlable surfaces (see file header),
// declared non-indexable only because they're transient auth-flow pages
// with no unique content worth ranking. Policy: noindex WITHOUT Disallow —
// the opposite Disallow posture from GATED_PAGES, deliberately.
const AUTH_UTILITY_PAGES = [
    "pages/login.html",
    "pages/signup.html",
    "pages/forgotPassword.html",
    "pages/updatePassword.html"
];

// NOINDEX_WITHOUT_DISALLOW: pages that must carry noindex but must NOT be
// listed in robots.txt, for a reason unrelated to AUTH_UTILITY_PAGES'
// linked-ness. 404.html is Cloudflare Pages' custom error-page template —
// real requests that hit it already receive an HTTP 404 status, which is
// itself sufficient signal to any crawler; disallowing the template file
// would serve no purpose (nothing ever legitimately links to /404.html as
// a URL) and could only ever cause confusion.
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

// --- Part 1: every explicitly declared page matches its category's
// required (noindex, Disallow) combination — and every explicitly listed
// path fails LOUDLY if the file doesn't exist, for every list, not just
// GATED_PAGES. A silently-skipped stale entry is exactly the kind of gap
// that lets real coverage quietly erode over time. --------------------

// requirements: { noindex: true|false|null, disallow: true|false|null }
// — null means "not checked for this category" (used for
// NOINDEX_WITHOUT_DISALLOW, which only asserts noindex, and
// MUST_STAY_PUBLIC/ACTION_GATED_PUBLIC_PAGES, which only assert
// not-disallowed).
function checkPages(relPaths, { noindex, disallow }, categoryLabel) {
    for (const relPath of relPaths) {
        const fullPath = join(ROOT, relPath);
        if (!existsSync(fullPath)) {
            fail(`${categoryLabel} lists ${relPath}, but no such file exists — update check-crawl-policy.js's policy lists`);
            continue;
        }
        const sitePath = toSitePath(relPath);
        const isDisallowed = disallowedPaths.has(sitePath);

        if (noindex === true || noindex === false) {
            const html = readFileSync(fullPath, "utf8");
            const hasNoindex = hasNoindexMeta(html);
            if (noindex && !hasNoindex) {
                fail(`${relPath} (${categoryLabel}) is missing <meta name="robots" content="noindex">`);
            } else if (!noindex && hasNoindex) {
                fail(`${relPath} (${categoryLabel}) must stay indexable but carries <meta name="robots" content="noindex">`);
            }
        }

        if (disallow === true && !isDisallowed) {
            fail(`${relPath} (${categoryLabel}) is declared private but robots.txt has no "Disallow: ${sitePath}" line`);
        } else if (disallow === false && isDisallowed) {
            const reason = noindex === true
                // Auth-utility pages: the specific reason Disallow is wrong here is
                // that it hides a real noindex tag from ever being read.
                ? "it is linked from crawlable surfaces, so blocking it prevents a crawler from ever reading its noindex tag (see docs/DEPLOYMENT.md §11)"
                // Genuinely public pages (no noindex at all): Disallow here is just
                // a plain SEO regression, not a noindex-visibility problem.
                : "this looks like an accidental over-broad Disallow line — the page must stay crawlable and indexable";
            fail(`${relPath} (${categoryLabel}) must not be Disallow'd — ${reason}`);
        }
    }
}

checkPages(GATED_PAGES, { noindex: true, disallow: true }, "gated application page");
checkPages(AUTH_UTILITY_PAGES, { noindex: true, disallow: false }, "auth-flow utility page");
checkPages(NOINDEX_WITHOUT_DISALLOW, { noindex: true, disallow: null }, "noindex-only exception");
checkPages(MUST_STAY_PUBLIC, { noindex: false, disallow: false }, "public page");
checkPages(ACTION_GATED_PUBLIC_PAGES, { noindex: false, disallow: false }, "action-gated public page");

// --- Part 2: auto-detect any page whose script graph calls requireAuth()
// but isn't classified in GATED_PAGES or ACTION_GATED_PUBLIC_PAGES above —
// this is what lets the check catch a genuinely new gated page, not just
// regressions on the ones already known about. Mirrors the page -> JS
// resolution approach tools/ci/check-auth-redirects.js already uses.
//
// KNOWN LIMITATION, stated rather than silently assumed away: this graph
// only follows STATIC ES module import specifiers (the getLocalImports()
// regex below). It does not follow dynamic, runtime import calls, so a
// requireAuth() call
// reachable only through a dynamically-imported module would not be
// detected. As of this writing there is exactly one dynamic import in the
// codebase — js/core/layout.js loads js/components/FeedbackModal.js that
// way — and FeedbackModal.js contains no requireAuth() call, verified by
// hand, not assumed, so this limitation has no live effect today. This is
// the same limitation check-auth-redirects.js's page/JS resolution
// already has; not something introduced here, and not full graph
// coverage. (Deliberately not written as literal import-call syntax in
// this comment — tools/ci/check-references.js's reference scanner reads
// JS comments too, and would otherwise try, and fail, to resolve it as a
// real specifier relative to this file's own directory.) ----------------

function stripComments(jsText) {
    // Block comments first (so a `//` that happens to sit inside one
    // doesn't confuse the line-based strip below), then a plain
    // line-based `//`-to-end-of-line strip — the same convention
    // tools/ci/check-csp-bootstrap.js's STYLE_ATTR_PATTERNS check already
    // uses for the same reason: good enough to keep an explanatory
    // comment like "// requireAuth() redirects to login.html itself..."
    // from being mistaken for a real call site, without needing a real
    // JS parser.
    const noBlockComments = jsText.replace(/\/\*[\s\S]*?\*\//g, "");
    return noBlockComments
        .split("\n")
        .map((line) => line.split("//")[0])
        .join("\n");
}

// Self-test the comment stripper before relying on it below.
const COMMENT_FIXTURES = [
    { text: '// requireAuth() redirects to login.html itself when signed out\nconst x = 1;', hasRealCall: false },
    { text: 'const user = await requireAuth("login.html");', hasRealCall: true },
    { text: '// a comment\nconst user = await requireAuth("login.html"); // trailing note', hasRealCall: true },
    { text: '/* block comment mentioning requireAuth( */\nconst x = 1;', hasRealCall: false }
];
for (const { text, hasRealCall } of COMMENT_FIXTURES) {
    const got = /\brequireAuth\s*\(/.test(stripComments(text));
    if (got !== hasRealCall) {
        fail(`comment-stripper self-test failed for ${JSON.stringify(text)} — expected hasRealCall=${hasRealCall}, got ${got}`);
    }
}

function resolveLocalRef(sourceFile, ref) {
    const clean = ref.split("#")[0].split("?")[0].trim();
    if (!clean || !(clean.startsWith(".") || clean.startsWith("/"))) return null;
    const baseDir = clean.startsWith("/") ? ROOT : dirname(sourceFile);
    const relTarget = clean.startsWith("/") ? clean.slice(1) : clean;
    return join(baseDir, relTarget);
}

const htmlFiles = walk(join(ROOT, "pages"), (name) => name.endsWith(".html")).sort();

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

// Matches both `<script src="...">` and `<script src='...'>` — Cloudflare's
// own edge-injected tags (e.g. the Web Analytics beacon) use single quotes,
// and while those never appear in this repo's own committed HTML, a
// future page author using single quotes for a real entry-point script
// tag shouldn't silently fall out of this check's coverage.
const scriptSrcRegex = /<script\b[^>]*\bsrc\s*=\s*["']([^"']+)["'][^>]*>/g;
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
        if (/\brequireAuth\s*\(/.test(stripComments(jsText))) return true;

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

if (failures > 0) {
    console.error(`\n${failures} crawl/noindex policy issue(s) found.`);
    process.exit(1);
}

console.log(
    `Crawl/noindex policy OK — ${GATED_PAGES.length} gated application pages (noindex + Disallow) and ` +
    `${AUTH_UTILITY_PAGES.length} auth-flow utility pages (noindex, NOT Disallow'd) verified, ` +
    `${NOINDEX_WITHOUT_DISALLOW.length} noindex-only exception confirmed, ${MUST_STAY_PUBLIC.length + ACTION_GATED_PUBLIC_PAGES.length} ` +
    `public pages confirmed crawlable, ${pagesScanned} pages/ HTML files scanned for unclassified requireAuth() usage.`
);
