export function SpotlightSlide(data) {

    return `
    
        <article class="spotlight-slide">

            <div class="spotlight-image">

                <img src="${data.image}" alt="${data.title}">

            </div>

            <div class="spotlight-content">

                <span class="spotlight-tag">
                    ${data.tag}
                </span>

                <h2>${data.title}</h2>

                <p>${data.subtitle}</p>

                <a
                    href="${data.href}"
                    class="btn btn-primary">

                    ${data.button}

                </a>

            </div>

        </article>

    `;

}