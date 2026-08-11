import { supabase } from "../core/supabase.js";

// Client wrapper for the supabase/functions/product-metadata Edge
// Function (Milestone 23). supabase.functions.invoke() automatically
// attaches the current session's JWT as the Authorization header when
// one exists — this is "the existing Supabase client" the milestone
// requires the browser to go through; there is no direct fetch() to any
// retailer URL anywhere in this file or its caller.
//
// Every failure mode (network error, function error response, no
// session) surfaces as the same thrown Error with a single friendly
// message — the caller (renderSetupInventorySection.js) already treats
// "the fetch failed" as one case, always falling back to manual entry,
// per the milestone's explicit "never require metadata success" rule.
const FALLBACK_MESSAGE = "We couldn't fill in the details from this link. You can enter them manually.";

export async function fetchProductMetadata(url) {
    const { data, error } = await supabase.functions.invoke("product-metadata", {
        body: { url }
    });

    if (error) {
        throw new Error(FALLBACK_MESSAGE);
    }

    if (!data || typeof data !== "object" || data.error) {
        throw new Error(FALLBACK_MESSAGE);
    }

    return {
        title: typeof data.title === "string" ? data.title : null,
        retailerName: typeof data.retailerName === "string" ? data.retailerName : null,
        priceCents: typeof data.priceCents === "number" ? data.priceCents : null,
        currency: typeof data.currency === "string" ? data.currency : null
    };
}
