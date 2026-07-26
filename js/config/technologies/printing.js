export default {
    id: "3d_printer",
    slug: "3d-printing",
    title: "3D Printing",
    subtitle: "Printers • Models • Fabrication",
    icon: "3d-printing.svg",
    accent: "#EC5FA7",

    specifications: [
        { key: "printer", label: "Printer" },
        { key: "process", label: "Process" },
        { key: "material", label: "Material" },
        { key: "nozzle", label: "Nozzle" },
        { key: "layer_height", label: "Layer Height" },
        { key: "slicer", label: "Slicer" }
    ],

    filters: [
        {
            key: "printer",
            label: "Printer",
            type: "text",
            placeholder: "Bambu, Prusa, Ender..."
        },
        {
            key: "process",
            label: "Process",
            type: "text",
            placeholder: "FDM, resin..."
        },
        {
            key: "material",
            label: "Material",
            type: "text",
            placeholder: "PLA, PETG, ABS..."
        },
        {
            key: "nozzle",
            label: "Nozzle",
            type: "text",
            placeholder: "0.4mm, hardened steel..."
        }
    ]
};