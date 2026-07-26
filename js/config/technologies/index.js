import pcBuild from "./pc-build.js";
import setup from "./setup.js";
import arduino from "./arduino.js";
import robotics from "./robotics.js";
import homelab from "./homelab.js";
import printing from "./printing.js";

export const TECHNOLOGIES = [
    pcBuild,
    setup,
    arduino,
    robotics,
    printing,
    homelab
];

export function getTechnology(id) {
    return TECHNOLOGIES.find(
        technology => technology.id === id
    ) || null;
}

export function getTechnologyFilters(id) {
    return getTechnology(id)?.filters || [];
}

export function getTechnologySpecifications(id) {
    return getTechnology(id)?.specifications || [];
}