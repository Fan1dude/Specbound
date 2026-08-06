import { searchComponents } from "../repositories/componentRepository.js";
import { escapeHtml } from "../utils/escapeHtml.js";

// Returns { destroy() } — callers that re-render (e.g. switching technology
// in the project editor, which recreates these fields) must call destroy()
// on the previous instance first. Without it, the document-level click
// listener below has nothing to remove it, and every re-render leaks
// another one — each is inert once its wrapper is gone, but they never get
// garbage collected for the life of the page.
export function setupComponentAutocomplete({
    input,
    technologyId,
    componentType,
    minimumCharacters = 2,
    onSelect = () => {},
    // Optional — when provided, an empty result set offers a "Suggest as
    // a new component" action instead of just a dead-end message. Not
    // repository logic itself (this file already imports searchComponents
    // directly, so that boundary isn't new), but kept as a caller-supplied
    // async callback rather than importing submitComponent() here, so the
    // caller controls what technologyId/fieldKey semantics and toast
    // feedback look like. Must return a Promise; rejecting it re-enables
    // the button so the user can retry.
    onSubmitNew = null
}) {
    const inputElement =
        typeof input === "string"
            ? document.querySelector(input)
            : input;

    if (!inputElement) return { destroy() {} };

    const wrapper = document.createElement("div");
    wrapper.className = "component-autocomplete";

    inputElement.parentNode.insertBefore(wrapper, inputElement);
    wrapper.appendChild(inputElement);

    const resultsElement = document.createElement("div");
    resultsElement.className = "component-autocomplete-results";
    resultsElement.id = `${inputElement.id || "component-autocomplete"}-listbox`;
    resultsElement.setAttribute("role", "listbox");
    resultsElement.hidden = true;

    wrapper.appendChild(resultsElement);

    let activeIndex = -1;
    let currentResults = [];
    let currentQuery = "";
    let requestTimer = null;
    let destroyed = false;

    inputElement.setAttribute("autocomplete", "off");
    inputElement.setAttribute("role", "combobox");
    inputElement.setAttribute("aria-expanded", "false");
    inputElement.setAttribute("aria-controls", resultsElement.id);

    inputElement.addEventListener("input", handleInput);
    inputElement.addEventListener("keydown", handleKeydown);
    document.addEventListener("click", handleDocumentClick);

    function handleInput() {
        clearTimeout(requestTimer);

        const query = inputElement.value.trim();

        currentQuery = query;
        inputElement.dataset.componentId = "";
        activeIndex = -1;

        if (query.length < minimumCharacters) {
            closeResults();
            return;
        }

        resultsElement.innerHTML = `
            <div class="component-autocomplete-state">
                Searching components...
            </div>
        `;

        openResults();

        requestTimer = setTimeout(async () => {
            try {
                const results = await searchComponents({
                    query,
                    technologyId,
                    componentType,
                    limit: 8
                });

                // The component may have been destroyed (re-render elsewhere)
                // while this request was in flight.
                if (destroyed) return;

                currentResults = results;
                renderResults();
            } catch (error) {
                if (destroyed) return;

                console.error("Autocomplete error:", error);

                resultsElement.innerHTML = `
                    <div class="component-autocomplete-state">
                        Components could not be loaded.
                    </div>
                `;
            }
        }, 250);
    }

    function handleKeydown(event) {
        if (resultsElement.hidden || !currentResults.length) {
            return;
        }

        if (event.key === "ArrowDown") {
            event.preventDefault();

            activeIndex =
                (activeIndex + 1) % currentResults.length;

            updateActiveResult();
        }

        if (event.key === "ArrowUp") {
            event.preventDefault();

            activeIndex =
                (activeIndex - 1 + currentResults.length) %
                currentResults.length;

            updateActiveResult();
        }

        if (event.key === "Enter" && activeIndex >= 0) {
            event.preventDefault();
            selectResult(currentResults[activeIndex]);
        }

        if (event.key === "Escape") {
            closeResults();
        }
    }

    function handleDocumentClick(event) {
        if (!wrapper.contains(event.target)) {
            closeResults();
        }
    }

    function renderResults() {
        if (!currentResults.length) {
            renderEmptyState();
            openResults();
            return;
        }

        resultsElement.innerHTML = currentResults
            .map((component, index) => `
                <button
                    class="component-autocomplete-option"
                    type="button"
                    data-index="${index}"
                    id="${resultsElement.id}-option-${index}"
                    role="option"
                    aria-selected="false"
                >
                    <span>
                        ${escapeHtml(component.canonical_name)}
                    </span>

                    ${
                        component.manufacturer
                            ? `
                                <small>
                                    ${escapeHtml(component.manufacturer)}
                                </small>
                            `
                            : ""
                    }
                </button>
            `)
            .join("");

        resultsElement
            .querySelectorAll(".component-autocomplete-option")
            .forEach(button => {
                button.addEventListener("click", () => {
                    const index = Number(button.dataset.index);
                    selectResult(currentResults[index]);
                });
            });

        openResults();
    }

    function renderEmptyState() {
        if (!onSubmitNew) {
            resultsElement.innerHTML = `
                <div class="component-autocomplete-state">
                    No matching components found. You may keep your custom value.
                </div>
            `;
            return;
        }

        resultsElement.innerHTML = `
            <div class="component-autocomplete-state">
                No matching components found. You may keep your custom value, or suggest it for the shared catalog.
            </div>

            <button type="button" class="component-autocomplete-submit-new btn btn-ghost btn-small">
                Suggest "${escapeHtml(currentQuery)}" as a new component
            </button>
        `;

        resultsElement
            .querySelector(".component-autocomplete-submit-new")
            ?.addEventListener("click", handleSubmitNewClick);
    }

    async function handleSubmitNewClick(event) {
        const button = event.currentTarget;
        const submittedQuery = currentQuery;

        button.disabled = true;
        button.textContent = "Submitting...";

        try {
            await onSubmitNew(submittedQuery);

            if (destroyed) return;

            resultsElement.innerHTML = `
                <div class="component-autocomplete-state">
                    Submitted "${escapeHtml(submittedQuery)}" for review. Your typed value is still saved on this build either way.
                </div>
            `;
        } catch (error) {
            if (destroyed) return;

            console.error("Component submission error:", error);
            renderEmptyState();
        }
    }

    function updateActiveResult() {
        let activeOption = null;

        resultsElement
            .querySelectorAll(".component-autocomplete-option")
            .forEach((option, index) => {
                const isActive = index === activeIndex;

                option.classList.toggle("is-active", isActive);
                option.setAttribute("aria-selected", String(isActive));

                if (isActive) activeOption = option;
            });

        if (activeOption) {
            inputElement.setAttribute("aria-activedescendant", activeOption.id);
        } else {
            inputElement.removeAttribute("aria-activedescendant");
        }
    }

    function selectResult(component) {
        inputElement.value = component.canonical_name;
        inputElement.dataset.componentId = component.id;

        closeResults();

        // Setting .value directly (as opposed to a user keystroke) does not
        // dispatch a native "input" event, so a caller relying only on that
        // listener would never learn the componentId was set — this is the
        // callback that closes that gap.
        onSelect(component);
    }

    function openResults() {
        resultsElement.hidden = false;
        inputElement.setAttribute("aria-expanded", "true");
    }

    function closeResults() {
        resultsElement.hidden = true;
        inputElement.setAttribute("aria-expanded", "false");
        inputElement.removeAttribute("aria-activedescendant");
        activeIndex = -1;
    }

    function destroy() {
        destroyed = true;
        clearTimeout(requestTimer);
        document.removeEventListener("click", handleDocumentClick);
        inputElement.removeEventListener("input", handleInput);
        inputElement.removeEventListener("keydown", handleKeydown);
    }

    return { destroy };
}

