import {
    getOpenFeedback,
    getHistoryFeedback,
    updateFeedbackStatus,
    getFeedbackSubmitterProfiles,
    CATEGORY_LABELS
} from "../../repositories/feedbackRepository.js";
import { supabase } from "../../core/supabase.js";
import { renderFeedbackCardList, wireFeedbackCardActions } from "../../components/FeedbackCard.js";
import { confirmDialog } from "../../utils/modal.js";
import { showToast } from "../../core/toast.js";
import { listSkeleton } from "../../utils/skeletons.js";
import { icon } from "../../utils/icons.js";

function cssEscape(value) {
    return typeof CSS !== "undefined" && CSS.escape ? CSS.escape(value) : String(value).replace(/["\\]/g, "\\$&");
}

// Milestone 26 — self-contained, fetch-owns-state controller, same shape
// as renderModerationPage.js (Milestone 24). Called only after
// loadFeedbackQueue.js has already confirmed the viewer is a
// moderator/staff member — this function assumes that's already true
// and never re-checks it; RLS on feedback_submissions and
// update_feedback_status()'s own internal check remain the real,
// independent security boundary regardless.
export async function renderFeedbackPage() {
    const errorEl = document.getElementById("feedbackError");
    const bodyEl = document.getElementById("feedbackBody");
    const pageHeading = document.getElementById("feedbackPageHeading");
    const openCountEl = document.getElementById("feedbackOpenCount");
    const openList = document.getElementById("feedbackOpenList");
    const historyList = document.getElementById("feedbackHistoryList");
    const openPanel = document.getElementById("feedbackOpenPanel");
    const historyPanel = document.getElementById("feedbackHistoryPanel");
    const tabs = Array.from(document.querySelectorAll("#feedbackTabs .tab"));
    const retryBtn = document.getElementById("feedbackRetryBtn");
    const categoryFilterEl = document.getElementById("feedbackCategoryFilter");
    const historyStatusFilterEl = document.getElementById("feedbackHistoryStatusFilter");

    if (!openList || !historyList) return;

    let openFeedback = [];
    let historyFeedback = [];
    let submitterProfiles = new Map();
    let categoryFilter = "all";
    let historyStatusFilter = "all";

    populateCategoryFilter();
    setupTabs();
    setupFilters();
    retryBtn?.addEventListener("click", loadAll);

    await loadAll();

    function populateCategoryFilter() {
        if (!categoryFilterEl) return;

        const options = [`<option value="all">All Categories</option>`]
            .concat(Object.entries(CATEGORY_LABELS).map(([value, label]) =>
                `<option value="${value}">${label}</option>`
            ));

        categoryFilterEl.innerHTML = options.join("");
    }

    async function loadAll() {
        if (errorEl) errorEl.hidden = true;
        if (bodyEl) bodyEl.hidden = false;

        openList.innerHTML = listSkeleton(3);
        historyList.innerHTML = listSkeleton(3);

        try {
            const [open, history] = await Promise.all([getOpenFeedback(), getHistoryFeedback()]);

            openFeedback = open;
            historyFeedback = history;
            submitterProfiles = await getFeedbackSubmitterProfiles([...open, ...history]);

            renderOpen();
            renderHistory();
        } catch (error) {
            console.error("Feedback queue load error:", error);

            if (bodyEl) bodyEl.hidden = true;
            if (errorEl) errorEl.hidden = false;
        }
    }

    function visibleOpen() {
        return categoryFilter === "all"
            ? openFeedback
            : openFeedback.filter(row => row.category === categoryFilter);
    }

    function visibleHistory() {
        let rows = categoryFilter === "all"
            ? historyFeedback
            : historyFeedback.filter(row => row.category === categoryFilter);

        if (historyStatusFilter !== "all") {
            rows = rows.filter(row => row.status === historyStatusFilter);
        }

        return rows;
    }

    function renderOpen() {
        const rows = visibleOpen();

        if (!rows.length) {
            openList.innerHTML = `
                <div class="empty-state">
                    <div class="empty-state-icon">${icon("check", 32)}</div>
                    <h3>No open feedback</h3>
                    <p>${openFeedback.length ? "No submissions match this category filter." : "New submissions will appear here as builders send them."}</p>
                </div>
            `;
        } else {
            openList.innerHTML = renderFeedbackCardList(rows, { submitterProfiles });
            wireFeedbackCardActions(openList, handleUpdateStatus);
        }

        if (openCountEl) {
            openCountEl.textContent = openFeedback.length ? String(openFeedback.length) : "";
            openCountEl.hidden = openFeedback.length === 0;
        }
    }

    function renderHistory() {
        const rows = visibleHistory();

        if (!rows.length) {
            historyList.innerHTML = `
                <div class="empty-state">
                    <div class="empty-state-icon">${icon("document", 32)}</div>
                    <h3>No feedback history yet</h3>
                    <p>${historyFeedback.length ? "No submissions match these filters." : "Feedback you or another reviewer act on will appear here."}</p>
                </div>
            `;
        } else {
            historyList.innerHTML = renderFeedbackCardList(rows, { submitterProfiles });
            wireFeedbackCardActions(historyList, handleUpdateStatus);
        }
    }

    async function handleUpdateStatus(feedbackId, expectedStatus, newStatus, triggerButton) {
        const sourceList = expectedStatus === "open" ? openFeedback : historyFeedback;
        const row = sourceList.find(item => item.id === feedbackId);
        if (!row) return;

        const confirmed = await confirmDialog(
            newStatus === "reviewed"
                ? {
                    title: "Mark as Reviewed?",
                    body: "This marks the submission as reviewed — a moderator or staff member has read and acknowledged it. This does not promise any action will be taken.",
                    confirmLabel: "Mark Reviewed",
                    cancelLabel: "Cancel"
                }
                : {
                    title: "Mark as Closed?",
                    body: "Closed is permanent — this submission cannot be reopened. This does not reveal whether the feedback was implemented, declined, duplicated, or otherwise concluded.",
                    confirmLabel: "Mark Closed",
                    cancelLabel: "Cancel",
                    danger: true
                }
        );

        if (!confirmed) return;

        const listEl = expectedStatus === "open" ? openList : historyList;
        const card = listEl.querySelector(`.feedback-card[data-feedback-id="${cssEscape(feedbackId)}"]`);
        const actionButtons = card ? Array.from(card.querySelectorAll('[data-action="update-feedback-status"]')) : [];

        // Captured BEFORE disabling anything — disabling the
        // currently-focused button evicts focus to <body> immediately,
        // well before any reconciliation runs. Same ordering rule
        // renderModerationPage.js's handleResolve() already documents.
        const wasFocusInsideCard = card?.contains(document.activeElement) ?? false;

        actionButtons.forEach(btn => { btn.disabled = true; });

        if (triggerButton) {
            triggerButton.dataset.originalHtml = triggerButton.innerHTML;
            triggerButton.innerHTML = "Saving...";
        }

        // Client-side freshness pre-check — a fast path only, NOT the
        // concurrency boundary. update_feedback_status()'s own atomic
        // guard (matching id + status = p_expected_status in one UPDATE)
        // is what actually prevents a stale/concurrent overwrite,
        // regardless of whether this pre-check ran, succeeded, or was
        // itself racing another reviewer's action.
        let stillExpected = true;

        try {
            const { data: freshRow, error: freshError } = await supabase
                .from("feedback_submissions")
                .select("status")
                .eq("id", feedbackId)
                .single();

            if (freshError) throw freshError;
            stillExpected = freshRow?.status === expectedStatus;
        } catch (error) {
            console.error("Feedback freshness check error:", error);
        }

        if (!stillExpected) {
            await handleConflict(wasFocusInsideCard);
            return;
        }

        try {
            const updated = await updateFeedbackStatus(feedbackId, expectedStatus, newStatus);

            showToast(`Feedback marked "${newStatus === "reviewed" ? "Reviewed" : "Closed"}".`, "success");
            applySuccessfulUpdate(row, updated, expectedStatus, wasFocusInsideCard);
        } catch (error) {
            console.error("Update feedback status error:", error);

            const message = error.message || "";

            // Checked first and narrowly — this is the atomic guard's
            // own distinct exception text, never confused with the
            // separate "not found" case below. A conflict never shows a
            // success toast for the attempted outcome; it reconciles
            // both views against the server instead.
            if (/already updated/i.test(message)) {
                await handleConflict(wasFocusInsideCard);
                return;
            }

            if (/not found/i.test(message)) {
                showToast("This feedback submission is no longer available.", "info");
                await loadAll();
                if (wasFocusInsideCard) pageHeading?.focus();
                return;
            }

            showToast(message || "Could not update this submission. Try again.", "error");

            actionButtons.forEach(btn => { btn.disabled = false; });
            if (triggerButton?.dataset.originalHtml) {
                triggerButton.innerHTML = triggerButton.dataset.originalHtml;
            }
        }
    }

    // Shared by both conflict-detection paths above — an honest,
    // identical response either way: no success toast for what THIS
    // reviewer attempted, a full reload from the server so every view
    // reflects whatever another reviewer actually recorded, and focus
    // moved to the page heading if it would otherwise be stranded.
    async function handleConflict(wasFocusInsideCard) {
        showToast("This submission was already updated by another reviewer. The queue has been refreshed.", "info");

        await loadAll();

        if (wasFocusInsideCard) pageHeading?.focus();
    }

    // expectedStatus === "open": the transition happened from the Open
    // tab — remove the row there and add it to History.
    // expectedStatus === "reviewed": the transition happened from
    // within the History tab itself (Reviewed -> Closed is the only
    // action ever available there) — update the row in place instead of
    // moving it between lists.
    function applySuccessfulUpdate(row, updated, expectedStatus, wasFocusInsideCard) {
        const merged = { ...row, ...updated };

        if (expectedStatus === "open") {
            const index = openFeedback.findIndex(item => item.id === row.id);
            openFeedback = openFeedback.filter(item => item.id !== row.id);
            historyFeedback = [merged, ...historyFeedback];

            renderOpen();
            renderHistory();

            if (!wasFocusInsideCard) return;

            const remainingCards = openList.querySelectorAll(".feedback-card");

            if (!remainingCards.length) {
                pageHeading?.focus();
                return;
            }

            const targetCard = remainingCards[Math.min(index, remainingCards.length - 1)];
            const targetButton = targetCard?.querySelector('[data-action="update-feedback-status"]');

            (targetButton || pageHeading)?.focus();
            return;
        }

        historyFeedback = historyFeedback.map(item => (item.id === row.id ? merged : item));
        renderHistory();

        if (!wasFocusInsideCard) return;

        // The card may still be visible (its status changed but the
        // active filter still matches, or the filter is "All") — in
        // that case it now has zero actions (Closed is terminal), so the
        // button that held focus no longer exists in the re-rendered
        // markup. Either way, the safe, always-correct target is the
        // page heading — this action can only ever be taken from
        // History, which has no per-card focusable fallback of its own
        // once a card loses its only action.
        pageHeading?.focus();
    }

    function setupTabs() {
        tabs.forEach((tab, index) => {
            tab.addEventListener("click", () => activateTab(tab));

            tab.addEventListener("keydown", event => {
                if (event.key !== "ArrowLeft" && event.key !== "ArrowRight") return;

                event.preventDefault();

                const delta = event.key === "ArrowRight" ? 1 : -1;
                const nextTab = tabs[(index + delta + tabs.length) % tabs.length];

                nextTab.focus();
                activateTab(nextTab);
            });
        });

        function activateTab(tab) {
            tabs.forEach(other => {
                other.classList.remove("is-active");
                other.setAttribute("aria-selected", "false");
            });

            tab.classList.add("is-active");
            tab.setAttribute("aria-selected", "true");

            const panelId = tab.getAttribute("aria-controls");

            [openPanel, historyPanel].forEach(panel => {
                if (panel) panel.hidden = panel.id !== panelId;
            });
        }
    }

    function setupFilters() {
        categoryFilterEl?.addEventListener("change", () => {
            categoryFilter = categoryFilterEl.value || "all";
            renderOpen();
            renderHistory();
        });

        historyStatusFilterEl?.addEventListener("change", () => {
            historyStatusFilter = historyStatusFilterEl.value || "all";
            renderHistory();
        });
    }
}
