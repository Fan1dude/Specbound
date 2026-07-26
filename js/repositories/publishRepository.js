import { supabase } from "../core/supabase.js";

// Calls the SECURITY DEFINER publish_draft() function — the only path
// allowed to write builds/build_revisions/revision_media (see
// supabase/migrations/0002_publish_draft_and_visibility.sql). Ownership
// and readiness are re-validated server-side; a rejected publish surfaces
// here as a thrown Postgres error with a human-readable message.
export async function publishDraft(draftId, { versionLabel = null, publishNotes = null } = {}) {
    const { data, error } = await supabase.rpc("publish_draft", {
        p_draft_id: draftId,
        p_version_label: versionLabel,
        p_publish_notes: publishNotes
    });

    if (error) throw error;

    return data;
}

// Calls the SECURITY DEFINER restore_revision_to_draft() function (see
// supabase/migrations/0005_revision_history_and_restore.sql). Ownership is
// re-validated server-side. expectedDraftUpdatedAt implements optimistic
// concurrency — pass the draft's updated_at exactly as last fetched; the
// server rejects the restore (rather than silently overwriting) if it no
// longer matches, e.g. because the owner has an editor tab open with
// unsaved/autosaved changes made after that fetch. Pass null only when no
// draft is linked to the build yet (nothing to race against).
export async function restoreRevisionToDraft(revisionId, expectedDraftUpdatedAt = null) {
    const { data, error } = await supabase.rpc("restore_revision_to_draft", {
        p_revision_id: revisionId,
        p_expected_draft_updated_at: expectedDraftUpdatedAt
    });

    if (error) throw error;

    return data;
}

// Calls the SECURITY DEFINER set_build_visibility() function (see
// supabase/migrations/0006_unpublish.sql) — the only direct way to change
// builds.visibility. Creates no revision. Republishing (publishDraft())
// separately restores visibility to "public" on its own — this is only
// ever called to unpublish (visibility "private") from the current UI.
export async function setBuildVisibility(buildId, visibility) {
    const { data, error } = await supabase.rpc("set_build_visibility", {
        p_build_id: buildId,
        p_visibility: visibility
    });

    if (error) throw error;

    return data;
}
