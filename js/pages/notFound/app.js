import { loadNavbar, loadFooter } from "../../core/layout.js";
import { icon } from "../../utils/icons.js";

loadNavbar();
loadFooter();

document.querySelector(".empty-state")
    ?.insertAdjacentHTML("afterbegin", `<div class="empty-state-icon">${icon("search", 32)}</div>`);
