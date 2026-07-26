export default {
    id: "setup",
    slug: "desk-setups",
    title: "Desk Setups",
    subtitle: "Battlestations • Productivity • Streaming",
    icon: "setup.svg",
    accent: "#9B6CFF",

    specifications: [
        { key: "desk", label: "Desk" },
        { key: "chair", label: "Chair" },
        { key: "monitor", label: "Monitor" },
        { key: "keyboard", label: "Keyboard" },
        { key: "mouse", label: "Mouse" },
        { key: "microphone", label: "Microphone" },
        { key: "lighting", label: "Lighting" }
    ],

    filters: [
        {
            key: "desk",
            label: "Desk",
            type: "text",
            placeholder: "Standing, corner..."
        },
        {
            key: "monitor",
            label: "Monitor",
            type: "text",
            placeholder: "Ultrawide, dual monitor..."
        },
        {
            key: "keyboard",
            label: "Keyboard",
            type: "text",
            placeholder: "Mechanical, 75%..."
        },
        {
            key: "lighting",
            label: "Lighting",
            type: "text",
            placeholder: "RGB, ambient..."
        }
    ]
};