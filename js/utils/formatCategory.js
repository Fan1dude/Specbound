const CATEGORY_LABELS = {
    pc_build: "PC Build",
    setup: "Desk Setup",
    arduino: "Arduino",
    robotics: "Robotics",
    "3d_printer": "3D Printing",
    homelab: "Home Lab"
};

export function formatCategory(category) {
    return CATEGORY_LABELS[category] || "Technology";
}
