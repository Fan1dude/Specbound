import { supabase } from "../core/supabase.js";

// Owner-scoped reusable Setup-category templates (Milestone 23). RLS
// (0035_setup_inventory_and_builder_dates.sql) is the real gate — every
// one of these calls is a plain supabase-js call, same "no RPC needed"
// posture already established for onboarding_welcomed_at/
// guidelines_accepted_at. A blueprint's own setup_inventory always
// stores its own name snapshot (see the migration's own header) — this
// repository is only ever read from the editor, never from any public
// render path.
export async function getMySavedSetupCategories(userId) {
    const { data, error } = await supabase
        .from("saved_setup_categories")
        .select("id, name")
        .eq("user_id", userId)
        .order("name");

    if (error) throw error;

    return data || [];
}

// normalized_name's uniqueness is enforced by the database (a trigger
// derives it from `name`, and a unique index enforces it per owner) —
// this just surfaces that failure with a message a builder would
// actually understand instead of a raw Postgres constraint-violation
// string. Postgres error code 23505 = unique_violation.
export async function createSavedSetupCategory(userId, name) {
    const { data, error } = await supabase
        .from("saved_setup_categories")
        .insert({ user_id: userId, name })
        .select("id, name")
        .single();

    if (error) {
        if (error.code === "23505") {
            throw new Error("You already have a saved category with that name.");
        }
        throw error;
    }

    return data;
}

export async function renameSavedSetupCategory(id, name) {
    const { data, error } = await supabase
        .from("saved_setup_categories")
        .update({ name })
        .eq("id", id)
        .select("id, name")
        .single();

    if (error) {
        if (error.code === "23505") {
            throw new Error("You already have a saved category with that name.");
        }
        throw error;
    }

    return data;
}

// Never touches any draft/build/revision's own setup_inventory — every
// blueprint already carries its own name snapshot, independent of this
// row's existence (see the migration's header comment for the full
// reasoning). Deleting a template is purely "stop offering this as a
// future starting point," never a retroactive edit.
export async function deleteSavedSetupCategory(id) {
    const { error } = await supabase
        .from("saved_setup_categories")
        .delete()
        .eq("id", id);

    if (error) throw error;
}
