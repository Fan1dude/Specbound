import { loadNavbar, loadFooter } from "../../core/layout.js";
import { CATEGORIES } from "../../config/categories.js";
import { TechnologyCard, hydrateTechnologyCards } from "../../components/TechnologyCard.js";

loadNavbar("");
loadFooter("");

const technologyGrid =
    document.getElementById("designTechnologyGrid");

if (technologyGrid) {
    technologyGrid.innerHTML = CATEGORIES
        .filter(category => category.featured)
        .map(category => TechnologyCard(category, ""))
        .join("");

    hydrateTechnologyCards(technologyGrid);
}