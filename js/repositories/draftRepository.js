import { supabase } from "../core/supabase.js";

export async function createDraft({ userId, title, category }) {
    const { data, error } = await supabase
        .from("project_drafts")
        .insert([{ user_id: userId, title, category }])
        .select()
        .single();

    if (error) throw error;

    return data;
}

export async function getDraft(draftId) {
    const { data, error } = await supabase
        .from("project_drafts")
        .select("*")
        .eq("id", draftId)
        .maybeSingle();

    if (error) throw error;

    return data;
}

// Used by the revision-detail page to find the owner's editable draft for
// a build before offering to restore into it (and to show its updated_at
// for the optimistic-concurrency check restore_revision_to_draft()
// enforces). Owner-only per project_drafts' existing RLS — returns null
// for anyone else, same as a build with no draft currently linked.
export async function getDraftByPublishedBuildId(buildId) {
    const { data, error } = await supabase
        .from("project_drafts")
        .select("*")
        .eq("published_build_id", buildId)
        .maybeSingle();

    if (error) throw error;

    return data;
}

export async function getMyDrafts(userId) {
    const { data, error } = await supabase
        .from("project_drafts")
        .select("*")
        .eq("user_id", userId)
        .order("updated_at", { ascending: false });

    if (error) throw error;

    return data || [];
}

export async function updateDraft(draftId, fields) {
    // updated_at is maintained by the set_project_drafts_updated_at trigger
    // (see supabase/migrations/0001_project_drafts_and_media.sql) — not set
    // here, so there's exactly one place that can get it wrong instead of
    // every call site that writes to this table.
    const { data, error } = await supabase
        .from("project_drafts")
        .update(fields)
        .eq("id", draftId)
        .select()
        .single();

    if (error) throw error;

    return data;
}
