export default {
    id: "robotics",
    slug: "robotics",
    title: "Robotics",
    subtitle: "Motors • AI • Engineering",
    icon: "robotics.svg",
    accent: "#FF8A3D",

    specifications: [
        { key: "controller", label: "Controller" },
        { key: "motor", label: "Motor" },
        { key: "sensor", label: "Sensor" },
        { key: "battery", label: "Battery" },
        { key: "mobility", label: "Mobility" },
        { key: "software", label: "Software" }
    ],

    filters: [
        {
            key: "controller",
            label: "Controller",
            type: "text",
            placeholder: "Arduino, Raspberry Pi..."
        },
        {
            key: "motor",
            label: "Motor",
            type: "text",
            placeholder: "Servo, stepper, DC..."
        },
        {
            key: "sensor",
            label: "Sensor",
            type: "text",
            placeholder: "LiDAR, camera..."
        },
        {
            key: "mobility",
            label: "Mobility",
            type: "text",
            placeholder: "Wheeled, tracked, arm..."
        }
    ]
};