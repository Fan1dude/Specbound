export default {
    id: "arduino",
    slug: "arduino",
    title: "Arduino",
    subtitle: "Automation • Sensors • Embedded",
    icon: "arduino.svg",
    accent: "#32D583",

    specifications: [
        { key: "board", label: "Board" },
        { key: "sensor", label: "Sensor" },
        { key: "display", label: "Display" },
        { key: "communication", label: "Communication" },
        { key: "power", label: "Power" },
        { key: "motor", label: "Motor" }
    ],

    filters: [
        {
            key: "board",
            label: "Board",
            type: "text",
            placeholder: "Uno, Nano, ESP32..."
        },
        {
            key: "sensor",
            label: "Sensor",
            type: "text",
            placeholder: "Ultrasonic, temperature..."
        },
        {
            key: "display",
            label: "Display",
            type: "text",
            placeholder: "OLED, LCD, TFT..."
        },
        {
            key: "communication",
            label: "Communication",
            type: "text",
            placeholder: "Wi-Fi, Bluetooth, LoRa..."
        }
    ]
};