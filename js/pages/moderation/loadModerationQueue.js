import { requireAuth } from "../../core/auth.js";
import { getProfileRoles } from "../../repositories/communityRepository.js";
import { renderModerationPage } from "./renderModerationPage.js";

// Milestone 24 — the client-side gate. This is UX only ("don't show a
// page someone can't use"), never the real security boundary: every read
// this page performs goes through RLS already scoped to
// is_platform_moderator(auth.uid()) (content_reports/moderation_actions,
// see supabase/migrations/0028_moderation.sql), and resolve_report()
// re-checks moderator status itself regardless of what this function
// decides. Same posture ManageRolesControl.js's own comment already
// documents for role management.
//
// Fails closed on every path: pages/moderation.html ships with
// #moderationGate visible and #moderationContent/#moderationDenied both
// hidden in the raw HTML (not just toggled by this script after the
// fact) — so a slow network, a thrown error, or JS not running at all
// never leaves protected markup visible by default. This function's job
// is only to flip exactly one of #moderationContent/#moderationDenied
// visible once the check has actually resolved, never both, never
// speculatively.
export async function loadModerationQueue() {
    const gate = document.getElementById("moderationGate");
    const content = document.getElementById("moderationContent");
    const denied = document.getElementById("moderationDenied");

    function showDenied() {
        if (gate) gate.hidden = true;
        if (content) content.hidden = true;
        if (denied) denied.hidden = false;
    }

    // requireAuth() redirects to login.html itself when signed out —
    // nothing here needs to render an access-denied state for that case,
    // since the browser is already navigating away.
    const user = await requireAuth("../login.html");
    if (!user) return;

    let roles = [];

    try {
        roles = await getProfileRoles(user.id);
    } catch (error) {
        console.error("Moderator role check error:", error);
        // A check that couldn't confirm authorization must never be
        // treated as authorized — the opposite failure mode from
        // GuidelinesGate.js's deliberate fail-open, because what's being
        // gated here is read access to other people's report data, not a
        // one-time acceptance prompt.
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

    await renderModerationPage();
}
