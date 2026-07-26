export default {
    id: "pc_build",
    slug: "pc-builds",
    title: "PC Builds",
    subtitle: "Gaming • Workstations • Servers",
    icon: "pc.svg",
    accent: "#4F7DFF",

    specifications: [
        { key: "cpu", label: "CPU" },
        { key: "gpu", label: "GPU" },
        { key: "motherboard", label: "Motherboard" },
        { key: "ram", label: "Memory" },
        { key: "storage", label: "Storage" },
        { key: "psu", label: "Power Supply" },
        { key: "case", label: "Case" },
        { key: "cooler", label: "Cooling" }
    ],

    filters: [
        {
            key: "cpu",
            label: "CPU",
            type: "text",
            placeholder: "Ryzen, Intel..."
        },
        {
            key: "gpu",
            label: "GPU",
            type: "text",
            placeholder: "RTX, Radeon, Arc..."
        },
        {
            key: "ram",
            label: "Memory",
            type: "text",
            placeholder: "32GB, DDR5..."
        },
        {
            key: "storage",
            label: "Storage",
            type: "text",
            placeholder: "NVMe, 2TB..."
        },
        {
            key: "case",
            label: "Case",
            type: "text",
            placeholder: "NZXT, Fractal..."
        }
    ]
};