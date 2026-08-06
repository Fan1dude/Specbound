// Shared between TechnologyRadioCard.js (upload.html's form) and
// TechnologyChooserButton.js (the Welcome dialog's chooser step) — same
// per-category accent/icon CSSOM-hydration mechanism TechnologyCard.js
// already established (see its own comment on why this can't be an
// inline style="..." attribute under this app's CSP), applied to a
// second, differently-interactive card shape.
export function technologyPickerIconUrl(technology, pathPrefix = "") {
    return new URL(
        `${pathPrefix}assets/icons/categories/${technology.icon}`,
        document.baseURI
    ).href;
}

export function hydrateTechnologyPickerCards(container) {
    container.querySelectorAll("[data-category-accent]").forEach(el => {
        el.style.setProperty("--category-accent", el.dataset.categoryAccent);
        el.style.setProperty("--category-icon", `url('${el.dataset.categoryIcon}')`);
    });
}
