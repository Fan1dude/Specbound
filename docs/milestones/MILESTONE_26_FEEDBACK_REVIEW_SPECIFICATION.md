# Milestone 26 — Feedback Review

Status: Implemented. Written after implementation as the design record —
describes what was actually built, not a proposal awaiting approval.
Local-only verification against disposable Supabase test data, including
four real accounts (submitter, moderator, staff, ordinary) exercised
through the live browser UI, plus a full rollback/reapply rehearsal
against real data; not yet deployed to production.

## 1. Problem

`feedback_submissions` (`supabase/migrations/0029_feedback_submissions.sql`,
Milestone 22) has carried a `status` column since it shipped, with three
allowed values (`open`/`reviewed`/`closed`), but nothing has ever written
past its `'open'` default — no RPC, no UPDATE RLS policy. Feedback has
been write-only since Milestone 22: builders could submit it, but no one
could ever see or act on it. This milestone closes that gap.

## 2. Existing contracts (confirmed by reading migrations, not assumed)

- `feedback_submissions` — `user_id` nullable, `references auth.users(id)
  on delete set null` (feedback deliberately outlives a deleted account),
  `category`/`message` `CHECK`-constrained (4 categories, 1-2000 chars),
  `page_url text` with no constraint, `status` `CHECK`-constrained to
  `('open','reviewed','closed')`. RLS: submitter reads own row
  (`auth.uid() = user_id`); moderators read all
  (`is_platform_moderator(auth.uid())`). No INSERT/UPDATE policy — all
  writes go through functions.
- `submit_feedback(p_category, p_message, p_page_url default null)` —
  `SECURITY DEFINER`, requires `auth.uid()` (feedback can never be
  anonymous), pins `user_id := auth.uid()` server-side. Unchanged by this
  milestone.
- `is_platform_moderator(uuid)` returns true for `role in ('moderator',
  'staff')` (`0027_profile_roles.sql`) — the same contract
  `content_reports`'/`resolve_report()`'s own moderator-read/-write
  policies already use, confirming feedback review is content-triage,
  not account-administration (which uses the stricter
  `is_platform_staff()`, staff-only).
- `resolve_report()`'s atomic guard (`0036_resolve_report_atomic_status_guard.sql`)
  — `update ... where id = ... and status = 'open' returning ...` as the
  concurrency boundary itself, not a separate pre-check. Directly reused
  and generalized here.
- `notifications` (`0011`, widened by `0031`/`0037`) — `recipient_id`/
  `actor_id` → `auth.users(id) on delete cascade`, `type text` `CHECK`,
  `build_id`/`comment_id` nullable, `read_at`, `created_at`. RLS `SELECT`
  scoped to `recipient_id = auth.uid()`.
- `create_notification(p_recipient_id, p_actor_id, p_type, p_build_id
  default null, p_comment_id default null)` — self-notification guard,
  zero client grants, callable only from inside another `SECURITY
  DEFINER` function.
- `js/pages/moderation/{loadModerationQueue,renderModerationPage}.js`,
  `js/components/ReportCard.js` — the Milestone 24 reviewer-page
  architecture this milestone's reviewer page reuses.

## 3. Approved decisions

- Both `moderator` and `staff` may review feedback — the existing
  `is_platform_moderator()` contract, unchanged.
- Statuses: `open` → `reviewed` → `closed`. Allowed transitions:
  `open→reviewed`, `open→closed`, `reviewed→closed`. Closed is terminal
  — no reopening, no no-op transition is ever valid.
- Notification copy, exact: `"Your feedback was reviewed."` /
  `"Your feedback was closed."` — no outcome disclosure, no reviewer
  identity. Both link to `pages/my-feedback.html`.
- A new, dedicated `pages/my-feedback.html` — self-only, read-only,
  newest-first, with a plain-language legend for what each status means.
- A separate `pages/feedback.html` reviewer page — not merged into
  Reports, since the two entities (content-safety violations vs. product
  signal) have different shapes and different resolution semantics.
- A dedicated `FeedbackCard.js` — not a `ReportCard.js` extension, since
  feedback's two-hop transition graph doesn't fit Reports' fully-passive
  History shape (a Reviewed row keeps one action, Mark Closed, even
  inside History).
- Explicitly excluded: internal reviewer notes, reviewer/submitter
  replies, outcome explanations, Planned/Completed statuses or any
  public roadmap commitment, search, duplicate linking, tags/priorities,
  assignment, reopening, deletion, anonymous feedback, email
  notifications, and any change to the existing categories, message
  limit, or submission form.

## 4. Migration `0039_feedback_status_workflow`

Four changes, one migration:

1. `feedback_submissions.status_updated_at timestamptz`, nullable, added
   with `if not exists` (required, not defensive habit — see §7). Set
   only inside the RPC's atomic UPDATE, only on success.
2. `notifications_type_check` widened to add `'feedback_reviewed'` and
   `'feedback_closed'` — two distinct frozen event types, not one type
   read from a live join to the feedback row's current status. A live
   join would make an old notification's rendered text silently change
   if the same submission were later actioned again (e.g. a "reviewed"
   notification would start reading "closed" once the row is later
   closed) — every other event type in this table is already a frozen
   descriptor of what happened, not a live pointer, and this follows
   that convention.
3. `notifications.actor_id` changed from `not null` to nullable — see
   §5 for the full reasoning. A pure loosening: every existing call site
   (`create_comment`, `set_build_like`, `set_build_saved`,
   `resolve_report`, `set_follow`) always passes a real actor and is
   completely unaffected.
4. `update_feedback_status(p_feedback_id uuid, p_expected_status text,
   p_new_status text) returns public.feedback_submissions`:

   ```sql
   if not public.is_platform_moderator(auth.uid()) then
       raise exception 'Only moderators or staff can update feedback status.';
   end if;

   if (p_expected_status, p_new_status) not in (
       ('open', 'reviewed'), ('open', 'closed'), ('reviewed', 'closed')
   ) then
       raise exception 'Invalid status transition.';
   end if;

   update public.feedback_submissions
       set status = p_new_status, status_updated_at = now()
       where id = p_feedback_id and status = p_expected_status
       returning * into v_row;

   if v_row is null then
       -- distinguishes not-found from stale/already-updated
   end if;

   if v_row.user_id is not null then
       perform public.create_notification(v_row.user_id, null, v_notification_type);
   end if;
   ```

   The transition allow-list is what makes every no-op and every
   backward transition impossible in one place. The atomic claim
   generalizes `resolve_report()`'s guard with an explicit
   expected-status parameter, since feedback's graph has two valid
   source statuses (`open`, `reviewed`) where a report's has one
   (`open`).

No UPDATE RLS policy is added — the table keeps its existing
"zero direct-write policies, every write goes through a function"
posture, matching `submit_feedback()`'s own insert-only precedent.

Grants: `revoke all on function ... from public, anon; grant execute ...
to authenticated;` — matching the hardened posture `0033`/`0038`
established for every other RPC in this schema.

## 5. Reviewer-identity privacy — a required correction before implementation

The original plan reused `report_resolved`'s pattern: a real `actor_id`
on the notification row, with `notificationFormat.js`'s fixed, generic
text keeping the reviewer's name out of the *rendered UI*. Before
writing any code, the full notification data path was inspected end to
end, as required:

- `notifications.actor_id`/FK: `not null references auth.users(id) on
  delete cascade` (`0011`). Making it nullable requires only `alter
  column ... drop not null` — a null FK value never needs to satisfy the
  FK constraint (Postgres only checks non-null values), no FK
  redefinition needed.
- `create_notification()`: its self-notification guard
  (`if p_recipient_id = p_actor_id then return;`) evaluates to `NULL`
  (not `TRUE`) when `p_actor_id` is null, so it correctly no-ops for an
  actorless call rather than misbehaving.
- Notification RLS: unaffected — `SELECT` stays scoped to
  `recipient_id = auth.uid()`. This was never the leak; the row's own
  content was.
- `notificationRepository.js`: `getRecentNotifications()`/
  `getNotificationsPage()` both do `.select("*")` — the raw REST
  response already contains `actor_id` verbatim, inspectable by the
  recipient via browser devtools/network tab regardless of what the UI
  renders. Confirmed live in this session, not assumed: the raw payload
  for a `report_resolved` notification already exposes the resolving
  moderator's UUID to the reporter today, in production, and always has.
- `enrichNotifications()` additionally does a *separate* batched
  `getProfilesByIds(uniqueActorIds)` call — for `feedback_reviewed`/
  `feedback_closed`, this would fetch and attach the reviewing
  moderator's public profile to the notification object, a second,
  independent exposure vector beyond the raw `actor_id` column itself.
- Bell/notifications-page renderers: neither ever dereferences
  `notification.actor` for `report_resolved` today (hardcoded generic
  text), so no rendering-layer change was needed there beyond adding two
  new `case` branches — but this only ever protected the *rendered*
  text, never the underlying data.

**Conclusion**: `report_resolved`'s pattern is not actually private at
the network-payload level, only at the rendered-text level. Feedback's
requirement is stricter — the reviewer's identity must be absent from
every client-visible channel. The only way to guarantee that is for the
row itself to carry no reviewer identity at all.

**Implemented**: `actor_id` made nullable (migration, §4.3);
`update_feedback_status()` passes `null` explicitly, never `auth.uid()`;
`enrichNotifications()` now filters falsy `actor_id` values before
batching the profile lookup (`.filter(Boolean)`, the same guard already
applied to `build_id` since the Milestone 25 follow-up fix), so an
actorless row never reaches `getProfilesByIds()`'s `.in("id", ids)` as a
literal `null` and never triggers Postgres's `22P02` rejection.

Verified directly against the raw network response in a live local
session, not assumed:

```json
{"id":"...","recipient_id":"8b15ed0c-...","actor_id":null,
 "type":"feedback_closed","build_id":null,"comment_id":null, ...}
```

## 6. Reviewer page (`pages/feedback.html`) and My Feedback (`pages/my-feedback.html`)

Reviewer page reuses Milestone 24's gate/controller architecture exactly
(`loadFeedbackQueue.js` fails closed on every path — raw HTML ships with
`#feedbackContent`/`#feedbackDenied` hidden, `#feedbackGate` visible,
flipped only once the real role check resolves; `renderFeedbackPage.js`
is a self-contained fetch-owns-state controller). Departures from
Reports, each a considered decision:

- **`FeedbackCard.js` is dedicated, not a `ReportCard.js` extension** —
  a card's available actions depend on its status in a way Reports never
  needed: Open shows both Mark Reviewed/Mark Closed; a Reviewed card
  *inside History* still shows Mark Closed (the only way
  `reviewed→closed` can ever be initiated, since it never appears in the
  Open tab); Closed shows nothing.
- **Category filter** on both tabs; a **History-only status filter**
  (All/Reviewed/Closed) — cheap, client-side over an already-bounded
  fetch (`getOpenFeedback()`/`getHistoryFeedback()`, `limit(100)`,
  matching `moderationRepository.js`'s own bounded-not-paginated
  posture).
- **History sorts by `status_updated_at` desc** (nulls last), with
  `created_at desc, id desc` as deterministic tiebreakers — "most
  recently actioned," not "oldest submission," matching what a review
  queue's history should mean.
- **`page_url` is always plain escaped text, never a link** —
  `feedback_submissions.page_url` has no `CHECK` constraint and
  `submit_feedback()` performs no server-side validation on it, so a
  direct RPC call (bypassing the modal) could set it to anything,
  including a `javascript:` URI. `escapeHtml`/`escapeAttribute` (this
  codebase's only escaping utilities) neutralize markup but not URL
  schemes, so the only safe design is to never let the value become an
  `href` at all — the same rule `ReportCard.js`'s `renderTargetMarkup()`
  already applies to every free-text/user-controlled value.
- **Confirmation dialogs** — Reviewed states plainly that it means
  acknowledged, not action-taken; Closed's confirm body includes, word
  for word: *"Closed is permanent — this submission cannot be
  reopened."* Verified live via the actual `<dialog>` element's text
  content, not assumed from source.
- **Stale-conflict handling** mirrors `renderModerationPage.js`'s
  pattern exactly: a client-side freshness `SELECT` as a fast path only
  (never the concurrency boundary), the RPC's own atomic guard as the
  real backstop, and identical honest reconciliation on either path (no
  false success, a full reload, focus moved to the page heading rather
  than stranded).

My Feedback (`pages/my-feedback.html`) is fully read-only: no role
gate (`requireAuth()` only — RLS is the real and only scope boundary,
`getMyFeedback()` passes no client-supplied user id anywhere in its
query), no actions, a static legend explaining Open/Reviewed/Closed,
newest-first.

Nav (`js/core/layout.js`): an unconditional "My Feedback" entry for
every signed-in user (both desktop dropdown and mobile list, alongside
Settings), and a moderator-gated "Feedback" entry reusing the exact same
`isModerator` check the existing "Moderation" link already computes (no
second role-check RPC call).

## 7. Rollback — the narrowest in this chain so far, and what its own rehearsal caught

**Deliberately narrow, matching the reasoning already established for
`0037`'s behavioral rollback, extended to cover a populated column and a
loosened constraint in addition to a widened CHECK.**
`0039_feedback_status_workflow_rollback.sql` drops *only* the function.
It does not drop `status_updated_at` (a populated column would be
destroyed with no way to recover it by reapplying forward), does not
narrow `notifications_type_check` back (would fail outright or destroy
real notifications once either new type has been used), and does not
restore `actor_id`'s `not null` (would fail outright once any actorless
row exists, and protects nothing once nothing can insert one anyway).

**Rehearsed for real, not simulated**, against the local database:
seeded a real submission via the real `submit_feedback()`/
`update_feedback_status()` RPCs (not a direct INSERT), applied the
literal rollback file, confirmed via direct SQL that the row's status,
`status_updated_at`, and the actorless notification survived byte-for-
byte identical and that `update_feedback_status()` was genuinely gone
(`42883: undefined function`), reapplied migration `0039` forward, and
confirmed a real `reviewed→closed` call succeeded normally afterward.

This rehearsal caught a real bug before it could reach the SQL test
suite or production: the forward migration's `alter table ... add
column status_updated_at` was not idempotent, and failed outright
(`column ... already exists`) when reapplied on top of its own
rollback's left-behind schema. Fixed to `add column if not exists`,
with the requirement noted directly in the migration's own comment.
`alter column actor_id drop not null` needed no such fix — confirmed via
the same rehearsal that dropping an already-dropped `NOT NULL`
constraint is a safe no-op in Postgres.

Compatibility, confirmed rather than assumed:

- **Old frontend + migrated DB**: never calls the new RPC, never renders
  `feedback_reviewed`/`feedback_closed` by name. If either type reached
  an old-frontend session regardless, `formatNotificationText()`'s
  existing `default:` case and `getNotificationUrl()`'s existing
  build-slug fallback both handle it safely — the same fallback already
  proven live for `role_awarded` and `follow`.
- **New frontend + pre-migration DB**: `update_feedback_status` calls
  fail cleanly (function does not exist), surfaced as a generic error
  toast; reads (reviewer queue, My Feedback) rely only on the unchanged
  `0029` RLS and work identically either way.
- **Rolled-back frontend/DB with existing notification rows**: historical
  `feedback_reviewed`/`feedback_closed` rows remain forever readable and
  render their correct, specific text forever — the JS that knows how to
  format them isn't un-shipped by a database rollback.

## 8. Verified live, not just tested in isolation

Four disposable local accounts (submitter, moderator, staff, ordinary)
were signed in through the real UI for the full cycle:

- **Real submission through the real modal.** The submitter opened the
  actual footer Feedback button (not a mocked call), filled and sent it.
  Confirmed via direct SQL: a real `feedback_submissions` row, correct
  category/message/`page_url` (the real `window.location.href` at
  submission time), `status='open'`.
- **Reviewer sees and acts on it.** Signed in as moderator, navigated to
  the real `pages/feedback.html`. The gate resolved correctly
  (`#feedbackContent` visible, `#feedbackDenied`/`#feedbackGate`
  hidden), the submission rendered with the correct category badge,
  submitter username linking to their real profile, `page_url` rendered
  as a `<span>` (confirmed via `instanceof HTMLAnchorElement === false`
  — never a link), both actions present. Clicked Mark Reviewed, the
  real confirm dialog appeared, confirmed — the card moved from Open
  (now showing its empty state) to History as Reviewed, with a
  `"Feedback marked \"Reviewed\"."` success toast.
- **Reviewed → Closed from within History.** Same session, switched to
  the History tab, clicked the card's one remaining action. The confirm
  dialog's text content was read directly from the DOM and confirmed to
  contain, verbatim, *"Closed is permanent — this submission cannot be
  reopened."* Confirmed — the card updated in place, still in History,
  now with zero actions.
- **Submitter sees both notifications and My Feedback.** Signed back in
  as the submitter. The Notifications page rendered exactly `"Your
  feedback was reviewed."` and `"Your feedback was closed."`, both
  `just now`, no reviewer name anywhere. The raw REST response for the
  notifications fetch was inspected directly (`read_network_requests`)
  and confirmed `"actor_id":null` on both rows — the privacy guarantee
  holds at the network-payload level, not merely the rendered-text
  level. `pages/my-feedback.html` rendered the submission with status
  Closed, the correct legend text, submission and status-updated dates.
- **Staff access.** Signed in as the staff account, confirmed
  `pages/feedback.html` resolves to content-visible (not denied) —
  `is_platform_moderator()` correctly covers `staff`, not just
  `moderator`.
- **Ordinary-user access fails closed.** Signed in as a plain
  authenticated account (no role), confirmed the page resolves to
  denied (content hidden). A direct `supabase.rpc('update_feedback_status',
  ...)` call from that session was additionally attempted and rejected
  server-side with `"Only moderators or staff can update feedback
  status."` — confirming the client gate is UX only and the real
  boundary holds even when bypassed entirely.
- All four disposable accounts, their feedback rows, and their
  notifications were deleted afterward; confirmed zero remaining rows
  matching the live-verification fixtures.

An unrelated environment issue was found and worked around during this
verification, not caused by this milestone: the Browser pane's
preview-server tooling was resolving `.claude/launch.json`'s static
server against a different (non-worktree) directory, silently serving a
stale `js/core/config.js` pointed at the *production* Supabase project.
No writes were made against it before this was caught (only a rejected
sign-in attempt and read-only fetches). Worked around by running a
purpose-built static file server from this worktree directly. Not a
defect in this milestone's code; flagged here so it isn't mistaken for
one, and as a heads-up for whoever next relies on that preview
mechanism from a worktree.

## 9. Files changed

- `supabase/migrations/0039_feedback_status_workflow.sql` (new)
- `supabase/rollbacks/0039_feedback_status_workflow_rollback.sql` (new)
- `js/repositories/feedbackRepository.js` (new)
- `js/components/FeedbackCard.js` (new)
- `js/pages/feedback/{app.js,loadFeedbackQueue.js,renderFeedbackPage.js}` (new)
- `js/pages/myFeedback/{app.js,loadMyFeedback.js,renderMyFeedback.js}` (new)
- `pages/feedback.html`, `pages/my-feedback.html` (new)
- `css/pages/feedback/{feedback.css,my-feedback.css}` (new)
- `js/utils/notificationFormat.js` — `feedback_reviewed`/
  `feedback_closed` cases
- `js/repositories/notificationRepository.js` — null-`actor_id` filter
  in `enrichNotifications()` (§5)
- `js/core/layout.js` — "My Feedback" (unconditional) and "Feedback"
  (moderator-gated) nav entries
- `supabase/tests/milestone_26_feedback_status_workflow.test.sql` (new,
  23 scenarios)
- `tests/feedbackQueue.test.html`, `tests/myFeedback.test.html`,
  `tests/feedbackNavLinks.test.html` (new)
- `tests/notificationFormat.test.html`, `tests/mobileAccountMenu.test.html`
  — extended/corrected for the new notification types and the new
  unconditional nav link
- `README.md`, `docs/ROADMAP.md`, `docs/CHANGELOG.md`,
  `supabase/migrations.md` — corrected stale Milestone 25/PR #21
  production-status language and added Milestone 26 records
