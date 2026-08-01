// Pure parser — no DOM, no network, no catalog awareness. Turns pasted
// text (a PCPartPicker/BuildCore export, or any plain "Label: Value" per
// line list) into a flat array of {label, value} pairs. Matching those
// labels to real technology fields and looking values up against the
// components catalog both happen in ImportSpecificationsModal.js, which
// has the DOM/network access this file deliberately doesn't.
const LINE_PATTERNS = [
    /^([^:]{1,40}):\s*(.+)$/, // "CPU: Ryzen 7800X3D"
    /^([^\t]{1,40})\t+(.+)$/, // "CPU<TAB>Ryzen 7800X3D" (spreadsheet paste)
    /^([^,]{1,40}),\s*(.+)$/, // "CPU, Ryzen 7800X3D" (CSV export)
    /^([^-]{1,40})\s+-\s+(.+)$/ // "CPU - Ryzen 7800X3D"
];

export function parseComponentList(rawText) {
    return String(rawText || "")
        .split(/\r?\n/)
        .map(line => line.trim())
        .filter(Boolean)
        .map(parseLine)
        .filter(Boolean);
}

function parseLine(line) {
    for (const pattern of LINE_PATTERNS) {
        const match = line.match(pattern);

        if (!match) continue;

        const label = match[1].trim();
        const value = match[2].trim();

        if (label && value) {
            return { label, value };
        }
    }

    return null;
}
