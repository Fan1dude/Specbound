import { loadNavbar, loadFooter } from "../../core/layout.js";

// Shared external entry point for the static legal pages (terms.html,
// privacy.html, community-guidelines.html, affiliate-disclosure.html) —
// their bootstrap used to be a bare inline `<script type="module">`
// block duplicated across all 4 files, blocked outright by this app's
// CSP (script-src has no `unsafe-inline`, no nonce/hash) the same way
// it blocked the category pages' inline bootstrap. Unlike category
// pages, these have no page-specific rendering logic — every one of
// them only ever needs navbar + footer, so one shared file covers all
// 4 rather than duplicating even this two-line body.
loadNavbar("../../");
loadFooter("../../");
