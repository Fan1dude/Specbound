// Cloudflare Pages Function — blocks public access to /docs/* (internal
// planning/architecture/legal-readiness source material, not required to
// run the public site). Scoped to this one path prefix only: it never runs
// for any other route, so it cannot affect _headers-applied CSP/HSTS on the
// rest of the site. See docs/DEPLOYMENT.md "Deployment surface" section.
export function onRequest() {
  return new Response("Not Found", {
    status: 404,
    headers: { "content-type": "text/plain; charset=utf-8" },
  });
}
