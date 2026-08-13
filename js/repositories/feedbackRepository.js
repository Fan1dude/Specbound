import { supabase } from "../core/supabase.js";
import { getProfilesByIds } from "./profileRepository.js";

// Milestone 26 — Feedback Review. Every read here relies entirely on the
// RLS already shipped in supabase/migrations/0029_feedback_submissions.sql
// ("Moderators can view all feedback" / "Users can view their own
// feedback", both unchanged by 0039) — a non-moderator calling
// getOpenFeedback()/getHistoryFeedback() gets back nothing (RLS denies
// it, not this code), and getMyFeedback() always returns only the
// caller's own rows regardless of what's asked for. The page-level gate
// in js/pages/feedback/loadFeedbackQueue.js is a UX convenience only,
// same posture already established by loadModerationQueue.js.

// Bounded, not unbounded — same conservative fixed-limit posture as
// moderationRepository.js's OPEN_REPORTS_LIMIT/RESOLVED_REPORTS_LIMIT,
// for the identical reason: a feedback queue is expected to stay small
// in practice at closed-beta scale, and a genuinely large backlog is
// itself a signal worth surfacing, not silently paging past.
const OPEN_FEEDBACK_LIMIT = 100;
const HISTORY_FEEDBACK_LIMIT = 100;

// Display-only labels, independent of FeedbackModal.js's own CATEGORIES
// list on purpose — that file (and the categories/message-limit it
// defines) is explicitly out of scope for this milestone, so this is a
// separate, read-side-only mapping rather than importing from or
// modifying it. Must be kept in sync with feedback_submissions'
// `category` CHECK constraint (0029) by hand if that ever changes.
export const CATEGORY_LABELS = {
    bug: "Bug",
    confusing: "Confusing",
    suggestion: "Suggestion",
    feature_request: "Feature Request"
};

export function describeFeedbackCategory(category) {
    return CATEGORY_LABELS[category] || "Feedback";
}

// Stored-status -> UI label/description, matching
// moderationRepository.js's describeReportStatus() convention — an
// unrecognized stored status (shouldn't happen; update_feedback_status()
// is the only writer and its own allow-list guarantees these three)
// gets a neutral, clearly-labeled fallback rather than guessing or
// throwing.
const STATUS_META = {
    open: { label: "Open", description: "Awaiting review." },
    reviewed: {
        label: "Reviewed",
        description: "A moderator or staff member has read and acknowledged it. This does not promise action."
    },
    closed: {
        label: "Closed",
        description: "The submission no longer needs review. This does not reveal whether it was implemented, declined, duplicated, or otherwise concluded."
    }
};

export function describeFeedbackStatus(status) {
    return STATUS_META[status] || { label: "Unknown status", description: `Stored status "${status}" does not match a known state.` };
}

export async function getOpenFeedback({ limit = OPEN_FEEDBACK_LIMIT } = {}) {
    const { data, error } = await supabase
        .from("feedback_submissions")
        .select("*")
        .eq("status", "open")
        .order("created_at", { ascending: false })
        .limit(limit);

    if (error) throw error;

    return data || [];
}

// History bundles Reviewed and Closed together (mirroring Reports'
// bundled "Resolved" tab) — the reviewer page's own status filter
// narrows within this set client-side, no separate query per filter.
// Sorted by status_updated_at (most-recently-actioned first), which is
// what makes this genuinely "history" rather than "old submissions" —
// see 0039's own header for why created_at would give the wrong order.
// `nulls last` + two further deterministic tiebreakers (created_at, id)
// guard against the (expected-empty-in-practice) case of a hand-edited
// row that reached reviewed/closed without ever going through
// update_feedback_status() and so never got a status_updated_at value.
export async function getHistoryFeedback({ limit = HISTORY_FEEDBACK_LIMIT } = {}) {
    const { data, error } = await supabase
        .from("feedback_submissions")
        .select("*")
        .in("status", ["reviewed", "closed"])
        .order("status_updated_at", { ascending: false, nullsFirst: false })
        .order("created_at", { ascending: false })
        .order("id", { ascending: false })
        .limit(limit);

    if (error) throw error;

    return data || [];
}

// Thin wrapper over update_feedback_status() — no new SQL, no new
// privilege model. Server-side already: re-checks is_platform_moderator(),
// validates the transition against its own allow-list, atomically claims
// the row by expected status, sets status_updated_at, and (inside the
// same function) creates exactly one actorless notification for the
// submitter when user_id is not null. See
// supabase/migrations/0039_feedback_status_workflow.sql.
export async function updateFeedbackStatus(feedbackId, expectedStatus, newStatus) {
    const { data, error } = await supabase.rpc("update_feedback_status", {
        p_feedback_id: feedbackId,
        p_expected_status: expectedStatus,
        p_new_status: newStatus
    });

    if (error) throw error;

    return data;
}

// Batch-resolves each row's submitter to a displayable identity — same
// getProfilesByIds() batching as getReportActorProfiles()
// (moderationRepository.js), one query regardless of how many feedback
// rows are passed in. A null user_id (deleted account, see 0029's own
// `on delete set null`) is never sent to getProfilesByIds() at all —
// the caller distinguishes "no profile because deleted" from "profile
// id present but lookup returned nothing" by checking user_id first,
// same as ReportCard.js's target-availability pattern.
export async function getFeedbackSubmitterProfiles(feedbackRows) {
    const ids = [...new Set(feedbackRows.map(row => row.user_id).filter(Boolean))];

    if (!ids.length) return new Map();

    const profiles = await getProfilesByIds(ids);
    return new Map(profiles.map(profile => [profile.id, profile]));
}

// Bounded, not unbounded — same conservative closed-beta posture as
// OPEN_FEEDBACK_LIMIT/HISTORY_FEEDBACK_LIMIT above. A single account's
// own submission history is lower-risk than an unbounded admin queue,
// but still shouldn't grow without limit — nothing in this app rate-
// limits repeat calls to submit_feedback(). No pagination UI this
// milestone; a user who genuinely hits this limit sees a restrained
// note (renderMyFeedback.js) rather than a silently-truncated list
// presented as complete.
export const MY_FEEDBACK_LIMIT = 100;

// Self-only — RLS ("Users can view their own feedback", 0029, unchanged)
// is the actual boundary; no client-supplied user id is ever passed
// here or needed, matching every other RLS-scoped read in this app
// (e.g. getOpenReports() doesn't re-filter by moderator status
// client-side either). Adding a limit() here narrows the RESULT SET
// size only — it does not touch, weaken, or duplicate the RLS scoping
// itself, which is enforced entirely server-side regardless of what
// this query asks for.
export async function getMyFeedback({ limit = MY_FEEDBACK_LIMIT } = {}) {
    const { data, error } = await supabase
        .from("feedback_submissions")
        .select("*")
        .order("created_at", { ascending: false })
        .limit(limit);

    if (error) throw error;

    return data || [];
}
