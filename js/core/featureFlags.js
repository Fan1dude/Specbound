// Centralized feature-flag registry. A flag here gates whether a shipped,
// tested capability is currently AVAILABLE to users -- not whether the
// code exists. Turning a flag off never deletes, disconnects, or hides
// data; it only stops the app from initiating new activity for that
// feature and stops rendering its UI.
//
// Deliberately a plain, frozen, hardcoded object -- not backed by
// localStorage, a query parameter, a cookie, or any other user-controlled
// input. A flag here is a deployment-time decision this app's own source
// makes, not something a visitor (or a browser DevTools session) can
// flip. Changing availability means changing a value below and shipping
// a new deploy.
export const FEATURE_FLAGS = Object.freeze({
    // Discord server access, account linking (Settings -> Connected
    // Accounts and the public-profile Connected Accounts display),
    // verification, and automatic role assignment. Built and merged as
    // part of Milestone 22 (Community Foundation) -- fully implemented,
    // not removed; every migration, RLS policy, RPC, repository method,
    // and UI component stays in the codebase while this is false. Held
    // back as a deliberate beta-launch-sequencing decision, not a defect
    // or a rollback.
    //
    // Enable after 100 legitimate published community builds and
    // production Discord readiness verification.
    discordConnections: false
});

// A small accessor, not a direct FEATURE_FLAGS import, at every call
// site -- gives every caller the same shape if a flag's storage or
// computation ever needs to change later (e.g. a per-environment
// override), without touching every place that reads one.
export function isFeatureEnabled(flagName) {
    return FEATURE_FLAGS[flagName] === true;
}
