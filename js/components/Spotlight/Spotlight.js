import { SpotlightSlide } from "./SpotlightSlide.js";

const demoSlides = [

{
    tag: "Featured Blueprint",

    title: "Project Titan",

    subtitle:
        "A custom gaming workstation built for performance and productivity.",

    image: "assets/images/demo/project.jpg",

    href:"#",

    button:"View Blueprint"

}

];

export function renderSpotlight(container){

    container.innerHTML =
        SpotlightSlide(demoSlides[0]);

}