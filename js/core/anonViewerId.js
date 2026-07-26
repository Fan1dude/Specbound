const STORAGE_KEY = "specbound:anon-viewer-id";

// A random id persisted per-browser, used only as an opaque cooldown key
// for record_build_view() (see supabase/migrations/0010_build_view_tracking.sql)
// — never treated as a real identity, never sent anywhere else. Signed-in
// callers are identified server-side via auth.uid() instead; this exists
// purely so a signed-out visitor's cooldown survives a page refresh.
export function getAnonViewerId() {
    try {
        const existing = localStorage.getItem(STORAGE_KEY);

        if (existing) return existing;

        const generated = crypto.randomUUID();
        localStorage.setItem(STORAGE_KEY, generated);

        return generated;
    } catch {
        // Storage unavailable (private browsing, disabled storage, etc.) —
        // fall back to a one-off id for this page load only. The cooldown
        // simply won't persist across visits for this visitor, which is
        // the same outcome as clearing storage.
        return crypto.randomUUID();
    }
}
