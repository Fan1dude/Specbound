import { escapeHtml } from "./escapeHtml.js";

// Shared markup for the three states almost every list/section in this app
// renders at some point — deliberately just render helpers, not a fetch or
// state-management abstraction. Each caller keeps its own try/catch and
// decides what (if anything) a retry should re-run; this module only knows
// how to draw the result.
export function renderLoadingState(container, message = "Loading...") {
    if (!container) return;

    container.setAttribute("role", "status");
    container.setAttribute("aria-live", "polite");
    container.innerHTML = `<p class="text-secondary list-state-message">${escapeHtml(message)}</p>`;
}

export function renderEmptyState(container, { title, description = "", actionHtml = "" } = {}) {
    if (!container) return;

    container.setAttribute("role", "status");
    container.setAttribute("aria-live", "polite");
    container.innerHTML = `
        <div class="empty-state">
            <h3>${escapeHtml(title)}</h3>
            ${description ? `<p>${escapeHtml(description)}</p>` : ""}
            ${actionHtml}
        </div>
    `;
}

// onRetry, if provided, re-runs exactly the operation the caller passes in —
// this module has no idea what that operation is or what else exists on the
// page. Callers are responsible for only retrying their own failed fetch,
// never re-fetching data that already loaded successfully.
//
// retryFocusTarget is an optional `() => HTMLElement|null` for callers
// whose successful retry lands its real content somewhere other than this
// same container (e.g. Settings repopulates static form fields elsewhere
// on the page, not this error container). Called only once a retry has
// actually succeeded. If omitted, the first focusable element found
// inside `container` itself is used — correct for every other current
// caller, whose successful retry re-renders directly into this container.
export function renderErrorState(container, { message = "Could not load this. Try again.", onRetry, retryFocusTarget } = {}) {
    if (!container) return;

    container.setAttribute("role", "status");
    container.setAttribute("aria-live", "polite");
    container.innerHTML = `
        <div class="empty-state list-state-error">
            <h3 tabindex="-1">${escapeHtml(message)}</h3>
            ${onRetry ? `<button type="button" class="btn btn-secondary list-state-retry">Try Again</button>` : ""}
        </div>
    `;

    if (onRetry) {
        const retryButton = container.querySelector(".list-state-retry");

        retryButton.addEventListener("click", async () => {
            retryButton.disabled = true;
            retryButton.textContent = "Retrying...";

            await onRetry();

            // A repeated failure means the caller's own catch block called
            // renderErrorState() on this same container again, replacing
            // this whole block (including the button this handler is
            // running from) with a fresh one — move focus to its heading
            // so the renewed failure isn't silently missed.
            const stillFailing = container.querySelector(".list-state-error h3");

            if (stillFailing) {
                stillFailing.focus();
                return;
            }

            // Otherwise the retry succeeded — focus the first relevant
            // interactive element in the now-real content.
            const target = retryFocusTarget ? retryFocusTarget() : findFirstFocusable(container);

            target?.focus();
        });
    }
}

function findFirstFocusable(root) {
    return root.querySelector(
        'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])'
    );
}

