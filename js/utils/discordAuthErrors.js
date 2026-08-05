// Milestone 22 polish — classifies Discord identity-linking failures into
// short, user-facing messages instead of surfacing raw Supabase text.
//
// linkIdentity() only throws synchronously for what GoTrue can validate
// before ever redirecting to Discord (manual linking turned off, the
// Discord provider not configured in this Supabase project). Everything
// the OAuth round trip itself can produce — the user cancelling, an
// identity that's already linked (to this account or another one), a
// provider-side failure — comes back as error/error_code/error_description
// params on the redirect URL instead, since linkIdentity() has already
// returned (and redirected the browser away) long before any of that is
// known. describeDiscordLinkError() covers the first group;
// readDiscordOAuthRedirectError() + describeDiscordRedirectError() cover
// the second.

// Covers both "Manual linking is disabled" (GOTRUE_SECURITY_MANUAL_LINKING_
// ENABLED off) and the Discord provider itself not being configured/enabled
// in this Supabase project — the two synchronous, pre-redirect failure
// modes, kept distinct because they mean different things to whoever is
// configuring the environment.
export function describeDiscordLinkError(error) {
    const code = error?.code || "";
    const message = (error?.message || "").toLowerCase();

    if (code === "manual_linking_disabled" || message.includes("manual linking is disabled")) {
        return "Discord connections aren't turned on for this Specbound environment yet.";
    }

    if (
        code === "provider_disabled" ||
        message.includes("unsupported provider") ||
        message.includes("provider is not enabled") ||
        (message.includes("provider") && message.includes("not enabled"))
    ) {
        return "Discord sign-in isn't set up for this Specbound environment yet.";
    }

    return "Could not connect Discord. Please try again.";
}

// Reads (and clears) the OAuth error Supabase's redirect back from Discord
// may carry. Different failure modes surface it in different places —
// some as a query string, some as a #hash fragment — so both are checked.
// Only the error/error_code/error_description params are removed; a `code`
// or `state` param (the PKCE exchange the Supabase client itself still
// needs to process) is left untouched so this never races that.
// Returns null when there's nothing to report — the common case.
export function readDiscordOAuthRedirectError() {
    const searchParams = new URLSearchParams(window.location.search);
    const hashParams = new URLSearchParams(window.location.hash.replace(/^#/, ""));

    const code = hashParams.get("error_code") || hashParams.get("error")
        || searchParams.get("error_code") || searchParams.get("error");

    if (!code) return null;

    const rawDescription = hashParams.get("error_description") || searchParams.get("error_description") || "";
    const description = rawDescription ? decodeURIComponent(rawDescription.replace(/\+/g, " ")) : "";

    const url = new URL(window.location.href);
    ["error", "error_code", "error_description"].forEach(key => url.searchParams.delete(key));

    if (url.hash) {
        const cleanedHash = new URLSearchParams(url.hash.replace(/^#/, ""));
        ["error", "error_code", "error_description"].forEach(key => cleanedHash.delete(key));
        const remaining = cleanedHash.toString();
        url.hash = remaining ? `#${remaining}` : "";
    }

    window.history.replaceState({}, document.title, url.toString());

    return { code, description };
}

// `type: "already_exists"` is deliberately returned with no message — the
// caller (settings/app.js) already knows, from the reconcile it just ran,
// whether this account ended up connected or not, and that's the only
// reliable way to tell "already linked to you" (harmless, a stale double
// click) from "already linked to someone else" (a real conflict) apart.
export function describeDiscordRedirectError(redirectError) {
    if (!redirectError) return null;

    const { code, description } = redirectError;

    if (code === "access_denied") {
        return { type: "cancelled", message: "Discord connection cancelled." };
    }

    if (code === "identity_already_exists") {
        return { type: "already_exists", message: null };
    }

    return {
        type: "callback_failed",
        message: description || "Something went wrong connecting Discord. Please try again."
    };
}
