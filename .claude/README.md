# .claude/ — development tooling only

Everything in this directory supports local preview and testing during
implementation. None of it is part of the Specbound application, is served
in production, or should be included in a deploy/build pipeline.

## Contents

- `launch.json` — tells the Claude Code preview browser how to start a local
  static file server for this project (Specbound has no build step; the
  site is plain HTML/CSS/JS served as-is).
- `nocache_server.py` — a zero-dependency Python static file server
  (stdlib `http.server` only) that adds `Cache-Control: no-store` to every
  response. Used instead of a bare `python -m http.server` because the
  default server sends no cache headers at all, which lets browsers
  heuristically cache files and serve stale content during iterative
  development — that's a testing hazard, not a product concern.

## Why this exists

The project had no dev/preview setup prior to Milestone 1. This was added
so that CSS/JS changes could actually be verified in a browser (broken
`@import` paths, mobile navigation, etc. are impossible to catch by reading
source alone). It will keep being used for manual verification in future
milestones.

## If a real build/deploy pipeline is introduced later

This directory can stay — it doesn't conflict with a bundler, CI config, or
hosting setup — but `nocache_server.py` should never be pointed at in
production, and no production build step should read from `.claude/`.
