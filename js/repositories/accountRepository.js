import { supabase } from "../core/supabase.js";

// Client wrapper for the supabase/functions/delete-account Edge
// Function — Launch Readiness self-service account deletion. Same
// pattern js/services/productMetadata.js already establishes for
// product-metadata: supabase.functions.invoke() automatically attaches
// the current session's JWT as the Authorization header, so there is no
// direct fetch() to the function anywhere in this file or its caller,
// and no user id is ever passed in the request body — the function
// derives the caller exclusively from that JWT.
//
// Every failure mode collapses to the same generic, safe message —
// never the underlying Supabase/network/edge-function detail — except
// "reauth_required", which the caller can act on directly (prompt for
// password again) rather than treat as a dead end.
const GENERIC_FAILURE_MESSAGE = "Your request could not be completed. Contact support@specboundapp.com.";

export const DELETE_ACCOUNT_REAUTH_REQUIRED = "reauth_required";

// The caller is expected to have already called
// supabase.auth.signInWithPassword() with the user's freshly-entered
// current password immediately before this — that mints a genuinely
// fresh session/access token, which supabase.functions.invoke() then
// attaches automatically. This function does not take or send a
// password itself; password verification happens entirely through that
// prior signInWithPassword() call and the Edge Function's own
// server-side freshness check against the resulting token.
export async function deleteAccount() {
    const { data, error } = await supabase.functions.invoke("delete-account", {
        body: {}
    });

    if (error) {
        throw new Error(GENERIC_FAILURE_MESSAGE);
    }

    if (!data || typeof data !== "object") {
        throw new Error(GENERIC_FAILURE_MESSAGE);
    }

    if (data.error === DELETE_ACCOUNT_REAUTH_REQUIRED) {
        const reauthError = new Error(GENERIC_FAILURE_MESSAGE);
        reauthError.code = DELETE_ACCOUNT_REAUTH_REQUIRED;
        throw reauthError;
    }

    if (data.error) {
        throw new Error(GENERIC_FAILURE_MESSAGE);
    }

    if (data.success !== true) {
        throw new Error(GENERIC_FAILURE_MESSAGE);
    }
}
