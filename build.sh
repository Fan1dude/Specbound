#!/bin/sh
# Deployment-artifact build for Cloudflare Pages.
#
# Specbound ships no framework and no bundler — this script's only job is to
# copy an explicit, version-controlled ALLOWLIST of public runtime files into
# dist/, which Cloudflare Pages then serves as the site. Anything not listed
# below is never copied, so it can never be served, regardless of what is
# later added to the repository root (docs/, supabase/, tests/, tools/,
# .github/, .claude/, README.md, package files, and any future top-level
# entry are excluded by omission, not by exclusion — see docs/DEPLOYMENT.md).
#
# Those excluded resources remain available via the public GitHub repository;
# they do not need to be served from specboundapp.com.
#
# Cloudflare Pages dashboard settings (changed only after this ships, per
# docs/DEPLOYMENT.md):
#   Build command:            sh build.sh
#   Build output directory:   dist
#   Root directory:           / (unchanged)
#
# The existing WAF rule blocking tests/, tools/, .github/, .claude/ stays in
# place as a second, independent layer of defense — see docs/DEPLOYMENT.md.

set -eu

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
cd "$SCRIPT_DIR"

DIST_DIR="dist"

# Files that must exist at the repository root and are copied as-is.
ALLOWLIST_FILES="
index.html
404.html
design-system.html
_headers
robots.txt
sitemap.xml
manifest.webmanifest
"

# Directories that must exist at the repository root and are copied
# recursively, path-preserving, so no application import or link needs
# rewriting.
ALLOWLIST_DIRS="
pages
css
js
assets
"

# Start clean so a stale previous build can never leak an entry that should
# no longer be present.
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

for entry in $ALLOWLIST_FILES; do
    [ -z "$entry" ] && continue
    if [ ! -f "$entry" ]; then
        echo "build.sh: required file '$entry' is missing from the repository root — aborting." >&2
        exit 1
    fi
    cp "$entry" "$DIST_DIR/$entry"
done

for entry in $ALLOWLIST_DIRS; do
    [ -z "$entry" ] && continue
    if [ ! -d "$entry" ]; then
        echo "build.sh: required directory '$entry/' is missing from the repository root — aborting." >&2
        exit 1
    fi
    cp -r "$entry" "$DIST_DIR/$entry"
done

echo "build.sh: dist/ built successfully from the approved allowlist."
