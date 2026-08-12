import { supabase } from "../core/supabase.js";
import { getBuildsByIds } from "./buildRepository.js";
import { getProfilesByIds } from "./profileRepository.js";
import { getCommentsByIds } from "./commentRepository.js";

// Milestone 24 — Moderator Report Queue. Every read here relies entirely
// on the RLS already shipped in supabase/migrations/0028_moderation.sql
// ("Moderators can view all reports" / "Moderators can view the audit
// log", both gated on is_platform_moderator(auth.uid())) — a non-
// moderator calling these gets back only their own filed reports (a
// separate, narrower, already-existing policy), never an error and never
// another user's report. The page-level gate in
// js/pages/moderation/loadModerationQueue.js is a UX convenience that
// fails closed before ever calling these — same "client-side check is
// not the security boundary" posture already established by
// ManageRolesControl.js/communityRepository.js for role management.

// Bounded, not unbounded — matches the conservative fixed-limit pattern
// already used by getRecentNotifications()/getBuildComments() rather
// than open-ended pagination, since a moderation queue is expected to
// stay small in practice (closed beta) and a genuinely large backlog is
// itself a signal worth surfacing, not silently paging past.
const OPEN_REPORTS_LIMIT = 100;
const RESOLVED_REPORTS_LIMIT = 100;

// Stored-status <-> UI-outcome mapping. The database has carried exactly
// these two resolution statuses since 0028_moderation.sql shipped
// (Milestone 22) — resolve_report()'s own CHECK is `p_status in
// ('reviewed', 'dismissed')`. Milestone 24 only adds new, more precise
// UI labels for an existing contract; the stored values are deliberately
// left unchanged rather than renamed, so this mapping is the one place
// that translation lives. See docs/milestones/MILESTONE_24_MODERATOR_REPORT_QUEUE_SPECIFICATION.md.
export const RESOLUTION_OUTCOMES = {
    no_violation: {
        status: "dismissed",
        label: "No violation",
        description: "The report was reviewed and the content does not violate the Community Guidelines."
    },
    violation_confirmed: {
        status: "reviewed",
        label: "Violation confirmed",
        description: "The report was reviewed and found valid. This records the decision only — it does not remove content, suspend the user, or take any other action."
    }
};

// Reverse lookup — every stored status this milestone's UI can produce.
// A legacy/unknown stored status (there shouldn't be one, since these are
// the only two resolve_report() has ever written, but a future migration
// or a hand-edited row is a real possibility) falls back to a neutral,
// clearly-labeled "Unknown status" rather than guessing or throwing.
const OUTCOME_BY_STATUS = Object.fromEntries(
    Object.values(RESOLUTION_OUTCOMES).map(outcome => [outcome.status, outcome])
);

export function describeReportStatus(status) {
    if (status === "open") return { label: "Open", description: "Awaiting moderator review." };

    const outcome = OUTCOME_BY_STATUS[status];
    if (outcome) return { label: outcome.label, description: outcome.description };

    return { label: "Unknown status", description: `Stored status "${status}" does not match a known resolution.` };
}

export async function getOpenReports({ limit = OPEN_REPORTS_LIMIT } = {}) {
    const { data, error } = await supabase
        .from("content_reports")
        .select("*")
        .eq("status", "open")
        .order("created_at", { ascending: false })
        .limit(limit);

    if (error) throw error;

    return data || [];
}

// Newest-resolution-first (reviewed_at, not created_at) — a report filed
// long ago but only just actioned belongs at the top of the history view,
// since "history" here means "moderation activity," not "report age."
export async function getResolvedReports({ limit = RESOLVED_REPORTS_LIMIT } = {}) {
    const { data, error } = await supabase
        .from("content_reports")
        .select("*")
        .in("status", ["reviewed", "dismissed"])
        .order("reviewed_at", { ascending: false })
        .limit(limit);

    if (error) throw error;

    return data || [];
}

// Thin wrapper over the existing resolve_report() RPC — no new SQL, no
// new privilege model. Server-side already: re-checks
// is_platform_moderator(), rejects an unknown status, raises if the
// report id doesn't exist, and — atomically, inside the same function —
// writes the public.moderation_actions audit row and notifies the
// reporter (create_notification(..., 'report_resolved')). Both of those
// side effects are the existing RPC's own behavior, not something this
// milestone adds; see js/utils/notificationFormat.js for the one small
// fix needed so that notification renders sensibly instead of falling
// through to a generic, broken-link default.
export async function resolveReport(reportId, outcomeKey) {
    const outcome = RESOLUTION_OUTCOMES[outcomeKey];

    if (!outcome) {
        throw new Error(`Unknown resolution outcome: ${outcomeKey}`);
    }

    const { data, error } = await supabase.rpc("resolve_report", {
        p_report_id: reportId,
        p_status: outcome.status
    });

    if (error) throw error;

    return data;
}

function targetKey(targetType, targetId) {
    return `${targetType}:${targetId}`;
}

// Resolves enough human-readable context per report to make a moderation
// decision without a query per row. Three batched lookups total
// (builds/comments/profiles), regardless of how many reports are passed
// in — same "batch-fetch-then-map client-side" pattern already
// established by attachBuildProfiles()/enrichNotifications() for the
// identical no-FK-to-join-through constraint (content_reports.target_id
// is a plain uuid across three possible tables, not a foreign key — see
// 0028_moderation.sql's own header for why).
//
// A target missing from its batch result — a deleted/soft-deleted
// comment, a build gone private or removed, a profile that no longer
// exists — is never an error here. RLS on builds/comments already
// silently excludes anything the caller (a moderator, same as anyone
// else at the RLS layer) can't see; that absence IS the "unavailable"
// signal, not a separate check this function needs to perform. Returns a
// Map keyed by "target_type:target_id" so callers do a plain lookup per
// report, never re-deriving which batch a given report's target came
// from.
export async function getReportTargetContext(reports) {
    const context = new Map();

    const buildIds = new Set();
    const commentIds = new Set();
    const profileIds = new Set();

    for (const report of reports) {
        if (report.target_type === "build") buildIds.add(report.target_id);
        else if (report.target_type === "comment") commentIds.add(report.target_id);
        else if (report.target_type === "profile") profileIds.add(report.target_id);
    }

    const [builds, comments] = await Promise.all([
        buildIds.size ? getBuildsByIds([...buildIds]) : Promise.resolve([]),
        commentIds.size ? getCommentsByIds([...commentIds]) : Promise.resolve([])
    ]);

    const buildsById = new Map(builds.map(build => [build.id, build]));

    // A reported comment's own context needs its parent build's title —
    // a second, small batch for exactly the build ids comments.length
    // introduces that the first batch (built only from target_type ===
    // "build" reports) didn't already cover. Still bounded: at most one
    // extra build per distinct commented-on build, never per comment.
    const commentBuildIds = new Set(comments.map(comment => comment.build_id).filter(id => !buildsById.has(id)));
    const extraBuilds = commentBuildIds.size ? await getBuildsByIds([...commentBuildIds]) : [];
    for (const build of extraBuilds) buildsById.set(build.id, build);

    const commentsById = new Map(comments.map(comment => [comment.id, comment]));

    for (const build of builds) {
        context.set(targetKey("build", build.id), {
            available: true,
            label: build.title || "Untitled project",
            href: build.slug ? `../build/build.html?slug=${encodeURIComponent(build.slug)}` : null
        });
    }

    for (const buildId of buildIds) {
        const key = targetKey("build", buildId);
        if (!context.has(key)) {
            context.set(key, { available: false, label: null, href: null });
        }
    }

    for (const comment of comments) {
        const parentBuild = buildsById.get(comment.build_id);
        context.set(targetKey("comment", comment.id), {
            available: true,
            label: parentBuild ? `Comment on ${parentBuild.title || "Untitled project"}` : "Comment",
            href: parentBuild?.slug ? `../build/build.html?slug=${encodeURIComponent(parentBuild.slug)}#commentsList` : null,
            secondaryText: comment.body
        });
    }

    for (const commentId of commentIds) {
        const key = targetKey("comment", commentId);
        if (!context.has(key)) {
            context.set(key, { available: false, label: null, href: null });
        }
    }

    if (profileIds.size) {
        const profiles = await getProfilesByIds([...profileIds]);
        const profilesById = new Map(profiles.map(profile => [profile.id, profile]));

        for (const profileId of profileIds) {
            const profile = profilesById.get(profileId);
            context.set(targetKey("profile", profileId), profile
                ? {
                    available: true,
                    label: profile.display_name || profile.username || "Builder profile",
                    href: `../profile.html?user=${encodeURIComponent(profile.id)}`
                }
                : { available: false, label: null, href: null });
        }
    }

    return context;
}

// Batch-resolves the reporter and (for resolved reports) the resolving
// moderator to a displayable identity — same getProfilesByIds() batching
// as every other build/profile pairing in this app, one query regardless
// of how many reports are passed in.
export async function getReportActorProfiles(reports) {
    const ids = new Set();

    for (const report of reports) {
        if (report.reporter_id) ids.add(report.reporter_id);
        if (report.reviewed_by) ids.add(report.reviewed_by);
    }

    if (!ids.size) return new Map();

    const profiles = await getProfilesByIds([...ids]);
    return new Map(profiles.map(profile => [profile.id, profile]));
}
