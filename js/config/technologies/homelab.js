export default {
    id: "homelab",
    slug: "home-labs",
    title: "Home Labs",
    subtitle: "Servers • Networking • Self-Hosting",
    icon: "homelab.svg",
    accent: "#22C7E8",

    specifications: [
        { key: "server", label: "Server" },
        { key: "cpu", label: "CPU" },
        { key: "memory", label: "Memory" },
        { key: "storage", label: "Storage" },
        { key: "networking", label: "Networking" },
        { key: "os", label: "Operating System" },
        { key: "services", label: "Services" }
    ],

    filters: [
        {
            key: "server",
            label: "Server Type",
            type: "text",
            placeholder: "Rack, mini PC, NAS..."
        },
        {
            key: "os",
            label: "Operating System",
            type: "text",
            placeholder: "Proxmox, TrueNAS..."
        },
        {
            key: "storage",
            label: "Storage",
            type: "text",
            placeholder: "ZFS, SSD, HDD..."
        },
        {
            key: "networking",
            label: "Networking",
            type: "text",
            placeholder: "2.5GbE, 10GbE..."
        }
    ]
};