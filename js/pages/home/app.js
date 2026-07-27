import { loadNavbar, loadFooter } from "../../core/layout.js";
import { getCurrentUser } from "../../core/auth.js";
import { renderActivityFeed } from "./renderActivityFeed.js";
import "../../features/featured.js";

import { CATEGORIES } from "../../config/categories.js";
import { TechnologyCard, hydrateTechnologyCards } from "../../components/TechnologyCard.js";



loadNavbar("");
loadFooter("");

const technologyGrid = document.getElementById("technologyGrid");

if (technologyGrid) {
    technologyGrid.innerHTML = CATEGORIES
        .filter(category => category.featured)
        .map(category => TechnologyCard(category, ""))
        .join("");

    hydrateTechnologyCards(technologyGrid);
}

if (document.getElementById("activityFeedGrid")) {
    getCurrentUser().then(renderActivityFeed);
}
