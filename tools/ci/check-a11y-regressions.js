// Milestone 18 regression checks — encodes three bug classes that have each
// been found and fixed more than once by hand in this app, so a future
// change can't silently reintroduce them. All three are static analysis of
// the CSS/HTML source; none of this replaces live browser/axe-core
// verification (see docs/CI.md and the Milestone 18 implementation report
// for what still needs manual checking).
import { readFileSync } from "node:fs";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";
import { walk } from "./lib/walk.js";

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const ROOT = join(SCRIPT_DIR, "..", "..");

const problems = [];

function stripComments(css) {
    return css.replace(/\/\*[\s\S]*?\*\//g, "");
}

// Minimal brace-depth-aware block extractor — good enough to pull out
// {selector, body} pairs, including from inside @media/@supports (whose
// contents get the same treatment as top-level rules), while leaving
// @keyframes/@font-face/@page alone (their bodies aren't selector/property
// pairs in the same shape and aren't relevant to either check below).
function extractRules(css, rules = []) {
    let i = 0;
    const n = css.length;

    while (i < n) {
        const start = i;

        while (i < n && css[i] !== "{" && css[i] !== "}") i++;
        if (i >= n) break;

        if (css[i] === "}") {
            i++;
            continue;
        }

        const header = css.slice(start, i).trim();
        i++; // skip '{'
        const bodyStart = i;
        let depth = 1;

        while (i < n && depth > 0) {
            if (css[i] === "{") depth++;
            else if (css[i] === "}") depth--;
            i++;
        }

        const body = css.slice(bodyStart, i - 1);

        if (header.startsWith("@media") || header.startsWith("@supports")) {
            extractRules(body, rules);
        } else if (!header.startsWith("@")) {
            rules.push({ selector: header, body });
        }
    }

    return rules;
}

const cssFiles = walk(ROOT, (name) => name.endsWith(".css")).sort();
const allRules = []; // { file, selector, body }

for (const file of cssFiles) {
    const css = stripComments(readFileSync(file, "utf8"));
    for (const rule of extractRules(css)) {
        allRules.push({ file, ...rule });
    }
}

// ---------------------------------------------------------------------
// Check 1: the [hidden]-vs-class-display specificity trap.
//
// `.foo[hidden] { display: none }` and the browser's built-in
// `[hidden] { display: none }` have equal specificity, so if `.foo` (or
// anything matching the same element) also has an author-stylesheet
// `display: <non-none>` rule, the class rule wins the cascade and the
// element stays visible despite the `hidden` attribute — the exact bug
// already fixed on .btn, .editor-recovery-banner, .revision-banner,
// .auth-form, and others. Any class that (a) sets a non-none display and
// (b) is ever combined with the `hidden` attribute in HTML must have a
// matching `.foo[hidden] { display: none }` override.
// ---------------------------------------------------------------------
const classesWithDisplay = new Set();
const classesWithHiddenOverride = new Set();

for (const { selector, body } of allRules) {
    const displayMatch = body.match(/display\s*:\s*([^;]+);?/i);
    if (!displayMatch) continue;
    const displayValue = displayMatch[1].trim().toLowerCase();

    for (const sel of selector.split(",")) {
        const trimmedSel = sel.trim();
        const hiddenClassMatch = trimmedSel.match(/^\.([\w-]+)\[hidden\]/);

        if (hiddenClassMatch) {
            if (displayValue === "none") {
                classesWithHiddenOverride.add(hiddenClassMatch[1]);
            }
            continue;
        }

        if (displayValue === "none") continue;
        for (const m of trimmedSel.matchAll(/\.([\w-]+)/g)) {
            classesWithDisplay.add(m[1]);
        }
    }
}

const htmlFiles = walk(ROOT, (name) => name.endsWith(".html")).sort();
const classesUsedWithHidden = new Set();
// Matches a class= attribute and a bare `hidden` attribute occurring
// anywhere in the same tag, in either attribute order.
const tagRegex = /<[a-zA-Z][^>]*>/g;

for (const file of htmlFiles) {
    const html = readFileSync(file, "utf8");
    for (const tagMatch of html.matchAll(tagRegex)) {
        const tag = tagMatch[0];
        // (?<!-) excludes aria-hidden="..." — a different attribute entirely.
        if (!/(?<!-)\bhidden\b/.test(tag)) continue;
        const classAttr = tag.match(/\bclass\s*=\s*"([^"]*)"/);
        if (!classAttr) continue;
        for (const cls of classAttr[1].split(/\s+/).filter(Boolean)) {
            classesUsedWithHidden.add(cls);
        }
    }
}

for (const cls of classesWithDisplay) {
    if (classesUsedWithHidden.has(cls) && !classesWithHiddenOverride.has(cls)) {
        problems.push({
            check: "hidden-specificity-trap",
            detail:
                `.${cls} sets a non-none display and is used with the hidden attribute, ` +
                `but has no ".${cls}[hidden] { display: none }" override — the hidden ` +
                `attribute will silently do nothing on this element.`
        });
    }
}

// ---------------------------------------------------------------------
// Check 2: dark-readable text on light/saturated fills.
//
// tokens.css's "-strong" fill tokens (--color-primary-strong,
// --color-success-strong, --color-warning-strong, --color-danger-strong,
// and the unprefixed --primary-strong/--danger-strong aliases) are light,
// high-luminance colors verified for use as FILLS paired with
// --color-text-inverse (dark ink) — never white or the app's normal light
// text, which fails contrast badly on them (see tokens.css's Primary
// comment). Every current use already pairs them correctly (.btn-primary,
// .btn-danger, .follow-btn, .notification-badge, .activity-feed-tab.is-active);
// this guards against a new component reintroducing the fill without the
// matching text color. Deliberately excludes the *-hover token variants
// (--primary-strong-hover etc.) since every current :hover rule using one
// relies on the base (non-hover) rule's already-verified color, same as
// any other CSS property that only changes on hover.
// ---------------------------------------------------------------------
const BASE_STRONG_FILL_TOKENS = [
    "--color-primary-strong",
    "--color-success-strong",
    "--color-warning-strong",
    "--color-danger-strong",
    "--primary-strong",
    "--danger-strong"
];

for (const { file, selector, body } of allRules) {
    const bgMatch = body.match(/background(?:-color)?\s*:\s*var\((--[\w-]+)\)/i);
    if (!bgMatch) continue;
    if (!BASE_STRONG_FILL_TOKENS.includes(bgMatch[1])) continue;

    if (!/color\s*:\s*var\(--color-text-inverse\)/i.test(body)) {
        problems.push({
            check: "light-fill-missing-inverse-text",
            detail:
                `${relative(ROOT, file)} — "${selector.trim()}" fills with ${bgMatch[1]} ` +
                `but doesn't pair it with "color: var(--color-text-inverse)" in the same rule.`
        });
    }
}

// ---------------------------------------------------------------------
// Check 3: no reintroduced glow effects.
//
// BRAND.md prohibits glow/gradient/neon effects; every former --glow-*
// token (all five were focus-visible rings) was retired in favor of
// --focus-ring, a solid zero-blur ring (tokens.css). This flags (a) any
// remaining reference to a --glow-* custom property, and (b) any
// box-shadow layer shaped like a glow: zero x/y offset with a non-zero
// blur radius and a non-neutral (non rgba(0,0,0,...)) color — the
// signature of a soft ambient glow, as opposed to this app's directional
// elevation shadows (--shadow-xs/sm/md/lg, all rgba(0,0,0,...) with a
// non-zero y-offset) or its zero-blur focus rings (--focus-ring and
// similar, blur always 0).
// ---------------------------------------------------------------------
function splitTopLevel(value, separator) {
    const parts = [];
    let depth = 0;
    let current = "";

    for (const char of value) {
        if (char === "(") depth++;
        else if (char === ")") depth--;

        if (char === separator && depth === 0) {
            parts.push(current);
            current = "";
        } else {
            current += char;
        }
    }

    parts.push(current);
    return parts;
}

for (const file of cssFiles) {
    const css = stripComments(readFileSync(file, "utf8"));

    for (const m of css.matchAll(/--glow[\w-]*/g)) {
        problems.push({
            check: "glow-reintroduced",
            detail: `${relative(ROOT, file)} references a retired --glow-* token (${m[0]}) — BRAND.md prohibits glow effects.`
        });
    }

    for (const m of css.matchAll(/box-shadow\s*:\s*([^;]+);/gi)) {
        for (const layer of splitTopLevel(m[1], ",")) {
            const trimmed = layer.trim();
            const parsed = trimmed.match(
                /^(-?0(?:px)?)\s+(-?0(?:px)?)\s+([\d.]+)(?:px)?\s+(?:[\d.]+(?:px)?\s+)?(.+)$/
            );
            if (!parsed) continue;

            const blur = parseFloat(parsed[3]);
            const color = parsed[4].trim();
            const isNeutral = /rgba?\(\s*0\s*,\s*0\s*,\s*0\b/i.test(color) || /^#000/i.test(color);

            if (blur > 0 && !isNeutral) {
                problems.push({
                    check: "glow-reintroduced",
                    detail:
                        `${relative(ROOT, file)} — box-shadow layer "${trimmed}" has a zero offset, ` +
                        `non-zero blur, and a non-neutral color — matches the shape of a glow effect, ` +
                        `not this app's directional elevation shadows or zero-blur focus rings.`
                });
            }
        }
    }
}

if (problems.length > 0) {
    console.error(`Found ${problems.length} accessibility regression(s):\n`);
    for (const p of problems) {
        console.error(`  [${p.check}] ${p.detail}\n`);
    }
    process.exit(1);
}

console.log(
    `No accessibility regressions found — checked ${cssFiles.length} CSS files ` +
        `(${allRules.length} rules) and ${htmlFiles.length} HTML files.`
);
