# Auth & Profile Architecture

**Status: current and accurate as of Phase 9E Track A live verification, 2026-07-27 — supersedes the 2026-07-26 version of this document, which drew an incorrect conclusion in §2/§4 (see the correction below).**

**Correction notice**: the original version of this document concluded "no database trigger on `auth.users`" exists, based on reading every tracked migration file. That conclusion was **wrong** — it correctly described what's in the *tracked migrations*, but incorrectly generalized that to the live database. A live INSERT-policy check (`SELECT * FROM pg_policies WHERE tablename = 'profiles' AND cmd = 'INSERT'`) returned **zero rows** — no INSERT policy exists at all, for anyone. Direct empirical testing (below) then proved a live database-level mechanism still creates profile rows reliably, even when zero client-side code ever runs. That mechanism predates migration tracking, exactly like the `profiles` table itself and its SELECT/UPDATE policies — it was never missing, it was simply never visible to a search that only covered tracked migration files. §2-§4 below are rewritten to reflect what was actually proven live, not what could be inferred from the repo alone.

This document covers Specbound's auth/identity layer: how a Supabase Auth user gets a corresponding `public.profiles` row, and the RLS model that governs it. It's the companion to `docs/STORAGE_ARCHITECTURE.md` (which covers Storage/media) — split out separately because profile creation is a database/auth concern, not a Storage one, even though avatar upload touches both.

---

## 1. `profiles` table — origin and RLS

`public.profiles` **predates migration tracking** — no tracked migration (`0001`-`0018`) contains its `CREATE TABLE`. It was already live when this project's `supabase/migrations/` convention started, alongside its RLS enablement and policies. This is a real gap in the audit trail (the table's *initial* schema and policy definitions exist only in the live database, not as a reviewable file in this repo), but the live policies themselves have now been directly verified:

| Operation | Policy | Verified |
|---|---|---|
| SELECT | Public — any visitor, authenticated or not, can read any profile row | Confirmed intentional: builder profiles (username, bio, avatar, build history) are meant to be publicly viewable, same as every other public-facing part of the app |
| UPDATE | Owner-scoped — a user can only update the row where `id = auth.uid()` | Confirmed correctly scoped |
| INSERT | **None exists.** Confirmed live, 2026-07-27: `SELECT * FROM pg_policies WHERE tablename = 'profiles' AND cmd = 'INSERT'` returns zero rows. | Confirmed intentional/correct, not a gap — see §2-§3 |
| DELETE | *(no client code ever deletes a profile row; not in scope of this audit)* | — |

Later migrations (`0003_profile_avatar_path.sql`, `0012_follows.sql`) add columns to `profiles` (`avatar_path`, `followers_count`, `following_count`) without ever touching its RLS — consistent with the table's policies being a stable, pre-existing baseline that additive migrations built on top of rather than modified.

## 2. Where a `profiles` row actually comes from

**A database-level mechanism — almost certainly a trigger on `auth.users`, running a `SECURITY DEFINER` (or otherwise RLS-bypassing) function — creates the `profiles` row automatically at signup, before any client-side code ever runs.** This is not visible in any of the 18 tracked migrations (same gap as the table itself and its SELECT/UPDATE policies — it predates migration tracking), but it was proven live, conclusively, on 2026-07-27:

**The proof.** Earlier the same day, a test signup (`sectest1785120843704@gmail.com`) was created via `supabase.auth.signUp()`. Email confirmation was pending, so `data.session` was `null` — and per `js/pages/signup/app.js`'s own logic, `ensureProfile()` is only called `if (data.session)` is truthy. It wasn't. **No client-side code ever ran for this user; no browser session for it was ever established.** Querying `profiles` for that exact user id anyway (profiles' SELECT policy is public, so this required no auth) returned a real row: `{ id: "35d9e517-...", username: "sectest1785120843704", created_at: "2026-07-27T02:54:04Z" }` — matching exactly the username passed as `options.data.username` at signup. The only thing that could have written this row is server-side logic reacting to the `auth.users` insert itself.

**This also explains why a live INSERT-policy check finds nothing** (§1): a trigger-driven `INSERT` runs as whatever role owns/executes the trigger function, not as the signing-up user — it never goes through PostgREST, never carries the user's JWT, and is therefore never subject to `profiles`' row-level security at all. RLS policies only gate access from roles that RLS applies to (`anon`, `authenticated`); a `SECURITY DEFINER` function (or a trigger function owned by a bypassing role) is a different, legitimate way to write a row that has nothing to do with whether a policy exists for ordinary clients.

**Confirming client-side `INSERT` is completely blocked, for anyone, for any row.** A second test — authenticated as a real account, attempting `supabase.from("profiles").insert([{ id: "<an arbitrary made-up UUID>", username: "..." }])` — was denied outright: `"new row violates row-level security policy for table \"profiles\""` (Postgres error `42501`). This is the standard, correct behavior of RLS when a table has RLS enabled and **zero** policies exist for a given command: every operation of that kind is denied by default, for every role RLS applies to, regardless of whose id is being inserted. This confirms the INSERT policy isn't merely unscoped or forgotten — there is categorically no way for a normal authenticated (or anonymous) client to insert a `profiles` row via direct table access, own id or otherwise.

### `ensureProfile()` — no longer the real creation path, but not removed

`js/repositories/profileRepository.js:78-98`'s `ensureProfile({ id, username })` is still called at both signup and login (unchanged from the original description below), but its own `.insert(...)` branch **can never succeed** given the finding above — RLS denies it unconditionally, for any id, including the caller's own:

```js
export async function ensureProfile({ id, username }) {
    const { data: existing } = await supabase.from("profiles").select("id").eq("id", id).maybeSingle();
    if (existing) return existing;

    const { data, error } = await supabase.from("profiles").insert([{ id, username }]).select().single();
    if (error) throw error;
    return data;
}
```

In every observed case, the trigger has already created the row by the time this function's `SELECT` runs, so the function returns on the `if (existing) return existing;` line and the `.insert(...)` call beneath it never executes. The function's own original code comment — *"since we don't know whether a DB trigger already created the row before email confirmation completes"* — shows the original author already suspected a trigger might exist; this just confirms it.

**A genuine, narrow latent gap this reveals**: if the trigger mechanism were ever to fail to fire for some edge case (a future Auth provider change, a manual `auth.users` row inserted outside the normal signup flow, etc.), `ensureProfile()`'s `.insert(...)` fallback would **not** actually be able to recover — it would hit the same unconditional RLS denial as the test above, throw, and get caught by the calling page's try/catch (which shows a toast on signup, or just `console.error`s on login) without ever creating the row. The code is *structured* like a working fallback but functionally cannot act as one under the current RLS configuration. Not a defect to fix in the RLS itself (§3 explains why the current lockdown is actually correct) — just worth knowing this isn't the safety net it visually appears to be, should the trigger's reliability ever come into question.

Both call sites remain otherwise as previously documented:

| Call site | When | Why |
|---|---|---|
| `js/pages/signup/app.js:63` | Immediately after `supabase.auth.signUp()`, **only if `data.session` is truthy** | If email confirmation is required, no session exists yet — deferred to first login |
| `js/pages/login/app.js:38` | Immediately after every successful `supabase.auth.signInWithPassword()`, unconditionally | Defensive/idempotent — now understood to almost always be a same-row no-op, since the trigger has already done the real work |

## 3. Security assessment — corrected, and more favorable than originally assessed

The original version of this document treated the INSERT path as a **client-controlled write** whose safety depended entirely on policy scoping — and flagged a real hypothetical risk if that policy turned out broad/unscoped (an impersonation-shaped gap, structurally the same failure class Migration A found and fixed for Storage). That framing was wrong, because the premise was wrong: **there is no client-controlled INSERT path at all.**

The actual model is strictly better than even a correctly-scoped `with check (auth.uid() = id)` policy would have been:

- A correctly-scoped policy still means *some* client request-shaped path exists to create a row — it's gated by comparing `auth.uid()` to the submitted `id`, which is safe, but it's still logic evaluated per-request against attacker-reachable input.
- **No policy at all** (this project's actual state) means there is no client-reachable path whatsoever — not "restricted to the caller's own id," but categorically absent for every role RLS governs. The only way a row gets created is the trigger, which reacts to `auth.users` itself (owned/managed by Supabase Auth, not directly writable by ordinary client code) rather than to anything a page's JavaScript submits.
- This eliminates the entire risk class the original §3 worried about (pre-creating/squatting an arbitrary `id`) — there's no INSERT surface to exploit in the first place.

**What this does *not* cover** (unchanged from before): UPDATE remains client-reachable and was already confirmed correctly owner-scoped (§1); SELECT is intentionally public (§1). Nothing about this finding changes either of those.

## 4. Summary

| Question | Answer |
|---|---|
| SECURITY DEFINER RPC / trigger? | **A database-level mechanism exists — proven live, almost certainly a trigger on `auth.users`** (classic Supabase pattern: `AFTER INSERT` trigger calling a `SECURITY DEFINER` function that reads `NEW.raw_user_meta_data->>'username'`). Not visible in any tracked migration; predates migration tracking. |
| Client-side INSERT policy? | **None exists** — confirmed via live `pg_policies` query (zero rows) and confirmed behaviorally (an authenticated client's direct `insert()` attempt is unconditionally denied, `42501`, for any id). |
| Privileged server logic? | No conventional server — this remains a static site + Supabase only. The "privileged" part is the trigger/function itself, which runs inside Postgres, not a separate server component. |
| Actual path | `auth.users` insert (via Supabase Auth's own signup handling) fires a database trigger that creates the matching `profiles` row, entirely server-side, before any client code runs. `ensureProfile()`'s own `.insert()` branch is unreachable in practice — the row already exists by the time it's checked. |
| Is it safe? | **Yes — more so than originally assessed.** No client-reachable INSERT path exists at all, eliminating the impersonation-shaped risk the original assessment worried about. The one real, narrow finding: `ensureProfile()`'s insert-fallback branch cannot actually function as a fallback if the trigger ever fails to fire, since it would hit the same unconditional RLS denial (§2). |
| Missing migration? | **Yes, but a documentation/tracking gap, not a security fix.** The trigger/function is real, live, and correctly locked down — but exists nowhere in this project's migration history, the same "untracked but correct" pattern the original `profiles` table and its SELECT/UPDATE policies already had. Proposed: a baseline migration that captures the live trigger/function definition verbatim (not a behavior change) — see `docs/MILESTONE_9_PHASE_9E_ARCHITECTURE.md` for the proposal, pending the exact live definition (requested from the user) to transcribe accurately rather than guess. |
