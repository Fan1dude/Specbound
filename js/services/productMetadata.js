import { supabase } from "../core/supabase.js";
import { isSafeHttpUrl } from "../utils/safeUrl.js";

// Client wrapper for the supabase/functions/product-metadata Edge
// Function (Milestone 23). supabase.functions.invoke() automatically
// attaches the current session's JWT as the Authorization header when
// one exists — this is "the existing Supabase client" the milestone
// requires the browser to go through; there is no direct fetch() to any
// retailer URL anywhere in this file or its caller.
//
// Every failure mode (network error, function error response, no
// session) surfaces as a thrown Error with a safe, user-facing message
// — never the underlying Supabase/networking/parsing detail. Most
// reasons collapse to the same generic fallback text (the caller always
// falls back to manual entry either way, per the milestone's "never
// require metadata success" rule), but a couple of edge-function reason
// codes get a more specific, still-safe message where that genuinely
// helps the user fix what they typed.
const GENERIC_FALLBACK_MESSAGE = "We couldn't fill in details from this link. You can enter them manually below.";

const REASON_MESSAGES = {
    invalid: "Enter a valid http:// or https:// URL.",
    unsupported: "We don't support pulling details from this link yet. You can enter them manually below.",
    timeout: GENERIC_FALLBACK_MESSAGE,
    blocked: GENERIC_FALLBACK_MESSAGE,
    rate_limited: "You've tried this a few times — wait a minute and try again, or enter the details manually.",
    auth_required: GENERIC_FALLBACK_MESSAGE
};

export async function fetchProductMetadata(url) {
    // A same-shape "invalid" outcome as the edge function's own scheme/
    // parse check (spec §5.2 steps 1-2), caught client-side so an
    // obviously malformed URL never spends a network round trip (or a
    // rate-limit slot) just to be told it's malformed. isSafeHttpUrl()
    // (js/utils/safeUrl.js) is this exact check, extracted so this file
    // and js/utils/affiliateLink.js share one implementation.
    if (!isSafeHttpUrl(url)) {
        throw new Error(REASON_MESSAGES.invalid);
    }

    const { data, error } = await supabase.functions.invoke("product-metadata", {
        body: { url }
    });

    if (error) {
        throw new Error(GENERIC_FALLBACK_MESSAGE);
    }

    if (!data || typeof data !== "object") {
        throw new Error(GENERIC_FALLBACK_MESSAGE);
    }

    if (data.error) {
        throw new Error(REASON_MESSAGES[data.error] || GENERIC_FALLBACK_MESSAGE);
    }

    return {
        title: typeof data.title === "string" ? data.title : null,
        retailerName: typeof data.retailerName === "string" ? data.retailerName : null,
        priceCents: typeof data.priceCents === "number" ? data.priceCents : null,
        currency: typeof data.currency === "string" ? data.currency : null
    };
}
