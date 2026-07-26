export function TechnologyCard(category, pathPrefix = "") {
    const iconPath = new URL(
        `${pathPrefix}assets/icons/categories/${category.icon}`,
        document.baseURI
    ).href;

    return `
        <a
            class="technology-card card"
            href="${pathPrefix}pages/categories/${category.slug}.html"
            style="
                --category-accent: ${category.accent};
                --category-icon: url('${iconPath}');
            "
        >
            <div class="technology-card-icon" aria-hidden="true">
                <span class="technology-card-symbol"></span>
            </div>

            <div class="technology-card-body">
                <h3>${category.title}</h3>
                <p>${category.subtitle}</p>
            </div>

            <div class="technology-card-footer">
                <span>Explore</span>
                <span aria-hidden="true">→</span>
            </div>
        </a>
    `;
}