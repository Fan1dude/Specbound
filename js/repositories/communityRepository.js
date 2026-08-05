import { supabase } from "../core/supabase.js";

// Milestone 22 §7 — checked lazily at the first community-facing action
// (publish or comment), never at signup or in the Milestone 21 Welcome
// dialog. Plain owner-scoped update, no RPC needed — the existing "Users
// can update their own profile" policy (0000) already covers this
// column, the same posture Milestone 21 used for onboarding_welcomed_at.
export async function hasAcceptedGuidelines(userId) {
    const { data, error } = await supabase
        .from("profiles")
        .select("guidelines_accepted_at")
        .eq("id", userId)
        .single();

    if (error) throw error;
    return Boolean(data?.guidelines_accepted_at);
}

export async function acceptGuidelines(userId) {
    const { error } = await supabase
        .from("profiles")
        .update({ guidelines_accepted_at: new Date().toISOString() })
        .eq("id", userId);

    if (error) throw error;
}

// A role badge needs to render on any visitor's view of a public
// profile, not just the owner's own view (spec §5) — but profile_roles
// itself is no longer publicly readable as of migration 0032 (its raw
// `note`/`granted_by` columns were retrievable by any direct API caller
// under the original `using (true)` policy, not just the `role` column
// this function ever asked for). get_public_profile_roles() is the
// replacement public read path: a SECURITY DEFINER function that only
// ever returns `role`, so there's no way to request the columns that
// prompted this change in the first place. Signature/return shape here
// is unchanged, so every existing caller (this profile's own role
// badges, and a signed-in viewer's own roles used to decide whether to
// show ManageRolesControl) keeps working with no call-site changes.
export async function getProfileRoles(userId) {
    const { data, error } = await supabase
        .rpc("get_public_profile_roles", { p_user_id: userId });

    if (error) throw error;
    return (data || []).map(row => row.role);
}

// Both RPCs are moderator/staff-gated server-side (see
// supabase/migrations/0028_moderation.sql) — the checks in
// ManageRolesControl.js are a UX convenience (don't show a control
// someone can't use), never the actual security boundary.
export async function grantRole(userId, role, note) {
    const { data, error } = await supabase.rpc("grant_profile_role", {
        p_user_id: userId,
        p_role: role,
        p_note: note || null
    });

    if (error) throw error;
    return data;
}

export async function revokeRole(userId, role, note) {
    const { error } = await supabase.rpc("revoke_profile_role", {
        p_user_id: userId,
        p_role: role,
        p_note: note || null
    });

    if (error) throw error;
}

// targetType must be one of 'build' | 'comment' | 'profile' — matches
// content_reports.target_type's CHECK constraint (0028_moderation.sql);
// an invalid value is rejected server-side, not re-validated here.
export async function reportContent(targetType, targetId, reason) {
    const { data, error } = await supabase.rpc("report_content", {
        p_target_type: targetType,
        p_target_id: targetId,
        p_reason: reason
    });

    if (error) throw error;
    return data;
}

// category must be one of 'bug' | 'confusing' | 'suggestion' |
// 'feature_request' — matches feedback_submissions.category's CHECK
// constraint (0029_feedback_submissions.sql).
export async function submitFeedback(category, message, pageUrl) {
    const { data, error } = await supabase.rpc("submit_feedback", {
        p_category: category,
        p_message: message,
        p_page_url: pageUrl || null
    });

    if (error) throw error;
    return data;
}

// redeem_beta_invite() requires a real session (auth.uid()) — signup
// alone doesn't have one when email confirmation is required (the
// normal case, see signup/app.js's own comment), so this is called at
// first login instead, mirroring ensureProfile()'s exact pattern.
export async function redeemBetaInvite(code) {
    const { error } = await supabase.rpc("redeem_beta_invite", { p_code: code });
    if (error) throw error;
}
