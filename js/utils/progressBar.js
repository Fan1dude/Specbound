// CSP compatibility helper — Milestone 10 brand refresh.
// .progress-fill's width is driven by a --progress custom property, which
// used to be set via an inline style="--progress: X%" attribute in
// template-string markup. A strict CSP with no 'unsafe-inline' in
// style-src silently blocks that (confirmed live during implementation:
// the attribute renders in the DOM, but the browser never applies it, so
// every progress bar in the app rendered at 0 width). Markup now carries
// the value as data-progress instead; call hydrateProgressBars() once
// after inserting any markup containing a [data-progress] element.
export function hydrateProgressBars(container) {
    container.querySelectorAll("[data-progress]").forEach(el => {
        el.style.setProperty("--progress", `${el.dataset.progress}%`);
    });
}
