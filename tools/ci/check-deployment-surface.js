// Verifies the production deployment boundary described in
// docs/DEPLOYMENT.md ("Deployment surface"): internal source material
// (docs/, supabase/, tests/, tools/, .github/, .claude/) must never be
// reachable in production, while every file the public site actually needs
// (pages/**, css/**, js/**, assets/**, root HTML, robots.txt, sitemap.xml,
// manifest.webmanifest, _headers) must remain present.
//
// docs/ and supabase/ are blocked by this repo's own Cloudflare Pages
// Functions (functions/docs/[[path]].js, functions/supabase/[[path]].js) —
// a mechanism this script can audit directly. tests/, tools/, .github/, and
// .claude/ are additionally pruned by the Cloudflare Pages build command
// and blocked by a Cloudflare WAF rule, both Dashboard-configured and
// outside this repository's direct control; this script still asserts
// their absence from the computed surface below as defense in depth and to
// keep the boundary fully repo-verifiable rather than depending solely on
// external Dashboard state this environment cannot inspect.
//
// There is no separate "dist/" build step for this project (see
// docs/DEPLOYMENT.md §2 — static site, no bundler). So "the deploy
// artifact" is computed here rather than built: every git-tracked file
// minus the excluded prefixes below, copied into a disposable temp
// directory. That computed directory is then audited for required-file
// presence, excluded-path absence, broken references, and secrets — and,
// to prove those assertions are non-vacuous, the same audit is run once
// more against a deliberately-sabotaged copy (one excluded file injected,
// one required file deleted) to confirm it actually fails before the real
// check is trusted to pass.
import {
    copyFileSync,
    existsSync,
    mkdirSync,
    mkdtempSync,
    readdirSync,
    readFileSync,
    rmSync,
    writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, extname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const ROOT = join(SCRIPT_DIR, "..", "..");

const EXCLUDED_PREFIXES = ["docs/", "supabase/", "tests/", "tools/", ".github/", ".claude/"];

const REQUIRED_FILES = [
    "index.html",
    "404.html",
    "design-system.html",
    "robots.txt",
    "sitemap.xml",
    "manifest.webmanifest",
    "_headers",
    "css/styles.css",
    "css/base/tokens.css",
    "js/core/config.js",
    "js/core/auth.js",
    "js/core/layout.js",
    "pages/login.html",
    "pages/signup.html",
    "pages/explore.html",
    "pages/legal/privacy.html",
    "pages/legal/community-guidelines.html",
    "functions/docs/[[path]].js",
    "functions/supabase/[[path]].js",
];

const SECRET_PATTERNS = [
    { name: "Supabase secret/service-role key", re: /\bsb_secret_[A-Za-z0-9_-]{10,}\b/ },
    { name: "JWT-shaped token (possible legacy service-role key)", re: /\beyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b/ },
    { name: "AWS access key ID", re: /\bAKIA[0-9A-Z]{16}\b/ },
    { name: "PEM private key block", re: /-----BEGIN (RSA |EC |OPENSSH |)PRIVATE KEY-----/ },
    { name: "Postgres/Supabase connection string with embedded credentials", re: /postgres(?:ql)?:\/\/[^:\s/]+:[^@\s/]+@/ },
    { name: "GitHub personal access token", re: /\bgh[pousr]_[A-Za-z0-9]{20,}\b/ },
    { name: "Discord bot/client secret assignment", re: /discord[_-]?(client[_-]?secret|bot[_-]?token)\s*[:=]\s*["'][^"'\s]{10,}["']/i },
];

function trackedFiles() {
    const out = execFileSync("git", ["ls-tree", "-r", "--name-only", "HEAD"], {
        cwd: ROOT,
        encoding: "utf8",
    });
    return out.split("\n").filter(Boolean).map((p) => p.replace(/\\/g, "/"));
}

function isExcluded(path) {
    return EXCLUDED_PREFIXES.some((prefix) => path === prefix.slice(0, -1) || path.startsWith(prefix));
}

function buildComputedArtifact(files, destDir) {
    rmSync(destDir, { recursive: true, force: true });
    mkdirSync(destDir, { recursive: true });
    for (const f of files) {
        if (isExcluded(f)) continue;
        const src = join(ROOT, f);
        const dest = join(destDir, f);
        mkdirSync(dirname(dest), { recursive: true });
        copyFileSync(src, dest);
    }
}

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

function walkDir(dir, filter, results = []) {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
        const full = join(dir, entry.name);
        if (entry.isDirectory()) {
            walkDir(full, filter, results);
        } else if (filter(entry.name)) {
            results.push(full);
        }
    }
    return results;
}

function checkReferencesInArtifact(destDir, failures) {
    const htmlFiles = walkDir(destDir, (n) => n.endsWith(".html"));
    const cssFiles = walkDir(destDir, (n) => n.endsWith(".css"));
    const jsFiles = walkDir(destDir, (n) => n.endsWith(".js"));

    function checkRef(sourceFile, ref) {
        const clean = stripSuffix(ref.trim());
        if (isExternalOrSkippable(clean)) return;
        const baseDir = clean.startsWith("/") ? destDir : dirname(sourceFile);
        const relTarget = clean.startsWith("/") ? clean.slice(1) : clean;
        const target = join(baseDir, relTarget);
        if (!existsSync(target)) {
            failures.push(
                `broken reference in artifact: ${relative(destDir, sourceFile)} -> ${ref} (not present in deploy artifact)`
            );
        }
    }

    const attrRegex = /\b(?:src|href)\s*=\s*"([^"]*)"/g;
    for (const file of htmlFiles) {
        const text = readFileSync(file, "utf8");
        for (const m of text.matchAll(attrRegex)) checkRef(file, m[1]);
    }

    const urlRegex = /url\(\s*["']?([^"')]+)["']?\s*\)/g;
    for (const file of cssFiles) {
        const text = readFileSync(file, "utf8");
        for (const m of text.matchAll(urlRegex)) checkRef(file, m[1]);
    }

    const importRegex = /\bfrom\s+["']([^"']+)["']|\bimport\(\s*["']([^"']+)["']\s*\)/g;
    for (const file of jsFiles) {
        const text = readFileSync(file, "utf8");
        for (const m of text.matchAll(importRegex)) {
            const spec = m[1] ?? m[2];
            if (!spec.startsWith(".") && !spec.startsWith("/")) continue;
            checkRef(file, spec);
        }
    }
}

function scanForSecrets(destDir, failures) {
    const TEXT_EXT = new Set([".html", ".css", ".js", ".json", ".txt", ".xml", ".webmanifest"]);
    const files = walkDir(destDir, (n) => TEXT_EXT.has(extname(n)));
    for (const file of files) {
        const text = readFileSync(file, "utf8");
        for (const { name, re } of SECRET_PATTERNS) {
            if (re.test(text)) {
                failures.push(`possible secret (${name}) found in artifact: ${relative(destDir, file)}`);
            }
        }
    }
}

function auditArtifact(destDir, sourceFileList) {
    const failures = [];

    for (const req of REQUIRED_FILES) {
        if (!existsSync(join(destDir, req))) {
            failures.push(`required file missing from artifact: ${req}`);
        }
    }

    for (const f of sourceFileList) {
        if (isExcluded(f) && existsSync(join(destDir, f))) {
            failures.push(`excluded path present in artifact: ${f}`);
        }
    }

    checkReferencesInArtifact(destDir, failures);
    scanForSecrets(destDir, failures);

    return failures;
}

// --- Self-test: prove the audit is non-vacuous before trusting a clean pass ---

const files = trackedFiles();
const sabotageDir = mkdtempSync(join(tmpdir(), "specbound-artifact-sabotage-"));
buildComputedArtifact(files, sabotageDir);

const injectedExcludedFile = join(sabotageDir, "docs", "__selftest_injected_leak.md");
mkdirSync(dirname(injectedExcludedFile), { recursive: true });
writeFileSync(injectedExcludedFile, "self-test only: simulated leaked internal file\n");

const removedRequiredFile = join(sabotageDir, "index.html");
const removedRequiredBackup = readFileSync(removedRequiredFile, "utf8");
rmSync(removedRequiredFile);

const sabotagedFailures = auditArtifact(sabotageDir, [...files, "docs/__selftest_injected_leak.md"]);
rmSync(sabotageDir, { recursive: true, force: true });

const caughtInjectedFile = sabotagedFailures.some((f) => f.includes("docs/__selftest_injected_leak.md"));
const caughtMissingFile = sabotagedFailures.some((f) => f.includes("index.html"));

if (!caughtInjectedFile || !caughtMissingFile) {
    console.error(
        "Self-test FAILED: the deployment-surface audit did not detect a deliberately injected excluded file " +
            "and/or a deliberately removed required file. The check is vacuous and cannot be trusted — fix the " +
            "audit logic before relying on it.\n" +
            `  Injected excluded-file failure detected: ${caughtInjectedFile}\n` +
            `  Missing required-file failure detected: ${caughtMissingFile}\n`
    );
    process.exit(1);
}
void removedRequiredBackup; // restored implicitly — sabotageDir was discarded, never touched the real repo

// --- Real check, against a clean computed artifact ---

const artifactDir = mkdtempSync(join(tmpdir(), "specbound-deploy-artifact-"));
buildComputedArtifact(files, artifactDir);
const realFailures = auditArtifact(artifactDir, files);
rmSync(artifactDir, { recursive: true, force: true });

if (realFailures.length > 0) {
    console.error(`Deployment-surface audit found ${realFailures.length} problem(s):\n`);
    for (const f of realFailures) console.error(`  ${f}`);
    process.exit(1);
}

const excludedCount = files.filter(isExcluded).length;
const includedCount = files.length - excludedCount;
console.log(
    `Deployment surface OK — self-test proved the audit is non-vacuous; computed artifact from ${files.length} ` +
        `tracked files (${includedCount} included, ${excludedCount} excluded under ${EXCLUDED_PREFIXES.join(", ")}) ` +
        `contains all ${REQUIRED_FILES.length} required runtime files, no excluded paths, no broken references, and no secret patterns.`
);
