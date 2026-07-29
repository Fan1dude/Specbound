// Validates that every JS file in the repo parses as a standalone ES module.
// Uses `node --input-type=module --check` on each file's contents directly
// (rather than relying on a repo-root package.json's "type" field) so this
// works without adding a root-level package.json — see tools/ci/package.json's
// description for why that matters for the Cloudflare Pages deploy.
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";
import { walk } from "./lib/walk.js";

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const ROOT = join(SCRIPT_DIR, "..", "..");

const files = walk(ROOT, (name) => name.endsWith(".js")).sort();
let failures = 0;

for (const file of files) {
    try {
        execFileSync(process.execPath, ["--input-type=module", "--check"], {
            input: readFileSync(file),
            stdio: ["pipe", "pipe", "pipe"]
        });
    } catch (err) {
        failures++;
        console.error(`\n✗ ${relative(ROOT, file)}`);
        console.error((err.stderr ?? Buffer.from(String(err.message))).toString().trim());
    }
}

console.log(`\n${files.length - failures}/${files.length} JS files passed syntax check.`);
if (failures > 0) {
    process.exit(1);
}
