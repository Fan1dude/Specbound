# Auth & Profile Architecture

**Status: current and accurate as of the S2 live-verification round, 2026-07-26.**

This document covers Specbound's auth/identity layer: how a Supabase Auth user gets a corresponding `public.profiles` row, and the RLS model that governs it. It's the companion to `docs/STORAGE_ARCHITECTURE.md` (which covers Storage/media) — split out separately because profile creation is a database/auth concern, not a Storage one, even though avatar upload touches both.

---

## 1. `profiles` table — origin and RLS

`public.profiles` **predates migration tracking** — no tracked migration (`0001`-`0018`) contains its `CREATE TABLE`. It was already live when this project's `supabase/migrations/` convention started, alongside its RLS enablement and policies. This is a real gap in the audit trail (the table's *initial* schema and policy definitions exist only in the live database, not as a reviewable file in this repo), but the live policies themselves have now been directly verified:

| Operation | Policy | Verified |
|---|---|---|
| SELECT | Public — any visitor, authenticated or not, can read any profile row | Confirmed intentional: builder profiles (username, bio, avatar, build history) are meant to be publicly viewable, same as every other public-facing part of the app |
| UPDATE | Owner-scoped — a user can only update the row where `id = auth.uid()` | Confirmed correctly scoped |
| INSERT | *(see §3 below — not separately re-verified this round, addressed by code-level audit instead)* | — |
| DELETE | *(no client code ever deletes a profile row; not in scope of this audit)* | — |

Later migrations (`0003_profile_avatar_path.sql`, `0012_follows.sql`) add columns to `profiles` (`avatar_path`, `followers_count`, `following_count`) without ever touching its RLS — consistent with the table's policies being a stable, pre-existing baseline that additive migrations built on top of rather than modified.

## 2. Where a `profiles` row comes from

**There is no `SECURITY DEFINER` RPC for profile creation, and no database trigger on `auth.users`.** This was confirmed by reading every `create function`/`create trigger` statement across all 18 tracked migrations (`0001`-`0018`) — the only trigger in the entire schema is `set_updated_at()` (a generic `updated_at` timestamp bumper, unrelated to profile creation), and none of the 20 custom functions across the schema (`publish_draft`, `create_comment`, `set_build_like`, `set_follow`, etc.) touch `profiles` at all.

Profile row creation is a **direct client-side INSERT**, gated purely by the table's RLS INSERT policy, through one function: `ensureProfile({ id, username })` in `js/repositories/profileRepository.js:78-98`.

```js
export async function ensureProfile({ id, username }) {
    const { data: existing } = await supabase.from("profiles").select("id").eq("id", id).maybeSingle();
    if (existing) return existing;

    const { data, error } = await supabase.from("profiles").insert([{ id, username }]).select().single();
    if (error) throw error;
    return data;
}
```

- **Lookup-then-insert, not upsert** — deliberate. A blind `upsert` would silently overwrite a username the user later changed in Settings, every single time `ensureProfile` runs again (which happens on every login, see below).
- The `id` passed is always `data.user.id` from the just-completed `supabase.auth.signUp()`/`signInWithPassword()` call — never user-suppliable independent of a real Supabase Auth session.

### Two call sites, covering signup's email-confirmation gap

| Call site | When | Why |
|---|---|---|
| `js/pages/signup/app.js:63` | Immediately after `supabase.auth.signUp()`, **only if `data.session` is truthy** | If email confirmation is required, no session exists yet — any insert attempt would fail RLS regardless, so it's skipped and deferred to first login (comment in the file explains this explicitly) |
| `js/pages/login/app.js:38` | Immediately after every successful `supabase.auth.signInWithPassword()`, unconditionally | Defensive/idempotent — covers the case where signup couldn't create the row (email confirmation was pending). Safe to run on every login because of the lookup-before-insert behavior above: it only ever inserts once, first time, and is a no-op every login after that |

Both call sites wrap `ensureProfile()` in a try/catch that shows a toast (signup) or just logs (login) on failure — a failed profile creation never blocks the auth flow itself (the user still ends up signed in either way), which is why the defensive login-time retry exists at all.

## 3. Security assessment of this path

This is a **client-controlled INSERT into an identity-bearing table**, so its safety rests entirely on the INSERT policy's scoping — the same class of risk the original S2 finding raised, just for the write direction that finding's live check didn't explicitly cover (the confirmed check was SELECT + UPDATE; see §1).

**What's structurally safe regardless of the exact policy wording:**
- `id` is always the caller's own `auth.uid()` in practice (sourced directly from the just-authenticated session's `data.user.id`), never an arbitrary value a page passes in from elsewhere.
- The lookup-before-insert means a legitimate user can never accidentally clobber an existing row via this path.

**What still depends on the live INSERT policy being scoped to `auth.uid() = id` (not yet independently re-verified this round, unlike SELECT/UPDATE above):**
- If the INSERT policy is missing entirely, signup/login would currently be failing to create profile rows — empirically not the case (profiles demonstrably exist for every tested account throughout this project), so *some* INSERT policy is live and functioning.
- If that policy is scoped correctly (`with check (auth.uid() = id)`), this path is fully safe: a malicious client could call `supabase.from("profiles").insert(...)` directly (bypassing the app's own `ensureProfile` wrapper entirely, since RLS — not app code — is the real enforcement boundary) but could never successfully insert a row for any `id` other than their own authenticated user id.
- If it is instead a broad/unscoped policy (the same failure shape Migration A found and fixed for Storage — a template-style "authenticated users can insert" policy with no `id`-matching `with check`), a malicious authenticated client could pre-create a `profiles` row for an arbitrary `id` (e.g., a real user who hasn't signed up yet, or squatting a specific `id`/username combination) before the legitimate signup/login-time `ensureProfile()` call ever runs — which would then silently no-op (row already exists) and leave the attacker's row in place permanently, since nothing here ever overwrites an existing row.

**Recommendation:** run `SELECT * FROM pg_policies WHERE tablename = 'profiles' AND cmd = 'INSERT'` and confirm the `with_check` clause is scoped to `auth.uid() = id` (or equivalent). This is a quick, narrowly-scoped follow-up to the S2 verification already done — not raised as a blocker to Phase 9C, since nothing in Phase 9C touches this path, but worth closing out before public launch given the impersonation-shaped risk if it turns out to be unscoped.

## 4. Summary

| Question | Answer |
|---|---|
| SECURITY DEFINER RPC? | No — no function in any of the 18 tracked migrations touches `profiles` |
| Database trigger on `auth.users`? | No — the schema's only trigger is the generic `set_updated_at()` timestamp bumper, unrelated |
| Privileged server logic? | No — there is no server component in this architecture at all (static site + Supabase only) |
| Actual path | Direct client-side `INSERT` via `ensureProfile()`, called at signup (if a session exists immediately) and defensively at every login (covers the email-confirmation-delay case), enforced entirely by the table's RLS INSERT policy |
| Is it safe? | Structurally sound in every way that doesn't depend on the live policy text (id always sourced from the real session, insert-only/never-overwrite). The one open item is confirming the INSERT policy's `with_check` is `auth.uid() = id`-scoped — recommended as a quick follow-up, not yet independently re-verified this round. |
