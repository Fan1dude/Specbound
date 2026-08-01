import { supabase } from "../core/supabase.js";
import { escapeLikeSpecialChars } from "../utils/sqlEscaping.js";

const SEARCH_RESULT_LIMIT_DEFAULT = 10;

// Backed by public.components (0020_components_catalog.sql) AND
// public.component_aliases (0021_component_aliases.sql) — a search has to
// check both, since a component may be found by a shorthand/misspelling
// a moderator attached as an alias rather than by its canonical_name
// directly (see the architecture doc's Milestone 19, §4.2). Two queries
// run in parallel and are merged client-side rather than one query with
// an OR-across-tables, since PostgREST doesn't support that directly.
export async function searchComponents({
    query,
    technologyId = null,
    componentType = null,
    limit = SEARCH_RESULT_LIMIT_DEFAULT
}) {
    const normalizedQuery = String(query || "").trim();

    if (!normalizedQuery) {
        return [];
    }

    const likePattern = `%${escapeLikeSpecialChars(normalizedQuery)}%`;

    let byName = supabase
        .from("components")
        .select("id, canonical_name, manufacturer, technology_id, field_key")
        .ilike("canonical_name", likePattern)
        .order("canonical_name")
        .limit(limit);

    let byAlias = supabase
        .from("component_aliases")
        .select("component:component_id(id, canonical_name, manufacturer, technology_id, field_key)")
        .ilike("alias", likePattern)
        .limit(limit);

    // componentType is field_key in the catalog's terms — kept as the
    // existing parameter name here since that's what call sites already
    // pass (ComponentAutocomplete.js), not renamed to avoid unrelated
    // call-site churn in this same change.
    if (technologyId) {
        byName = byName.eq("technology_id", technologyId);
        byAlias = byAlias.eq("technology_id", technologyId);
    }

    if (componentType) {
        byName = byName.eq("field_key", componentType);
        byAlias = byAlias.eq("field_key", componentType);
    }

    const [nameResult, aliasResult] = await Promise.all([byName, byAlias]);

    if (nameResult.error) {
        console.error("Component search error:", nameResult.error);
        throw nameResult.error;
    }

    if (aliasResult.error) {
        console.error("Component alias search error:", aliasResult.error);
        throw aliasResult.error;
    }

    const merged = new Map();

    for (const component of nameResult.data || []) {
        merged.set(component.id, component);
    }

    for (const row of aliasResult.data || []) {
        if (row.component && !merged.has(row.component.id)) {
            merged.set(row.component.id, row.component);
        }
    }

    return Array.from(merged.values())
        .sort((a, b) => a.canonical_name.localeCompare(b.canonical_name))
        .slice(0, limit);
}

// Alphanumeric-only lowercase — mirrors the DB's generated normalized_name/
// normalized_alias columns exactly (0020/0021's regexp_replace(lower(x),
// '[^a-z0-9]', '', 'g')), so an .eq() against those columns here can only
// ever match what the database itself considers the same normalized value.
function normalizeForExactMatch(value) {
    return String(value || "").toLowerCase().replace(/[^a-z0-9]/g, "");
}

// True exact match only — canonical name OR alias, normalized-equal to
// the query. Distinct from searchComponents() above (an ilike substring
// search meant for fuzzy suggestions): this is what the import review
// flow uses to decide whether a componentId may attach automatically
// (see the architecture doc's Milestone 19, §4.4 — "only exact catalog
// matches may attach automatically"). Both underlying unique indexes
// (components_technology_field_normalized_idx,
// component_aliases_technology_field_normalized_idx) guarantee at most
// one row each, so maybeSingle() is safe here, not just convenient.
export async function findExactComponentMatch({ query, technologyId, fieldKey }) {
    const normalized = normalizeForExactMatch(query);

    if (!normalized || !technologyId || !fieldKey) {
        return null;
    }

    const [byName, byAlias] = await Promise.all([
        supabase
            .from("components")
            .select("id, canonical_name, manufacturer, technology_id, field_key")
            .eq("technology_id", technologyId)
            .eq("field_key", fieldKey)
            .eq("normalized_name", normalized)
            .maybeSingle(),
        supabase
            .from("component_aliases")
            .select("component:component_id(id, canonical_name, manufacturer, technology_id, field_key)")
            .eq("technology_id", technologyId)
            .eq("field_key", fieldKey)
            .eq("normalized_alias", normalized)
            .maybeSingle()
    ]);

    if (byName.error) {
        console.error("Exact component match error:", byName.error);
        throw byName.error;
    }

    if (byAlias.error) {
        console.error("Exact component alias match error:", byAlias.error);
        throw byAlias.error;
    }

    return byName.data || byAlias.data?.component || null;
}

// Ordinary authenticated users can never insert directly into
// public.components (see 0020_components_catalog.sql's "Catalog
// moderators can add catalog components" policy) — this submits a
// candidate to public.component_submissions instead, for moderator
// review. It does NOT create a usable componentId; the caller should
// keep saving the user's free-text value (componentId: null) on their
// own build regardless of whether this submission is ever approved —
// see js/utils/specifications.js and the architecture doc's Milestone 19,
// §4.1 for why those two things are deliberately decoupled.
export async function submitComponent({ technologyId, fieldKey, submittedName, manufacturer = null }) {
    const { data: userData, error: userError } = await supabase.auth.getUser();

    if (userError) {
        console.error("Component submission auth error:", userError);
        throw userError;
    }

    const userId = userData.user?.id;

    if (!userId) {
        throw new Error("You must be signed in to submit a new component.");
    }

    const { data, error } = await supabase
        .from("component_submissions")
        .insert({
            technology_id: technologyId,
            field_key: fieldKey,
            submitted_name: submittedName,
            manufacturer,
            submitted_by: userId
        })
        .select("id, technology_id, field_key, submitted_name, status")
        .single();

    if (error) {
        console.error("Component submission error:", error);
        throw error;
    }

    return data;
}
