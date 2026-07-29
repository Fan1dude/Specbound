# Continuous Integration

Status: Authoritative. Added Milestone 17, 2026-07-29.

This document describes what runs automatically on every push/PR (`.github/workflows/ci.yml`), what the CI tooling under `tools/ci/` does, and — just as importantly — what still requires manual browser verification. It does not change local development: opening HTML files directly, or serving the repo with `.claude/nocache_server.py`, still works exactly as before. CI tooling is only needed to run the automated checks described below; it is not a build step for the site itself (see `docs/DEPLOYMENT.md`).

---

## 1. Why `tools/ci/package.json` exists, and why it isn't at the repo root

Specbound is deliberately a static site with no bundler and no root-level `package.json` — see `docs/DEPLOYMENT.md`. Two of the three CI checks (the browser test runner) need `playwright` to drive headless Chromium, which needs `npm install` somewhere.

Putting that `package.json` at the repo root would have a real consequence: Cloudflare Pages auto-detects a root-level `package.json` and runs `npm install` as part of every production build, regardless of the configured "Framework preset" or build command — introducing an unrelated dependency install (and, if Playwright's browser download ran too, a very large one) into every production deploy for no reason.

Instead, `tools/ci/package.json` lives one level down. Cloudflare's root-directory build detection (`Root directory: /` per `docs/DEPLOYMENT.md`) never sees it, so production deploys are unaffected. CI explicitly `cd`s into `tools/ci` to install it. `tools/` is also pruned from the published output entirely (`docs/DEPLOYMENT.md`'s build command), so none of this ships to production either way.

---

## 2. What runs automatically (`.github/workflows/ci.yml`)

Two jobs, both on every push to `main`/`master` and every pull request:

### `syntax-and-references` (no dependencies beyond Node itself)

- **`tools/ci/check-syntax.js`** — parses every `.js` file in the repo with `node --input-type=module --check`, treating each file as a standalone ES module. Catches typos, mismatched brackets, stray tokens — anything that would make the file fail to load in the browser. Doesn't need a root `package.json`'s `"type": "module"` field (deliberately — see §1); the module-ness is asserted per-invocation instead.
- **`tools/ci/check-references.js`** — regex-scans every HTML `src=`/`href=` attribute, every CSS `url()` (including `@import url()`), and every JS `import`/`export ... from`/dynamic `import()` specifier, and confirms each local reference resolves to a real file on disk. External URLs (any `scheme:` prefix, `//`, `#anchor`) and bare module specifiers (npm-style names, the Supabase CDN import in `js/core/supabase.js`) are skipped — they aren't local files to check. Existence checks are **case-sensitive**, even though this is normally run on case-insensitive filesystems (Windows/macOS), because the production host (Cloudflare Pages, Linux) is case-sensitive; a reference that only "works" locally by case coincidence would 404 in production.

- **`tools/ci/check-a11y-regressions.js`** (added Milestone 18) — three static-analysis regression checks encoding bug classes this app has already hit more than once by hand:
  1. **`[hidden]`-vs-class-display specificity trap** — any class that sets a non-`none` `display` and is ever combined with the `hidden` attribute in HTML must have a matching `.class[hidden] { display: none }` override (the `.btn[hidden]`/`.editor-recovery-banner[hidden]`/`.revision-banner[hidden]`/`.auth-form[hidden]` bug class). Caught a real, previously-unknown instance on `.editor-view-live-link` (the project editor page, which requires auth and so wasn't reachable by live browser testing) during Milestone 18.
  2. **Dark-readable text on light/saturated fills** — every use of tokens.css's `-strong` fill tokens (`--color-primary-strong`, `--color-danger-strong`, etc.) as a `background` must pair with `color: var(--color-text-inverse)` in the same rule, matching the verified-safe pattern established in Milestone 14.
  3. **No reintroduced glow effects** — flags any reference to a retired `--glow-*` token, and any `box-shadow` layer shaped like a glow (zero offset, non-zero blur, non-neutral color) as opposed to this app's directional elevation shadows or zero-blur focus rings.

All three are static analysis of the CSS/HTML source, not a live DOM/rendering check, and running the same way whether a page requires authentication or not — see Milestone 18's implementation report for the full audit this ran alongside.

All three checks in this job are fast, dependency-free, and run directly against a checked-out repo with no secrets and no network access beyond `actions/checkout`/`actions/setup-node`.

**Known limitation:** all three are regex/static-analysis based, not a real HTML/CSS/JS parser or browser engine. They won't catch a reference built at runtime from a variable (e.g. a template-literal-constructed asset path), a `hidden` attribute set only via JS with no static HTML attribute to scan, or any contrast/motion/focus issue that only a rendered page can show — those need manual/browser verification instead (§4).

### `browser-tests` (installs `playwright` + headless Chromium)

- **`tools/ci/run-tests.js`** — starts a plain Node HTTP server over the repo root (its own minimal static server, not `.claude/nocache_server.py`, so CI doesn't depend on dev-only tooling), then drives headless Chromium through every file in `tests/*.test.html` (24 files as of this milestone) and reads each one's `window.__testResults = { passCount, failCount, total, results }` — a convention every one of those files already followed before this milestone existed. Fails the job if any test fails, or if a test file doesn't report `window.__testResults` within 10 seconds (treated as a hard failure, not silently skipped).

**No Supabase secrets are used or required.** The two test files that reference `../core/supabase.js` (`tests/searchBuilds.test.html`, `tests/legacyImageUrlCompatibility.test.html`) do so through the existing "blob-URL module rewriting" pattern already used elsewhere in the suite: they fetch the real source file under test, rewrite its `"../core/supabase.js"` import string to point at an in-file mock (constructed as a `Blob` URL), and import the rewritten module. No real network call to Supabase happens in any of the 24 tests. This was confirmed by inspecting both files before wiring them into CI, not assumed.

---

## 3. Running the same checks locally

```bash
node tools/ci/check-syntax.js
node tools/ci/check-references.js
```

```bash
cd tools/ci
npm install
npx playwright install --with-deps chromium
cd ../..
node tools/ci/run-tests.js
```

All four require a locally installed Node (not otherwise needed for this project — see `docs/DEPLOYMENT.md`).

---

## 4. What CI does *not* cover — manual/browser verification still required

This is the explicit boundary between "automated, runs on every push" and "reviewed by hand in a real browser," so neither gets silently assumed to cover the other:

| Not covered by CI | Why | Where it's addressed instead |
|---|---|---|
| Live Supabase behavior — RLS policies, RPC functions (`record_build_view`, etc.), real auth flows | Would require a configured test Supabase project and real (or seeded) accounts; this environment has anon-key-only access and no service-role/CLI access (see `docs/DATABASE.md`'s Known Gap section) | Implementation-reviewed at the time each milestone shipped; noted case-by-case in each milestone's report where live verification wasn't possible (e.g. Milestone 11B's 3 private-build cases) |
| Actual visual rendering, layout, contrast as rendered by a real browser engine | The syntax/reference checks are static-analysis only; they don't render anything | `docs/BRAND.md`'s WCAG AA contrast verification (Milestone 14) and the accessibility audit (Milestone 18) — both done via live browser testing, not CI |
| Cross-browser/cross-device behavior | CI only runs headless Chromium | Not currently covered by any automated or manual process beyond ad hoc spot checks during development |
| Runtime-constructed asset/URL references (template-literal paths) | Outside what a regex-based static check can see (§2's known limitation) | Not currently covered — flagged here as a real gap, not silently assumed safe |
| Keyboard navigation, focus visibility, screen-reader behavior | Requires an actual input device / assistive tech, not just a headless DOM | `docs/milestones/MILESTONE_8D_ARCHITECTURE.md` (Milestone 8D's manual audit) and Milestone 18's accessibility audit |

---

## 5. Related Documents

- `docs/DEPLOYMENT.md` — the "no build step" static-site model this tooling is deliberately kept separate from
- `docs/ENGINEERING_STANDARDS.md` — the Pull Request Checklist this CI now partially automates (syntax/reference correctness; the rest — "Responsive," "Accessible," "Uses design tokens" — remains a manual review item)
