import { requireAuth } from "../../core/auth.js";
import { getProfileRoles } from "../../repositories/communityRepository.js";
import { renderFeedbackPage } from "./renderFeedbackPage.js";

// Milestone 26 — the client-side gate, identical shape to
// loadModerationQueue.js (Milestone 24). This is UX only ("don't show a
// page someone can't use"), never the real security boundary: every
// read this page performs goes through RLS already scoped to
// is_platform_moderator(auth.uid()) (feedback_submissions, unchanged by
// 0039), and update_feedback_status() re-checks moderator status itself
// regardless of what this function decides.
//
// Fails closed on every path: pages/feedback.html ships with
// #feedbackGate visible and #feedbackContent/#feedbackDenied both hidden
// in the raw HTML (not just toggled by this script after the fact) — so
// a slow network, a thrown error, or JS not running at all never leaves
// feedback content visible by default.
export async function loadFeedbackQueue() {
    const gate = document.getElementById("feedbackGate");
    const content = document.getElementById("feedbackContent");
    const denied = document.getElementById("feedbackDenied");

    function showDenied() {
        if (gate) gate.hidden = true;
        if (content) content.hidden = true;
        if (denied) denied.hidden = false;
    }

    // requireAuth() redirects to login.html itself when signed out —
    // nothing here needs to render an access-denied state for that case.
    // Root-relative (hotfix, previously "../login.html" — pages/feedback.html
    // is one level up from site root, so "../login.html" pointed at a
    // nonexistent /login.html instead of the real /pages/login.html).
    const user = await requireAuth("/pages/login.html");
    if (!user) return;

    let roles = [];

    try {
        roles = await getProfileRoles(user.id);
    } catch (error) {
        console.error("Feedback reviewer role check error:", error);
        // A check that couldn't confirm authorization must never be
        // treated as authorized — same fail-closed posture as
        // loadModerationQueue.js, for the identical reason: what's being
        // gated is read access to other people's feedback submissions.
        showDenied();
        return;
    }

    const isModerator = roles.includes("moderator") || roles.includes("staff");

    if (!isModerator) {
        showDenied();
        return;
    }

    if (gate) gate.hidden = true;
    if (denied) denied.hidden = true;
    if (content) content.hidden = false;

    await renderFeedbackPage();
}
