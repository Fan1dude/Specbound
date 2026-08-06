import { escapeHtml, escapeAttribute } from "../utils/escapeHtml.js";
import { parseComponentList } from "../utils/parseComponentList.js";
import { getRelevanceScore } from "../utils/fuzzySearch.js";
import { searchComponents, findExactComponentMatch } from "../repositories/componentRepository.js";

// Below this relevance score, a parsed line's label isn't considered a
// match for a technology field — see getRelevanceScore in fuzzySearch.js
// (12 is its "one token is a prefix of the other" tier).
const MIN_FIELD_MATCH_SCORE = 12;

// Below this, a catalog ilike hit isn't worth surfacing as a fuzzy
// suggestion at all — fuzzySearch.js's "similar word" tier.
const MIN_SUGGESTION_SCORE = 6;
const MAX_SUGGESTIONS = 3;

// Paste-list import (PCPartPicker/BuildCore text/CSV exports, or any
// plain "Label: Value" list) — no scraping, no provider API (out of
// scope, see the architecture plan). Reuses the .modal CSS classes from
// modal.css but isn't a confirmDialog() call, since it needs a textarea
// and a review step instead of a single confirm/cancel choice.
//
// Nothing here saves anything. The reviewed {fieldKey: {componentId,
// name}} map goes back to the caller via onImport() — the manual
// picker's own save path (renderSpecificationsSection.js's setValue())
// is always what actually persists a value. Fuzzy matching may suggest,
// never persist.
//
// Milestone 19 revision: every parsed line always produces a review row
// — matched, needs review, or unrecognized — never silently dropped (see
// the architecture doc §4.3). Only an exact catalog match (canonical
// name or alias, checked via findExactComponentMatch) attaches a
// componentId automatically; anything else surfaced as a fuzzy
// suggestion requires the user to explicitly confirm it (§4.4).
export function openImportSpecificationsModal({ technologyId, fields, onImport }) {
    const dialog = document.createElement("dialog");
    dialog.className = "modal modal-import-specifications";

    dialog.innerHTML = `
        <div class="modal-body">
            <h2 class="modal-title">Import from a parts list</h2>
            <p class="modal-message">
                Paste an exported parts list — PCPartPicker, BuildCore, or any
                "Label: Value" per-line list. Every line is shown for review;
                nothing is saved until you confirm.
            </p>

            <label for="importSpecificationsText" class="sr-only">Pasted parts list</label>
            <textarea
                id="importSpecificationsText"
                rows="8"
                placeholder="CPU: AMD Ryzen 7 7800X3D&#10;GPU: NVIDIA RTX 4080&#10;..."
            ></textarea>

            <div id="importSpecificationsReview" class="import-specifications-review" hidden></div>

            <div class="modal-actions">
                <button type="button" class="btn btn-secondary" data-action="cancel">Cancel</button>
                <button type="button" class="btn btn-primary" data-action="parse">Review matches</button>
            </div>
        </div>
    `;

    document.body.appendChild(dialog);

    const textarea = dialog.querySelector("#importSpecificationsText");
    const reviewContainer = dialog.querySelector("#importSpecificationsReview");
    const actionButton = dialog.querySelector('[data-action="parse"]');
    const cancelButton = dialog.querySelector('[data-action="cancel"]');

    // The single source of truth for the review step — re-rendered
    // wholesale on every state change (assigning an unrecognized line to
    // a field, confirming a fuzzy suggestion), same pattern the rest of
    // this codebase uses (e.g. renderGallerySection.js) rather than
    // patching individual DOM nodes.
    let rows = [];

    cancelButton.addEventListener("click", close);

    // Native Esc fires "cancel" first — preventDefault stops the dialog
    // from closing itself so the same fade-out close() path always runs.
    dialog.addEventListener("cancel", event => {
        event.preventDefault();
        close();
    });

    dialog.addEventListener("click", event => {
        if (event.target === dialog) close();
    });

    actionButton.addEventListener("click", async () => {
        if (actionButton.dataset.mode === "import") {
            runImport();
            return;
        }

        const parsedEntries = parseComponentList(textarea.value);

        if (!parsedEntries.length) {
            reviewContainer.hidden = false;
            reviewContainer.innerHTML = `<p class="text-secondary">No lines could be parsed. Try one "Label: Value" pair per line.</p>`;
            return;
        }

        actionButton.disabled = true;
        actionButton.textContent = "Matching...";

        rows = await buildRows(parsedEntries, fields, technologyId);

        actionButton.disabled = false;
        actionButton.dataset.mode = "import";
        actionButton.textContent = "Import reviewed values";

        renderReview();
    });

    function renderReview() {
        reviewContainer.hidden = false;

        const matched = rows.filter(row => row.fieldKey && row.matchState === "confirmed");
        const needsReview = rows.filter(row => row.fieldKey && row.matchState !== "confirmed");
        const unrecognized = rows.filter(row => !row.fieldKey);

        reviewContainer.innerHTML = `
            ${renderSection("Matched", matched, renderMatchedRow)}
            ${renderSection("Needs review", needsReview, renderNeedsReviewRow)}
            ${renderSection("Unrecognized", unrecognized, renderUnrecognizedRow)}
        `;

        wireRowEvents();
    }

    function renderSection(title, sectionRows, renderRow) {
        if (!sectionRows.length) return "";

        return `
            <div class="import-specifications-section">
                <p class="import-specifications-section-heading">${escapeHtml(title)} (${sectionRows.length})</p>
                ${sectionRows.map(renderRow).join("")}
            </div>
        `;
    }

    function renderMatchedRow(row) {
        return `
            <div class="import-specifications-row" data-row-id="${row.rowId}">
                <label for="import-row-${row.rowId}">${escapeHtml(row.fieldLabel)}</label>
                <input id="import-row-${row.rowId}" type="text" class="import-row-input" data-row-id="${row.rowId}" value="${escapeAttribute(row.name)}">
                <span class="badge import-match-badge is-confirmed">Catalog match</span>
            </div>
        `;
    }

    function renderNeedsReviewRow(row) {
        const suggestions = row.matchState === "suggested"
            ? `
                <div class="import-suggestion-list">
                    ${row.suggestions.map(suggestion => `
                        <button
                            type="button"
                            class="import-suggestion-confirm"
                            data-row-id="${row.rowId}"
                            data-component-id="${escapeAttribute(suggestion.id)}"
                            data-component-name="${escapeAttribute(suggestion.canonical_name)}"
                        >
                            Use "${escapeHtml(suggestion.canonical_name)}" (${suggestion.confidence}% match)
                        </button>
                    `).join("")}
                </div>
            `
            : "";

        return `
            <div class="import-specifications-row is-needs-review" data-row-id="${row.rowId}">
                <label for="import-row-${row.rowId}">${escapeHtml(row.fieldLabel)}</label>
                <input id="import-row-${row.rowId}" type="text" class="import-row-input" data-row-id="${row.rowId}" value="${escapeAttribute(row.name)}">
                ${row.matchState === "suggested" ? `<span class="badge import-match-badge is-suggested">Possible match</span>` : ""}
                ${suggestions}
            </div>
        `;
    }

    function renderUnrecognizedRow(row) {
        return `
            <div class="import-specifications-row is-unrecognized" data-row-id="${row.rowId}">
                <p class="import-unrecognized-line">
                    <strong>${escapeHtml(row.rawLabel)}</strong>: ${escapeHtml(row.rawValue)}
                </p>

                <label for="import-assign-${row.rowId}" class="sr-only">Assign this line to a field</label>
                <select id="import-assign-${row.rowId}" class="import-assign-field" data-row-id="${row.rowId}">
                    <option value="">Skip this line</option>
                    ${fields.map(field => `<option value="${escapeAttribute(field.key)}">${escapeHtml(field.label)}</option>`).join("")}
                </select>
            </div>
        `;
    }

    function wireRowEvents() {
        reviewContainer.querySelectorAll(".import-row-input").forEach(input => {
            input.addEventListener("input", () => {
                const row = findRow(input.dataset.rowId);
                if (row) row.name = input.value;
            });
        });

        reviewContainer.querySelectorAll(".import-suggestion-confirm").forEach(button => {
            button.addEventListener("click", () => {
                const row = findRow(button.dataset.rowId);
                if (!row) return;

                row.matchState = "confirmed";
                row.componentId = button.dataset.componentId;
                row.componentName = button.dataset.componentName;
                row.name = button.dataset.componentName;

                renderReview();
            });
        });

        reviewContainer.querySelectorAll(".import-assign-field").forEach(select => {
            select.addEventListener("change", async () => {
                const row = findRow(select.dataset.rowId);
                if (!row) return;

                const fieldKey = select.value;

                if (!fieldKey) {
                    rows = rows.filter(candidate => candidate.rowId !== row.rowId);
                    renderReview();
                    return;
                }

                const field = fields.find(candidate => candidate.key === fieldKey);
                select.disabled = true;

                const classified = await classifyEntry(
                    { label: row.rawLabel, value: row.rawValue },
                    field,
                    technologyId
                );

                Object.assign(row, { fieldKey, fieldLabel: field.label }, classified);
                renderReview();
            });
        });
    }

    function findRow(rowId) {
        return rows.find(row => String(row.rowId) === String(rowId));
    }

    function runImport() {
        const fieldValues = {};

        rows.forEach(row => {
            if (!row.fieldKey) return;

            const name = (row.name || "").trim();
            if (!name) return;

            // componentId only survives if the reviewer left the
            // pre-filled/confirmed catalog name untouched — an edited
            // value is no longer guaranteed to refer to that catalog row.
            fieldValues[row.fieldKey] = {
                name,
                componentId: row.matchState === "confirmed" && name === row.componentName
                    ? row.componentId
                    : null
            };
        });

        onImport(fieldValues);
        close();
    }

    function close() {
        dialog.classList.remove("is-open");
        // Matches --duration-fast (150ms), same asymmetry rule confirmDialog
        // uses — close is always faster than open.
        setTimeout(() => {
            dialog.close();
            dialog.remove();
        }, 150);
    }

    dialog.showModal();
    requestAnimationFrame(() => dialog.classList.add("is-open"));
}

// Splits parsed lines into field-assigned and unassigned groups (greedy
// best-match, one pasted line can't be claimed by two fields), then
// classifies every field-assigned line's catalog match state. Unassigned
// lines become rowId-bearing "unrecognized" rows directly — never
// dropped, per §4.3 of the architecture doc.
async function buildRows(entries, fields, technologyId) {
    const usedEntryIndexes = new Set();
    const assigned = [];

    fields.forEach(field => {
        let bestIndex = -1;
        let bestScore = 0;

        entries.forEach((entry, index) => {
            if (usedEntryIndexes.has(index)) return;

            const score = getRelevanceScore(field.label, entry.label);

            if (score > bestScore) {
                bestScore = score;
                bestIndex = index;
            }
        });

        if (bestIndex !== -1 && bestScore >= MIN_FIELD_MATCH_SCORE) {
            usedEntryIndexes.add(bestIndex);
            assigned.push({ entry: entries[bestIndex], field });
        }
    });

    let rowId = 0;

    const matchedRows = await Promise.all(assigned.map(async ({ entry, field }) => ({
        rowId: rowId++,
        fieldKey: field.key,
        fieldLabel: field.label,
        rawLabel: entry.label,
        rawValue: entry.value,
        ...(await classifyEntry(entry, field, technologyId))
    })));

    const unrecognizedRows = entries
        .filter((_, index) => !usedEntryIndexes.has(index))
        .map(entry => ({
            rowId: rowId++,
            fieldKey: null,
            fieldLabel: null,
            rawLabel: entry.label,
            rawValue: entry.value,
            matchState: null,
            componentId: null,
            componentName: null,
            name: entry.value,
            suggestions: []
        }));

    return [...matchedRows, ...unrecognizedRows];
}

// Only an exact catalog match (canonical name or alias) may attach a
// componentId automatically. Everything else is either a fuzzy
// "suggested" candidate requiring explicit confirmation, or plain
// "unmatched" free text — never auto-attached either way.
async function classifyEntry(entry, field, technologyId) {
    try {
        const exactMatch = await findExactComponentMatch({
            query: entry.value,
            technologyId,
            fieldKey: field.key
        });

        if (exactMatch) {
            return {
                matchState: "confirmed",
                componentId: exactMatch.id,
                componentName: exactMatch.canonical_name,
                name: exactMatch.canonical_name,
                suggestions: []
            };
        }

        const candidates = await searchComponents({
            query: entry.value,
            technologyId,
            componentType: field.key,
            limit: 8
        });

        const suggestions = candidates
            .map(candidate => ({
                id: candidate.id,
                canonical_name: candidate.canonical_name,
                score: getRelevanceScore(candidate.canonical_name, entry.value)
            }))
            .filter(candidate => candidate.score >= MIN_SUGGESTION_SCORE)
            .sort((a, b) => b.score - a.score)
            .slice(0, MAX_SUGGESTIONS)
            // Capped below 100 — this tier is explicitly not an exact
            // match (that's the "confirmed" tier above), so a raw score
            // that happens to reach/exceed 100 shouldn't display as if
            // it were one.
            .map(candidate => ({ ...candidate, confidence: Math.min(99, Math.round(candidate.score)) }));

        if (suggestions.length) {
            return {
                matchState: "suggested",
                componentId: null,
                componentName: null,
                name: entry.value,
                suggestions
            };
        }
    } catch (error) {
        // Best-effort only — a failed catalog lookup still leaves the
        // parsed value available for manual review, just without a
        // pre-attached componentId or suggestions.
        console.error("Import catalog lookup error:", error);
    }

    return {
        matchState: "unmatched",
        componentId: null,
        componentName: null,
        name: entry.value,
        suggestions: []
    };
}
