import { loadNavbar, loadFooter } from "../../core/layout.js";

// Launch Readiness self-service account deletion — the redirect target
// after a successful deletion (js/pages/settings/renderDeleteAccountSection.js).
// No per-page logic beyond navbar/footer: by the time a visitor lands
// here, the account is already gone and there is no session to check —
// this page is deliberately reachable while signed out, unlike every
// other post-auth-action page in this app.
loadNavbar("../");
loadFooter("../");
