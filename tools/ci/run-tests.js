// Runs every tests/*.test.html file in a headless browser and aggregates the
// window.__testResults = { passCount, failCount, total, results } object each
// one sets when finished (a convention already shared by all 24 test files —
// see the harness code at the bottom of any tests/*.test.html for the exact
// shape). Requires `npm install` in this directory first (playwright).
//
// Serves the repo over plain HTTP itself (no dependency on the dev-only
// .claude/nocache_server.py) so this can run unattended in CI.
import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { readdirSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { dirname, extname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const ROOT = join(SCRIPT_DIR, "..", "..");
const PORT = 4173;

// Regenerated fresh on every run so headingSemantics.test.html's discovered
// page list can never drift from what's actually tracked in git -- see
// generate-page-manifest.js for the discovery rules.
execFileSync(process.execPath, [join(SCRIPT_DIR, "generate-page-manifest.js")], { stdio: "inherit" });

const MIME_TYPES = {
    ".html": "text/html; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".mjs": "text/javascript; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".svg": "image/svg+xml",
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".webmanifest": "application/manifest+json",
    ".json": "application/json",
    ".xml": "application/xml",
    ".txt": "text/plain; charset=utf-8",
    ".ico": "image/x-icon"
};

function startServer() {
    const server = createServer(async (req, res) => {
        try {
            const urlPath = decodeURIComponent(req.url.split("?")[0]);
            const filePath = join(ROOT, urlPath);
            if (!filePath.startsWith(ROOT)) {
                res.writeHead(403);
                res.end();
                return;
            }
            const data = await readFile(filePath);
            res.writeHead(200, { "Content-Type": MIME_TYPES[extname(filePath)] ?? "application/octet-stream" });
            res.end(data);
        } catch {
            res.writeHead(404);
            res.end("Not found");
        }
    });
    return new Promise((resolve) => server.listen(PORT, () => resolve(server)));
}

const server = await startServer();
const testDir = join(ROOT, "tests");
const testFiles = readdirSync(testDir).filter((f) => f.endsWith(".test.html")).sort();

const browser = await chromium.launch();
const page = await browser.newPage();

let totalPass = 0;
let totalFail = 0;
let hardFailures = 0;
const lines = [];

for (const file of testFiles) {
    const consoleErrors = [];
    const onConsole = (msg) => {
        if (msg.type() === "error") consoleErrors.push(msg.text());
    };
    const onPageError = (err) => consoleErrors.push(String(err));
    page.on("console", onConsole);
    page.on("pageerror", onPageError);

    try {
        await page.goto(`http://localhost:${PORT}/tests/${file}`, { waitUntil: "load" });
        await page.waitForFunction(() => window.__testResults !== undefined, null, { timeout: 10000 });
        const results = await page.evaluate(() => window.__testResults);
        totalPass += results.passCount;
        totalFail += results.failCount;
        const status = results.failCount === 0 ? "PASS" : "FAIL";
        lines.push(`${status}  ${file}  (${results.passCount}/${results.total})`);
    } catch {
        hardFailures++;
        const errSuffix = consoleErrors.length ? ` — console: ${consoleErrors.join(" | ")}` : "";
        lines.push(`ERROR ${file}  did not report window.__testResults within 10s${errSuffix}`);
    } finally {
        page.off("console", onConsole);
        page.off("pageerror", onPageError);
    }
}

await browser.close();
server.close();

console.log(lines.join("\n"));
console.log(
    `\n${totalPass} passed, ${totalFail} failed across ${testFiles.length} test files` +
        (hardFailures ? `, ${hardFailures} file(s) failed to load/report` : "") +
        "."
);

if (totalFail > 0 || hardFailures > 0) {
    process.exit(1);
}
