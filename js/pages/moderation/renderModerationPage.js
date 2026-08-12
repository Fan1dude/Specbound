import {
    getOpenReports,
    getResolvedReports,
    resolveReport,
    getReportTargetContext,
    getReportActorProfiles,
    RESOLUTION_OUTCOMES
} from "../../repositories/moderationRepository.js";
import { supabase } from "../../core/supabase.js";
import { renderReportCardList, wireReportCardActions } from "../../components/ReportCard.js";
import { confirmDialog } from "../../utils/modal.js";
import { showToast } from "../../core/toast.js";
import { listSkeleton } from "../../utils/skeletons.js";
import { icon } from "../../utils/icons.js";

function cssEscape(value) {
    return typeof CSS !== "undefined" && CSS.escape ? CSS.escape(value) : String(value).replace(/["\\]/g, "\\$&");
}

// Milestone 24 — self-contained, fetch-owns-state controller, same shape
// as renderNotifications.js: one module-level async function that grabs
// its own DOM references, loads its own data, and re-renders on every
// state change rather than a framework-driven diff. Called only after
// loadModerationQueue.js has already confirmed the viewer is a moderator
// — this function assumes that's already true and never re-checks it;
// the RLS on content_reports/moderation_actions and resolve_report()'s
// own internal check remain the real, independent security boundary
// regardless.
export async function renderModerationPage() {
    const errorEl = document.getElementById("moderationError");
    const bodyEl = document.getElementById("moderationBody");
    const openHeading = document.getElementById("moderationOpenHeading");
    const openCountEl = document.getElementById("moderationOpenCount");
    const openList = document.getElementById("moderationOpenList");
    const historyList = document.getElementById("moderationHistoryList");
    const openPanel = document.getElementById("moderationOpenPanel");
    const historyPanel = document.getElementById("moderationHistoryPanel");
    const tabs = Array.from(document.querySelectorAll("#moderationTabs .tab"));
    const retryBtn = document.getElementById("moderationRetryBtn");

    if (!openList || !historyList) return;

    let openReports = [];
    let resolvedReports = [];
    let targetContext = new Map();
    let actorProfiles = new Map();

    setupTabs();
    retryBtn?.addEventListener("click", loadAll);

    await loadAll();

    async function loadAll() {
        if (errorEl) errorEl.hidden = true;
        if (bodyEl) bodyEl.hidden = false;

        openList.innerHTML = listSkeleton(3);
        historyList.innerHTML = listSkeleton(3);

        try {
            const [open, resolved] = await Promise.all([getOpenReports(), getResolvedReports()]);

            openReports = open;
            resolvedReports = resolved;

            const allReports = [...open, ...resolved];

            [targetContext, actorProfiles] = await Promise.all([
                getReportTargetContext(allReports),
                getReportActorProfiles(allReports)
            ]);

            renderOpen();
            renderHistory();
        } catch (error) {
            console.error("Moderation queue load error:", error);

            if (bodyEl) bodyEl.hidden = true;
            if (errorEl) errorEl.hidden = false;
        }
    }

    function renderOpen() {
        if (!openReports.length) {
            openList.innerHTML = `
                <div class="empty-state">
                    <div class="empty-state-icon">${icon("check", 32)}</div>
                    <h3>No open reports</h3>
                    <p>New reports will appear here as builders submit them.</p>
                </div>
            `;
        } else {
            openList.innerHTML = renderReportCardList(openReports, { mode: "open", targetContext, actorProfiles });
            wireReportCardActions(openList, handleResolve);
        }

        if (openCountEl) {
            openCountEl.textContent = openReports.length ? String(openReports.length) : "";
            openCountEl.hidden = openReports.length === 0;
        }
    }

    function renderHistory() {
        if (!resolvedReports.length) {
            historyList.innerHTML = `
                <div class="empty-state">
                    <div class="empty-state-icon">${icon("document", 32)}</div>
                    <h3>No resolved reports yet</h3>
                    <p>Reports you or another moderator resolve will appear here.</p>
                </div>
            `;
        } else {
            historyList.innerHTML = renderReportCardList(resolvedReports, { mode: "resolved", targetContext, actorProfiles });
        }
    }

    async function handleResolve(reportId, outcomeKey, triggerButton) {
        const report = openReports.find(r => r.id === reportId);
        if (!report) return;

        const outcome = RESOLUTION_OUTCOMES[outcomeKey];
        const target = targetContext.get(`${report.target_type}:${report.target_id}`);
        const targetLabel = target?.available && target.label ? target.label : `this ${report.target_type}`;

        const confirmed = await confirmDialog({
            title: `Mark as "${outcome.label}"?`,
            body: `This report about ${targetLabel} will be marked "${outcome.label}". ${outcome.description}`,
            confirmLabel: outcome.label,
            cancelLabel: "Cancel",
            danger: outcomeKey === "violation_confirmed"
        });

        if (!confirmed) return;

        const card = openList.querySelector(`.report-card[data-report-id="${cssEscape(reportId)}"]`);
        const actionButtons = card ? Array.from(card.querySelectorAll('[data-action="resolve-report"]')) : [];

        // Captured BEFORE disabling anything below — disabling the
        // currently-focused button makes the browser evict focus to
        // <body> immediately (a disabled element can't hold focus), well
        // before removeFromOpenAndFocus() ever runs. Re-deriving "was
        // focus inside this card" from document.activeElement at removal
        // time would always see <body> by then and silently skip
        // restoring focus anywhere — exactly the "no focus loss" failure
        // this milestone's own requirement calls out.
        const wasFocusInsideCard = card?.contains(document.activeElement) ?? false;

        actionButtons.forEach(btn => { btn.disabled = true; });

        if (triggerButton) {
            triggerButton.dataset.originalHtml = triggerButton.innerHTML;
            triggerButton.innerHTML = "Saving...";
        }

        // Client-side freshness guard — resolve_report() (0028_moderation.sql)
        // matches by report id alone, regardless of its current status, so
        // it has no built-in defense against two moderators resolving the
        // same report moments apart (the second call would silently
        // re-resolve it, overwriting who/when it was resolved and firing a
        // second reporter notification). Rather than add a migration to
        // harden the RPC itself for this milestone, this re-checks the
        // report's live status immediately before calling it — closes the
        // realistic case (a queue left open in two tabs) without a schema
        // change; a genuinely simultaneous click is a tiny residual, non-
        // security race documented in this milestone's final report, not
        // fixed here.
        let stillOpen = true;

        try {
            const { data: freshRow, error: freshError } = await supabase
                .from("content_reports")
                .select("status")
                .eq("id", reportId)
                .single();

            if (freshError) throw freshError;
            stillOpen = freshRow?.status === "open";
        } catch (error) {
            console.error("Report freshness check error:", error);
            // Fall through — resolve_report()'s own check remains the
            // backstop if this pre-check itself couldn't be completed.
        }

        if (!stillOpen) {
            showToast("This report was already resolved by someone else.", "info");
            removeFromOpenAndFocus(reportId, wasFocusInsideCard);
            return;
        }

        try {
            const updated = await resolveReport(reportId, outcomeKey);

            showToast(`Report marked "${outcome.label}".`, "success");

            resolvedReports = [{ ...report, ...updated }, ...resolvedReports];
            renderHistory();
            removeFromOpenAndFocus(reportId, wasFocusInsideCard);
        } catch (error) {
            console.error("Resolve report error:", error);

            if (/not found/i.test(error.message || "")) {
                showToast("This report is no longer open.", "info");
                removeFromOpenAndFocus(reportId, wasFocusInsideCard);
                return;
            }

            showToast(error.message || "Could not resolve this report. Try again.", "error");

            actionButtons.forEach(btn => { btn.disabled = false; });
            if (triggerButton?.dataset.originalHtml) {
                triggerButton.innerHTML = triggerButton.dataset.originalHtml;
            }
        }
    }

    // Removes a report from the Open list and re-renders it — full
    // re-render, not a single-node removal, matching
    // renderNotifications.js's "re-render the whole list on state change"
    // convention. Focus is only ever moved if it was actually inside the
    // card being removed; the replacement target is whichever open
    // report now sits at the same list position (the "next" report
    // sliding into the resolved one's place), the previous one if it was
    // last, or the Open heading (tabindex="-1" in the markup for exactly
    // this) if the list is now empty — never silently dropped to <body>.
    function removeFromOpenAndFocus(reportId, wasFocusInsideCard) {
        const index = openReports.findIndex(r => r.id === reportId);

        openReports = openReports.filter(r => r.id !== reportId);
        renderOpen();

        if (!wasFocusInsideCard) return;

        const remainingCards = openList.querySelectorAll(".report-card");

        if (!remainingCards.length) {
            openHeading?.focus();
            return;
        }

        const targetCard = remainingCards[Math.min(index, remainingCards.length - 1)];
        const targetButton = targetCard?.querySelector('[data-action="resolve-report"]');

        (targetButton || openHeading)?.focus();
    }

    function setupTabs() {
        tabs.forEach((tab, index) => {
            tab.addEventListener("click", () => activateTab(tab));

            // Same standard WAI-ARIA Tabs left/right-arrow pattern as
            // js/pages/editor/editorTabs.js.
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
}
