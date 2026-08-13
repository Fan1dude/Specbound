# Milestone 25 — Follow Notifications

Status: Implemented. Written after implementation as the design record —
describes what was actually built, not a proposal awaiting approval.
Local-only verification against disposable Supabase test data, including
two real accounts exercised through the live browser UI; not yet
deployed to production.

## 1. Problem

`set_follow()` (`supabase/migrations/0012_follows.sql`, Milestone 7C) has
never called `create_notification()`. That migration's own header
comment says so explicitly: "No `create_notification()` call — 'Follow
notifications' is explicitly out of scope for this milestone." A builder
could gain a follower and never know. This milestone closes that gap.

## 2. Existing contracts (confirmed by reading migrations, not assumed)

- `follows` — `follower_id`/`following_id` → `auth.users(id) on delete
  cascade`, `unique(follower_id, following_id)`, `check(follower_id <>
  following_id)`. RLS `SELECT` fully public; no direct write policy —
  all writes go through `set_follow()`. `profiles.followers_count`/
  `following_count` are trigger-maintained caches
  (`bump_follow_counts()`).
- `set_follow(p_following_id uuid, p_followed boolean) returns
  table(followed boolean, followers_count integer, following_count
  integer)` — `SECURITY DEFINER`, idempotent desired-state RPC (call it
  with `true` or `false`, not a toggle), rejects self-follow at both the
  application level and via a `CHECK` constraint, granted to
  `authenticated` only.
- `notifications` (`0011_notifications.sql`, widened by
  `0031_guidelines_and_notification_types.sql`) — `recipient_id`/
  `actor_id` → `auth.users(id) on delete cascade`, `type text` with a
  `CHECK`, `build_id` nullable since `0031` (was `not null`
  originally), `comment_id`, `read_at`, `created_at`. RLS `SELECT`
  scoped to `recipient_id = auth.uid()`.
- Confirmed live production `notifications_type_check` before writing
  any code: `type = any (array['comment','like','save','reply',
  'role_awarded','report_resolved'])` — matches source, no drift.
- `create_notification(p_recipient_id, p_actor_id, p_type, p_build_id
  default null, p_comment_id default null)` — self-notification guard
  (`if p_recipient_id = p_actor_id then return; end if;`), zero client
  grants ever, callable only from inside another `SECURITY DEFINER`
  function.
- `notificationFormat.js` is the single shared source for both the
  navbar bell dropdown (`notificationBell.js`) and the dedicated
  notifications page (`js/pages/notifications/renderNotifications.js`)
  — every notification renders as plain escaped text plus a link, no
  per-type icon system.
- `renderFollow.js`'s Follow button disables itself only as a
  client-side UX debounce; the real duplicate guarantee is the
  database's `unique(follower_id, following_id)` constraint plus `on
  conflict do nothing` in `set_follow()`.

## 3. Approved decisions

- Copy: `"{name} followed you."` — no numeric count, no digest.
- Link target: the follower's own profile
  (`pages/profile.html?user={actor_id}`), built from the trusted
  `actor_id` column, never from a joined username or any other
  user-controlled text.
- Notify only on a genuinely new follow row — never on an
  already-existing follow (idempotent re-call, duplicate button click),
  never on unfollow.
- Refollowing after an unfollow **does** notify again, since the
  `unique` constraint means it's a genuinely new row every time.
- Follows never appear in the Activity Feed — a relationship change
  alone isn't feed-worthy content, and the Feed stays focused on actual
  builder work. Notification-only.
- No follower-count digests, rankings, or dashboards — out of scope.
- Likes stay exactly as they are — no change to their notification
  behavior.

## 4. Migration `0037_follow_notifications`

Two changes, one migration:

1. `alter table public.notifications drop constraint
   notifications_type_check; alter table public.notifications add
   constraint notifications_type_check check (type in ('comment',
   'like', 'save', 'reply', 'role_awarded', 'report_resolved',
   'follow'));` — additive only, no existing row can violate a widened
   set.
2. `create or replace function public.set_follow(...)` — identical
   signature, `SECURITY DEFINER`, `search_path`, self-follow
   protection, and grants. Only the `p_followed = true` branch changes:

   ```sql
   insert into public.follows (follower_id, following_id)
   values (v_follower_id, p_following_id)
   on conflict (follower_id, following_id) do nothing
   returning id into v_inserted_id;

   if v_inserted_id is not null then
       perform public.create_notification(p_following_id, v_follower_id, 'follow');
   end if;
   ```

   This is the exact atomic `INSERT ... ON CONFLICT ... RETURNING ...
   check not null` pattern already proven in
   `0036_resolve_report_atomic_status_guard.sql` — the `RETURNING`
   clause itself is the atomic claim on "did this call actually insert
   a new row," no separate existence check, no race window. The
   `p_followed = false` (unfollow) branch is completely untouched — no
   notification path exists there at all, by construction, not by a
   conditional.

Stored notification shape: `type = 'follow'`, `recipient_id` = the
followed user, `actor_id` = the follower, `build_id = null`,
`comment_id = null` — a follow has no associated build, the same shape
`report_resolved` already uses.

## 5. Rollback — behavioral, not a schema reversal

**This is a deliberate, required design choice, not an oversight.** The
initial proposal was a full reversal (narrow the constraint back,
restore the old function). That was corrected before implementation
began: once production contains any `'follow'`-typed notification row,
narrowing `notifications_type_check` back to its pre-0037 values would
either fail outright (existing rows violate the narrower constraint) or
require deleting legitimate user notifications to make the ALTER
succeed. Neither is acceptable.

`0037_follow_notifications_rollback.sql` instead:

1. Restores `set_follow()` to its exact pre-0037 body — future follows
   stop notifying.
2. Leaves `notifications_type_check` untouched — `'follow'` stays a
   permanently valid type.
3. Never deletes, updates, or otherwise touches any existing
   `'follow'`-typed row.

An already-deployed, pre-Milestone-25 frontend encountering a `'follow'`
row it has never heard of already has a safe path: `notificationFormat.js`'s
generic `default` case, the same fallback `role_awarded` rows have
silently relied on, unremarked, since migration `0031` — direct,
current-repository evidence, not an assumption, that an unrecognized
notification type renders safely today.

## 6. Verified live, not just tested in isolation

Two disposable local accounts were signed in through the real UI (not
mocked) for the full cycle:

- **New follow → notification.** Account A followed account B. Signing
  in as B, the bell dropdown showed exactly `"m25_live_a followed
  you."`, linking to A's own profile. Clicking it navigated correctly
  and cleared the unread badge. The dedicated notifications page
  rendered the same row identically.
- **Unfollow → no notification.** A unfollowed B. Confirmed via direct
  SQL against the local database that no third `follow`-typed row was
  created.
- **Refollow → new notification.** A followed B again. Confirmed a
  third row was created with a new `created_at`, and it rendered
  correctly on both the bell dropdown and the notifications page.
- **Standalone rollback rehearsal**, separate from the SQL test suite's
  own in-transaction rehearsal: with three real `'follow'` notification
  rows already present from the steps above, the actual rollback file
  was applied directly (`psql -f
  supabase/rollbacks/0037_follow_notifications_rollback.sql`). All
  three rows survived unchanged. A fresh `set_follow(..., true)` call
  for a third disposable account created zero new notifications
  (`followers_count`/`following_count` still updated correctly — only
  the notification is suppressed) and the RPC's return shape was
  unaffected. Migration `0037` was then reapplied, and a follow-up
  `set_follow()` call confirmed notifications resumed (a fourth row was
  created). All disposable accounts, follows, and notifications were
  deleted afterward (cascade via `auth.users` deletion).

## 7. A pre-existing bug this milestone's live verification surfaced

Not introduced by this milestone, and not part of migration `0037`'s
own SQL — but only actually triggered by a real browser session once a
`build_id = null` notification existed and reached
`notificationRepository.js`'s `enrichNotifications()`:

```js
const uniqueBuildIds = [...new Set(notifications.map(n => n.build_id))];
// ...
getBuildsByIds(uniqueBuildIds)
```

`getBuildsByIds()` does an unguarded `.in("id", ids)`. A raw `null` in
that array serializes to PostgREST as the literal `id=in.(null)`, and
Postgres rejects `null` as a `uuid` (`22P02: invalid input syntax for
type uuid: "null"`), breaking the bell dropdown and the notifications
page entirely (`"Could not load notifications. Try refreshing the
page."`) for the affected user. This already affects `report_resolved`
notifications — which also always carry `build_id = null` — live in
production today, ever since Milestone 24 shipped a real caller for
`resolve_report()`. It predates Milestone 25 and was not introduced by
it; Milestone 25's live verification is simply the first thing to
actually exercise this exact path end-to-end in a real browser.

Fixed in `js/repositories/notificationRepository.js` by filtering out
falsy `build_id` values before the batch fetch:

```js
const uniqueBuildIds = [...new Set(notifications.map(n => n.build_id).filter(Boolean))];
```

## 8. Files changed

- `supabase/migrations/0037_follow_notifications.sql` (new)
- `supabase/rollbacks/0037_follow_notifications_rollback.sql` (new)
- `js/utils/notificationFormat.js` — `'follow'` case in
  `formatNotificationText()` and `getNotificationUrl()`
- `js/repositories/notificationRepository.js` — null-`build_id` fix
  (§7)
- `supabase/tests/milestone_25_follow_notifications.test.sql` (new)
- `tests/notificationFormat.test.html`,
  `tests/notificationBell.test.html`, `tests/notifications.test.html`
  — extended with follow-notification cases
- `README.md`, `docs/ROADMAP.md`, `docs/CHANGELOG.md`,
  `supabase/migrations.md` — corrected stale Milestone 24 status
  language and added Milestone 25 records
