export function fuzzyMatches(value, query) {
    const searchTokens = tokenize(query);

    if (!searchTokens.length) return true;

    const valueTokens = tokenize(value);
    const compactValue = normalizeCompact(value);

    return searchTokens.every(searchToken => {
        const compactSearch = normalizeCompact(searchToken);

        if (compactValue.includes(compactSearch)) {
            return true;
        }

        return valueTokens.some(valueToken =>
            wordsAreSimilar(valueToken, searchToken)
        );
    });
}

export function getRelevanceScore(value, query) {
    const normalizedValue = normalizeReadable(value);
    const normalizedQuery = normalizeReadable(query);

    const compactValue = normalizeCompact(value);
    const compactQuery = normalizeCompact(query);

    if (!normalizedQuery) return 0;

    // Exact readable match
    if (normalizedValue === normalizedQuery) {
        return 120;
    }

    // Exact match ignoring spaces and punctuation
    if (compactValue === compactQuery) {
        return 115;
    }

    // Exact phrase appears inside the value
    if (normalizedValue.includes(normalizedQuery)) {
        return 100;
    }

    if (compactValue.includes(compactQuery)) {
        return 95;
    }

    const queryTokens = tokenize(query);
    const valueTokens = tokenize(value);

    let score = 0;

    for (const queryToken of queryTokens) {
        if (isNumericToken(queryToken)) {
            score += scoreNumericToken(queryToken, valueTokens);
            continue;
        }

        if (valueTokens.includes(queryToken)) {
            score += 18;
            continue;
        }

        if (
            valueTokens.some(valueToken =>
                valueToken.startsWith(queryToken) ||
                queryToken.startsWith(valueToken)
            )
        ) {
            score += 12;
            continue;
        }

        if (
            valueTokens.some(valueToken =>
                wordsAreSimilar(valueToken, queryToken)
            )
        ) {
            score += 6;
        }
    }

    return score;
}

function normalizeReadable(value) {
    return String(value || "")
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, " ")
        .trim();
}

function isNumericToken(value) {
    return /^\d+(?:\.\d+)?$/.test(value);
}

function scoreNumericToken(queryToken, valueTokens) {
    const queryNumber = Number(queryToken);

    const valueNumbers = valueTokens
        .filter(isNumericToken)
        .map(Number);

    if (!valueNumbers.length) return 0;

    if (valueNumbers.includes(queryNumber)) {
        return 30;
    }

    const closestDifference = Math.min(
        ...valueNumbers.map(value =>
            Math.abs(value - queryNumber)
        )
    );

    // Nearby numbers remain possible alternatives,
    // but receive a much lower score.
    if (closestDifference <= 2) return 10;
    if (closestDifference <= 4) return 7;
    if (closestDifference <= 8) return 3;

    return 0;
}

export function findClosestSuggestions(
    query,
    choices,
    limit = 5
) {
    const normalizedQuery = normalizeCompact(query);

    if (!normalizedQuery) return [];

    return [...new Set(choices.filter(Boolean))]
        .map(choice => {
            const normalizedChoice = normalizeCompact(choice);

            return {
                value: String(choice),
                score: similarityScore(
                    normalizedQuery,
                    normalizedChoice
                )
            };
        })
        .filter(item => item.score >= 0.45)
        .sort((a, b) => b.score - a.score)
        .slice(0, limit)
        .map(item => item.value);
}

function tokenize(value) {
    return String(value || "")
        .toLowerCase()
        .replace(/([a-z])(\d)/g, "$1 $2")
        .replace(/(\d)([a-z])/g, "$1 $2")
        .replace(/[^a-z0-9]+/g, " ")
        .trim()
        .split(/\s+/)
        .filter(Boolean);
}

function normalizeCompact(value) {
    return String(value || "")
        .toLowerCase()
        .replace(/[^a-z0-9]/g, "");
}

function wordsAreSimilar(first, second) {
    const a = normalizeCompact(first);
    const b = normalizeCompact(second);

    if (!a || !b) return false;

    if (isNumericToken(a) && isNumericToken(b)) {
        return a === b;
    }

    if (a.includes(b) || b.includes(a)) return true;

    const allowedDistance =
        Math.max(a.length, b.length) <= 5
            ? 1
            : Math.max(a.length, b.length) <= 10
                ? 2
                : 3;

    return levenshteinDistance(a, b) <= allowedDistance;
}

function similarityScore(first, second) {
    if (first.includes(second) || second.includes(first)) {
        return 0.95;
    }

    const longestLength = Math.max(
        first.length,
        second.length
    );

    if (!longestLength) return 1;

    const distance = levenshteinDistance(first, second);

    return 1 - distance / longestLength;
}

function levenshteinDistance(first, second) {
    const rows = second.length + 1;
    const columns = first.length + 1;

    const matrix = Array.from(
        { length: rows },
        () => Array(columns).fill(0)
    );

    for (let column = 0; column < columns; column++) {
        matrix[0][column] = column;
    }

    for (let row = 0; row < rows; row++) {
        matrix[row][0] = row;
    }

    for (let row = 1; row < rows; row++) {
        for (let column = 1; column < columns; column++) {
            const cost =
                second[row - 1] === first[column - 1]
                    ? 0
                    : 1;

            matrix[row][column] = Math.min(
                matrix[row - 1][column] + 1,
                matrix[row][column - 1] + 1,
                matrix[row - 1][column - 1] + cost
            );
        }
    }

    return matrix[rows - 1][columns - 1];
}