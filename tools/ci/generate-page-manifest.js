// Discovers every git-tracked complete HTML page (root-level + pages/**)
// and writes tests/generated/pageManifest.json for headingSemantics.test.html
// to fetch. Uses `git ls-files` (execFileSync, argv array — no shell string
// interpolation) so untracked local/scratch files are never swept in as
// production pages, and a newly `git add`-ed page is picked up automatically
// with no second list to maintain.
//
// Inclusion rules (explicit, path-based):
//   - tracked *.html files directly at the repo root (index.html, 404.html,
//     design-system.html, ...) -- bucket "root"
//   - tracked pages/**/*.html files -- bucket "page", except
//   - tracked pages/categories/*.html files -- bucket "category" (these
//     share one JS renderer, js/pages/categories/renderCategoryPage.js,
//     and ship with zero static <h1> by design -- verified dynamically by
//     headingSemantics.test.html's Group B, not the static per-file check)
//
// Everything else tracked in the repo (tests/**, tools/**, docs/**, css/**,
// js/**, supabase/**, etc.) is a fixture, source file, or non-page
// document, not a complete application page, and is excluded by simply
// never being queried.
import { execFileSync } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join, posix } from "node:path";
import { fileURLToPath } from "node:url";

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const ROOT = join(SCRIPT_DIR, "..", "..");
const OUT_PATH = join(ROOT, "tests", "generated", "pageManifest.json");

function gitLsFiles(pattern) {
    const out = execFileSync("git", ["ls-files", "--", pattern], { cwd: ROOT, encoding: "utf8" });
    return out.split(/\r?\n/).filter(Boolean).map((p) => p.split("\\").join(posix.sep));
}

// Note: git's default (non ":(glob)") pathspec matching already lets `*`
// cross directory separators, so "pages/*.html" matches every nested file
// under pages/ (pages/login.html, pages/build/edit.html, pages/legal/
// terms.html, ...) without needing "**" -- confirmed empirically, since
// git's "**" only gets its shell-glob "any depth" meaning under explicit
// ":(glob)" pathspec magic and behaves differently (and wrongly, for this
// purpose) in the default mode used here.
const rootHtml = gitLsFiles("*.html").filter((p) => !p.includes("/"));
const pagesHtml = gitLsFiles("pages/*.html");

const pages = [
    ...rootHtml.map((path) => ({ path, bucket: "root" })),
    ...pagesHtml.map((path) => ({
        path,
        bucket: path.startsWith("pages/categories/") ? "category" : "page",
    })),
];

pages.sort((a, b) => a.path.localeCompare(b.path));

mkdirSync(dirname(OUT_PATH), { recursive: true });
writeFileSync(
    OUT_PATH,
    JSON.stringify({ generatedAt: new Date().toISOString(), pages }, null, 2) + "\n"
);

console.log(`page manifest: ${pages.length} tracked complete page(s) written to tests/generated/pageManifest.json`);
