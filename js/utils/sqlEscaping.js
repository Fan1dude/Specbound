// Postgres ILIKE treats %, _, and \ as special — escaping them first means
// a literal "%" or "_" typed by the user matches literally instead of
// acting as a wildcard.
export function escapeLikeSpecialChars(value) {
    return value.replace(/\\/g, "\\\\").replace(/%/g, "\\%").replace(/_/g, "\\_");
}

// PostgREST's .or() filter is a small DSL where "," "." "(" ")" are
// structural, not literal — this is its own escaping layer on top of the
// ILIKE escaping above, needed only for values embedded in an .or()
// string. Wrapping a value in double quotes (escaping any literal quote/
// backslash first) is PostgREST's documented way to pass an arbitrary
// string safely, so a search containing a comma or parenthesis can't
// corrupt or extend the filter.
export function quoteForOrFilter(value) {
    return `"${value.replace(/\\/g, "\\\\").replace(/"/g, "\\\"")}"`;
}
