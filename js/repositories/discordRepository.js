import { supabase } from "../core/supabase.js";

// OAuth itself is entirely Supabase Auth's native identity-linking
// (linkIdentity/unlinkIdentity/getUserIdentities) — this repository never
// touches a token, only the public identity mirror row. See
// supabase/migrations/0026_social_connections.sql and Milestone 22 spec
// §4 for the full design.

// Public profile pages (Builder Portfolio) only ever need this narrower,
// visibility-filtered read — RLS already enforces is_public = true for
// any caller who isn't the row's own owner, but the filter is repeated
// explicitly here for readability rather than relying on that implicitly,
// the same convention Milestone 20's resolveFeaturedBuild.js already
// established.
export async function getPublicDiscordConnection(userId) {
    const { data, error } = await supabase
        .from("social_connections")
        .select("provider_username, provider_avatar_url")
        .eq("user_id", userId)
        .eq("provider", "discord")
        .eq("is_public", true)
        .maybeSingle();

    if (error) throw error;
    return data;
}

export async function getMyDiscordConnection(userId) {
    const { data, error } = await supabase
        .from("social_connections")
        .select("*")
        .eq("user_id", userId)
        .eq("provider", "discord")
        .maybeSingle();

    if (error) throw error;
    return data;
}

export async function linkDiscord(redirectTo) {
    const { data, error } = await supabase.auth.linkIdentity({
        provider: "discord",
        options: { redirectTo }
    });

    if (error) throw error;
    return data;
}

export async function syncDiscordIdentity() {
    const { data, error } = await supabase.rpc("sync_discord_identity");
    if (error) throw error;
    return data;
}

export async function setDiscordVisibility(isPublic) {
    const { error } = await supabase
        .from("social_connections")
        .update({ is_public: isPublic })
        .eq("provider", "discord");

    if (error) throw error;
}

export async function disconnectDiscord() {
    const { data: identitiesData, error: identitiesError } = await supabase.auth.getUserIdentities();
    if (identitiesError) throw identitiesError;

    const discordIdentity = identitiesData?.identities?.find(identity => identity.provider === "discord");

    if (discordIdentity) {
        const { error: unlinkError } = await supabase.auth.unlinkIdentity(discordIdentity);
        if (unlinkError) throw unlinkError;
    }

    const { error: deleteError } = await supabase
        .from("social_connections")
        .delete()
        .eq("provider", "discord");

    if (deleteError) throw deleteError;
}

// Self-healing (spec §4.6/§4.7): reconciles Supabase Auth's own linked-
// identity state against this app's mirror row whenever they disagree —
// a linked identity with no mirror row means a sync never completed
// (network drop right after linking); a mirror row with no linked
// identity means a disconnect's delete succeeded but the Supabase-level
// unlink didn't, or vice versa. Safe and cheap to call unconditionally
// on every Settings load rather than trying to detect "did we just come
// back from a Discord OAuth redirect" specifically.
export async function reconcileDiscordConnection(userId) {
    const { data: identitiesData, error: identitiesError } = await supabase.auth.getUserIdentities();
    if (identitiesError) throw identitiesError;

    const hasLinkedIdentity = Boolean(
        identitiesData?.identities?.some(identity => identity.provider === "discord")
    );
    const existingConnection = await getMyDiscordConnection(userId);

    if (hasLinkedIdentity && !existingConnection) {
        return syncDiscordIdentity();
    }

    if (!hasLinkedIdentity && existingConnection) {
        await supabase.from("social_connections").delete().eq("provider", "discord");
        return null;
    }

    return existingConnection;
}
