import { supabase } from "./supabase.js";

// Memoized for the lifetime of the current page only — every page calls
// this at least twice (once from loadNavbar(), once from its own load
// flow), each call a real supabase.auth.getUser() round-trip (it
// revalidates the session server-side, unlike getSession()). Caching the
// in-flight/resolved promise means both callers share one request instead
// of firing two. Deliberately narrow: this is not a general-purpose
// application cache, it never persists across a navigation (a fresh page
// load re-imports this module with a fresh, empty cachedUserPromise), and
// it's cleared explicitly on sign-out so a stale "signed in" result can
// never survive past that action within the same page.
let cachedUserPromise = null;

export function getCurrentUser() {
    if (!cachedUserPromise) {
        cachedUserPromise = supabase.auth.getUser().then(({ data }) => data.user);
    }

    return cachedUserPromise;
}

export function clearCurrentUserCache() {
    cachedUserPromise = null;
}

export async function requireAuth(redirectPath = "login.html") {
    const user = await getCurrentUser();

    if (!user) {
        window.location.href = redirectPath;
        return null;
    }

    return user;
}
