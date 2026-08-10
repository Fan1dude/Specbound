import { loadNavbar, loadFooter } from "../../core/layout.js";
import { renderCategoryPage } from "./renderCategoryPage.js";

// Shared external entry point for all 6 category landing pages
// (pc-builds/desk-setups/arduino/robotics/3d-printing/home-labs.html) —
// their bootstrap used to be a bare inline `<script type="module">`
// block duplicated across all 6 files. This app's CSP
// (`script-src 'self' https://cdn.jsdelivr.net`, no `unsafe-inline`, no
// nonce/hash) blocks inline script content outright, so that block
// never ran in production: navbar, page content, and footer all stayed
// empty. Every other page in this app already bootstraps via an
// external `<script type="module" src="...">` (e.g.
// js/pages/explore/app.js) for exactly this reason — this file brings
// category pages in line with that pattern. One file instead of 6
// identical inline copies since all 6 pages need the exact same
// pathPrefix and the same three calls; renderCategoryPage() itself
// already reads which category to render from the page's own
// `<main data-category="...">` attribute.
loadNavbar("../../");
loadFooter("../../");
renderCategoryPage("../../");
