# Milestone 24 — Moderator Report Queue

Status: Implemented. Written after implementation as the design record —
unlike Milestone 21's pre-implementation spec, this document describes
what was actually built, not a proposal awaiting approval. Local-only
verification against disposable Supabase test data; not yet deployed to
production.

## 1. Problem

Milestone 22 shipped `ReportButton.js` (builders can report a project,
comment) and the server-side contract for acting on those reports —
`content_reports`, `moderation_actions`, and a `resolve_report()` RPC,
all in migration `0028_moderation.sql`. Nothing in the application ever
called `resolve_report()`. Reports could be filed but never reviewed.

## 2. Existing database contract (confirmed by reading migrations, not assumed)

No new migration was needed. Confirmed by reading `0028_moderation.sql`
and `0027_profile_roles.sql` directly before writing any application
code:

- `content_reports` — `id`, `reporter_id`, `target_type` (`build` /
  `comment` / `profile`), `target_id` (plain `uuid`, no FK — the target
  table depends on `target_type`), `reason`, `status` (`open` /
  `reviewed` / `dismissed`, default `open`), `reviewed_by`,
  `reviewed_at`, `created_at`. Unique on `(reporter_id, target_type,
  target_id)`. RLS: a reporter sees their own reports; a moderator sees
  all; no direct write policy for anyone — all writes go through
  `resolve_report()`.
- `moderation_actions` — an audit trail row per moderation event
  (`action_type` includes `report_resolved`, `role_granted`,
  `role_revoked`, `content_removed`). RLS: moderator-only read, no
  direct write policy.
- `resolve_report(p_report_id uuid, p_status text, p_note text default
  null)` — `SECURITY DEFINER`, requires
  `is_platform_moderator(auth.uid())`, validates `p_status` is
  `reviewed` or `dismissed`, updates the report, inserts a
  `moderation_actions` row automatically, and calls
  `create_notification(reporter_id, actor_id, 'report_resolved')`
  automatically. All of this already existed; this milestone only
  needed a caller.
- `is_platform_moderator(uuid)` returns true for `moderator` or `staff`
  roles; `is_platform_staff(uuid)` is `staff` only. Both already existed
  (Milestone 22).

## 3. Stored-status ↔ UI-label mapping

The existing stored statuses (`reviewed` / `dismissed`) were kept as-is
— never renamed — per the explicit instruction to prefer the existing
contract. The two approved user-facing outcomes map onto them:

| UI label | Stored status |
|---|---|
| No violation | `dismissed` |
| Violation confirmed | `reviewed` |

`js/repositories/moderationRepository.js` exports this mapping
(`RESOLUTION_OUTCOMES`) and a reverse lookup (`describeReportStatus()`)
with a safe "Unknown status" fallback for any legacy or unrecognized
stored value, so a future status value never crashes the history view.

## 4. Double-resolution race — found in PR review, closed by migration `0036`

**Originally shipped as a known, deliberately unfixed gap; no longer
one.** The initial version of `resolve_report()` matched by report id
alone, with no status guard — two moderators resolving the same report
within moments of each other could both succeed, the second silently
overwriting the first's decision. It was initially mitigated only
client-side, with a pre-resolve status check in `resolveReport()` that
gave honest feedback for the case where a check ran *after* someone else
had already resolved the report.

That mitigation was reviewed during PR #19 review and confirmed
insufficient — it's a classic time-of-check-to-time-of-use gap. **This
was empirically demonstrated**, not just reasoned about: two real,
separately-authenticated database sessions were used to call
`resolve_report()` against the same open report in immediate sequence.
Both calls returned success. The second silently overwrote the first's
`status`/`reviewed_by`. Two `moderation_actions` rows and two
`report_resolved` notifications existed afterward for what should have
been one decision. See the PR review notes for the exact commands and
output.

**Fixed by migration `0036_resolve_report_atomic_status_guard.sql`**
(paired rollback: `0036_resolve_report_atomic_status_guard_rollback.sql`
in `supabase/rollbacks/`). `resolve_report()` is unchanged in signature,
security mode, authorization check, `moderation_actions` insert,
notification call, and return shape — only its `UPDATE` now adds `and
status = 'open'` to the `WHERE` clause and uses the `UPDATE ...
RETURNING` itself as the atomic claim, rather than a separate check
beforehand. Postgres's normal row-level locking under READ COMMITTED
makes this safe with no new isolation level or advisory lock: a second,
truly concurrent call blocks on the row, then — once the first commits —
re-evaluates `status = 'open'` against the now-updated row and correctly
matches nothing. A report that no longer matches now raises one of two
distinct messages: `'Report not found.'` (unchanged, no such id) or
`'This report has already been resolved.'` (new — exists, but wasn't
`open` at claim time), so the client can distinguish and respond to each
honestly instead of both surfacing as the same generic failure.

`js/pages/moderation/renderModerationPage.js`'s client-side freshness
check remains, but only as a fast path that skips an unnecessary RPC
round trip in the common case — it is explicitly documented in its own
comment as not the concurrency boundary. That boundary is the atomic
guard in `resolve_report()` itself. Whichever path detects the conflict
(the pre-check or the RPC's own rejection), the client responds
identically: no success toast for the outcome that was attempted, no
locally-guessed entry inserted into history, a full reload reconciling
both the Open and Resolved views against the server (so whichever
outcome the other moderator actually recorded is what's shown), and
focus moved to the Open heading rather than silently dropped.

Re-running the exact two-session demonstration above after the fix: the
second call now raises `'This report has already been resolved.'`, the
first decision is untouched, and exactly one `moderation_actions` row
and one notification exist. See
`supabase/tests/milestone_24_resolve_report_atomic_guard.test.sql` for
the full automated regression coverage.

## 5. Authorization design

Two layers, matching the pattern `renderProfile.js` and
`ManageRolesControl.js` already established:

1. **Client-side gate (UX only, never the security boundary)** —
   `js/pages/moderation/loadModerationQueue.js` calls the existing
   `getProfileRoles(userId)` (wraps `get_public_profile_roles`) and
   checks for `moderator` or `staff`. `pages/moderation.html` ships with
   `#moderationContent` and `#moderationDenied` both `hidden` in the raw
   HTML (not toggled into that state by script) and `#moderationGate`
   visible by default, so a slow network, a thrown error, or JS not
   running at all never leaves protected markup visible. A role-check
   error is treated as denied, never as authorized.
2. **Real boundary: RLS + RPC** — every read this page performs
   (`content_reports`, `moderation_actions`) is already scoped by
   `is_platform_moderator(auth.uid())` at the database level, and
   `resolve_report()` re-checks moderator status itself regardless of
   what the client believes. No service-role key is used in the
   browser anywhere in this milestone.

## 6. Queue and history behavior

- **Open view** (default): report cards, not a table — each shows
  target type, a human-readable target label (a raw UUID appears only
  as restrained diagnostic context when the target is unavailable,
  never as the primary label), a safe link to the target when it still
  resolves, reason, reporter, submission date, and the two resolution
  actions.
- **Target context** is resolved via batched lookups grouped by
  `target_type` — one query per type (`getBuildsByIds`,
  `getProfilesByIds`, a new `getCommentsByIds`), not a query per report.
  A target that RLS excludes (deleted, unpublished, made private) simply
  isn't in the batch result, which is the natural "unavailable" signal
  — no extra existence check needed.
- **Resolution** requires an explicit confirmation dialog naming the
  specific report and target and explaining what the outcome means.
  Action buttons disable immediately on click to prevent duplicate
  submissions; on a recoverable failure they re-enable. On success the
  report leaves Open (no full page reload) and appears in Resolved.
  Focus is preserved deliberately: which button/heading receives focus
  after a card leaves the DOM is captured *before* disabling the
  triggering button — disabling the focused element evicts focus to
  `<body>` immediately in the browser, before any later
  `document.activeElement` check would run, which was a real bug caught
  during test-writing (see `js/pages/moderation/renderModerationPage.js`
  and its focus-restoration comment).
- **Resolved/history view** is read-only — no reopening, editing, or
  deleting a resolved report from the UI. Newest-resolution-first,
  bounded (`limit`, not unbounded). Shows the approved outcome label,
  target context, resolution date, and resolving moderator.
- Resolving a report **never** automatically unpublishes, removes, or
  otherwise acts on the reported content, and both the page copy and
  the confirmation dialogs say this explicitly. No moderator notes,
  reporter notifications naming the moderator or the specific outcome,
  suspensions, warnings, or appeals were added — all explicitly out of
  scope for this milestone.

## 7. Navigation

A "Moderation" link appears in the signed-in account menu (desktop
dropdown and mobile flat list, matching the navbar's existing
duplication pattern) only when `getProfileRoles()` includes `moderator`
or `staff`. Never shown to signed-out visitors or ordinary users, and
never in the public Explore nav. No open-report count badge risk was
taken — the Open tab's count is fetched as part of loading the
authorized queue itself, not as a separate cheap-but-unreliable badge
query.

## 8. What this milestone did not touch

No changes to the existing report-submission flow (`ReportButton.js`,
`reportContent()`), no changes to role-management UI, no schema
changes, no new dependencies, no unrelated refactors of the comments or
community system.
