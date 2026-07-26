// Section navigation shell. Only Overview has a real panel in Milestone 4A —
// the other tabs are rendered disabled until their sections are built, so
// nothing here fakes a working feature.
export function setupEditorTabs() {
    const tabs = Array.from(document.querySelectorAll("#editorTabs .tab:not([disabled])"));

    function activateTab(tab) {
        tabs.forEach(other => {
            other.classList.remove("is-active");
            other.setAttribute("aria-selected", "false");
        });

        tab.classList.add("is-active");
        tab.setAttribute("aria-selected", "true");

        const section = tab.dataset.section;

        document.querySelectorAll(".editor-panel").forEach(panel => {
            panel.hidden = panel.id !== `panel-${section}`;
        });
    }

    tabs.forEach((tab, index) => {
        tab.addEventListener("click", () => activateTab(tab));

        // Standard WAI-ARIA Tabs pattern: once a tab has focus, ArrowLeft/
        // ArrowRight move to (and activate) the adjacent enabled tab,
        // wrapping at the ends — the disabled tabs are already excluded
        // from `tabs`, so this never lands on one of them.
        tab.addEventListener("keydown", event => {
            if (event.key !== "ArrowLeft" && event.key !== "ArrowRight") return;

            event.preventDefault();

            const delta = event.key === "ArrowRight" ? 1 : -1;
            const nextTab = tabs[(index + delta + tabs.length) % tabs.length];

            nextTab.focus();
            activateTab(nextTab);
        });
    });
}
