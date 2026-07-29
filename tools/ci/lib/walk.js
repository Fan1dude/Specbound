import { readdirSync } from "node:fs";
import { join } from "node:path";

const IGNORE_DIRS = new Set(["node_modules", ".git", ".github", ".claude", "supabase"]);

// Recursively collects file paths under `dir` for which `filter(path)` returns true,
// skipping tooling/VCS directories anywhere in the tree (matched by name, not depth).
export function walk(dir, filter, results = []) {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
        if (IGNORE_DIRS.has(entry.name)) continue;
        const full = join(dir, entry.name);
        if (entry.isDirectory()) {
            walk(full, filter, results);
        } else if (filter(entry.name)) {
            results.push(full);
        }
    }
    return results;
}
