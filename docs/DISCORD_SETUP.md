# Discord Account Linking — Production Setup Guide

This document has two purposes: (1) an accurate, code-verified description of how Discord account linking actually works in this repository, and (2) the external (Supabase dashboard, Discord Developer Portal) configuration required for it to work in production. Section 1 is verifiable by reading the code cited. Sections 2–3 are **not** verifiable from this repository — they describe dashboard state this environment has no access to and did not change.

Companion to `docs/AUTH_ARCHITECTURE.md` (general auth/profile model) and `docs/DEPLOYMENT.md` §4 (Supabase Site URL / Redirect URLs, which this feature also depends on).

---

## 1. Repository-verified behavior

**No custom OAuth code exists anywhere in this app.** Discord linking is entirely Supabase Auth's native identity-linking API (`supabase.auth.linkIdentity()` / `unlinkIdentity()` / `getUserIdentities()`). The application never receives, handles, or stores a Discord OAuth access token — tokens live only in Supabase's own `auth.identities`/`auth.sessions` tables, never in a table this app controls. See the header comment in `supabase/migrations/0026_social_connections.sql` for the design rationale (this app has no server/edge-function layer to safely hold a client secret).

| Behavior | Verified at |
|---|---|
| `linkIdentity()` call, provider name, and `redirectTo` | `js/repositories/discordRepository.js:40-48` — `linkDiscord(redirectTo)` calls `supabase.auth.linkIdentity({ provider: "discord", options: { redirectTo } })`. Provider string is the literal `"discord"`. |
| Where `redirectTo` comes from | `js/pages/settings/app.js:451` — `await linkDiscord(window.location.href)`. This is the **one and only** call site in the repo; `redirectTo` is always the live Settings page URL at the moment "Connect Discord" is clicked, not a hardcoded path. |
| `unlinkIdentity()` call | `js/repositories/discordRepository.js:77-94` — `disconnectDiscord()` calls `supabase.auth.getUserIdentities()`, finds the `discord` identity, calls `supabase.auth.unlinkIdentity(discordIdentity)`, then deletes the mirror row from `public.social_connections`. |
| Callback success detection | Not a separate "success" branch — `js/pages/settings/app.js` calls `reconcileDiscordConnection(user.id)` (via `createDiscordConnectionTracker`) unconditionally on every Settings page load, and separately reads any OAuth error via `readDiscordOAuthRedirectError()` (`js/utils/discordAuthErrors.js:48-73`), which parses `error`/`error_code`/`error_description` from both the query string and the `#hash` fragment. If no error param is present and a linked identity now exists with no mirror row, `reconcileDiscordConnection` calls `sync_discord_identity()` — that row's existence *is* the success signal, there is no separate "you succeeded" redirect param to check. |
| Callback failure detection | Same `readDiscordOAuthRedirectError()` / `describeDiscordRedirectError()` pair (`js/utils/discordAuthErrors.js:80-97`). Three outcomes: `error=access_denied` → user cancelled; `error_code=identity_already_exists` → the Discord identity is already linked (to this account or another one — `js/pages/settings/app.js:435-441` distinguishes the two using the reconcile result, not a Supabase field); anything else → generic callback failure, showing Supabase's own `error_description` verbatim. A **separate**, synchronous failure class exists for configuration problems that GoTrue rejects *before* ever redirecting to Discord (`describeDiscordLinkError`, `js/utils/discordAuthErrors.js:21-39`): `manual_linking_disabled` and `provider_disabled`/"provider is not enabled". |
| Identity synchronization | `public.sync_discord_identity()` (`supabase/migrations/0026_social_connections.sql:104-146`), a `SECURITY DEFINER` RPC. Reads `auth.identities` (not directly exposed to PostgREST) scoped to `auth.uid()` only, and upserts `provider_user_id` (`identity_data->>'provider_id'`), `provider_username` (`coalesce(global_name, user_name, full_name)`), and `provider_avatar_url` into `public.social_connections`, keyed on the `(user_id, provider)` unique constraint. Called by `reconcileDiscordConnection()` (`js/repositories/discordRepository.js:104-123`) on every Settings load — self-healing, not just immediately post-redirect. |
| Public visibility storage/update | `social_connections.is_public boolean not null default false` (migration `0026`, line 66). Updated via `setDiscordVisibility(userId, isPublic)` (`js/repositories/discordRepository.js:63-75`), a plain owner-scoped `UPDATE`. RLS: owner can always `SELECT` their own row; a separate policy lets anyone `SELECT` a row only where `is_public = true` (migration `0026`, lines 80-91) — connecting Discord never implies public display; the two are independent decisions. |
| What's displayed publicly | `js/pages/profile/renderProfileHero.js:129-155` (`renderConnectedAccounts`) — renders only when `provider_username` and `provider_user_id` are both present, as a link to `https://discord.com/users/<provider_user_id>` (a real Discord profile deep link) showing the Discord icon and username. The public read path, `getPublicDiscordConnection()` (`js/repositories/discordRepository.js:15-26`), selects only `provider_user_id, provider_username, provider_avatar_url` and filters `is_public = true` client-side in addition to RLS already enforcing it. `provider_avatar_url` is stored but **not currently rendered** anywhere. |
| User-facing error cases | See the table above (callback failures) plus: `setDiscordVisibility` throws `"No Discord connection found to update."` if the update matches zero rows (`js/repositories/discordRepository.js:63-75`, deliberately checked via `.select("id")` rather than trusting a silent 0-row `UPDATE` success); generic `"Could not refresh Discord connection."` / `"Could not disconnect Discord."` toasts on repository errors during those two actions (`js/pages/settings/app.js:473,517`). |
| Migration and RPC | `supabase/migrations/0026_social_connections.sql` — table `public.social_connections`, RLS policies, and `public.sync_discord_identity()`. Rollback: `supabase/rollbacks/0026_social_connections_rollback.sql`. |

**Known discrepancy, not fixed here:** migration `0026`'s own file header still says `Status: PROPOSED — not yet applied` (line 3). Per this task's verified starting state, `0026` is actually applied — local and remote migration history matched through `0033` in an earlier, separate preflight. This is the same class of stale in-file header comment already corrected for migration `0033` in `supabase/migrations.md` (PR #8); `0026`'s header was not in scope for that fix and is not touched here either, per this task's explicit instruction not to edit applied migration files. Flagging it here so it isn't mistaken for a live blocker.

---

## 2. Supabase dashboard configuration

**Not verifiable from this repository — read access to the Supabase dashboard was not used, and nothing here was changed.** Configure and confirm manually:

- [ ] **Authentication → Providers → Discord**: enabled, with a **Discord Client ID** and **Discord Client Secret** filled in (obtained from the Discord Developer Portal, §3).
- [ ] **Authentication → Providers → "Allow manual linking of identities to any user"** (`GOTRUE_SECURITY_MANUAL_LINKING_ENABLED`): enabled. `linkIdentity()` requires this to attach a second provider to an already-authenticated user — without it, every link attempt fails synchronously with the `manual_linking_disabled` error described in §1.
- [ ] **Authentication → URL Configuration → Site URL**: `https://specboundapp.com`
- [ ] **Authentication → URL Configuration → Redirect URLs**: allowlist the **exact** production path,
  ```
  https://specboundapp.com/pages/settings.html
  ```
  **Prefer this exact path over a wildcard** (`https://specboundapp.com/**`). Per §1, `redirectTo` has exactly one call site in the repo and it is always the live Settings page URL — nothing in the current implementation redirects from any other page. A wildcard would be strictly broader than what the code actually needs, with no repository evidence justifying it. If a future change adds a second call site elsewhere, widen the allowlist then, deliberately, rather than pre-emptively.

If `redirectTo` is not in the allowlist, Supabase does not surface a client-visible error for that specific case — it silently falls back to the Site URL, so the user lands somewhere other than Settings after linking with no error toast at all (this failure mode is **not** one of the cases `describeDiscordRedirectError()` can detect, since no `error` param is ever present on that particular redirect).

---

## 3. Discord Developer Portal configuration

**Not verifiable from this repository.** In the Discord application backing this integration, under **OAuth2 → Redirects**, confirm the redirect list includes:

```
https://xpxjqyraizntbtijzoyp.supabase.co/auth/v1/callback
```

This is **Supabase Auth's own hosted callback URL** — the fixed `https://<project-ref>.supabase.co/auth/v1/callback` pattern Supabase's GoTrue service uses for every OAuth provider on this project (ref `xpxjqyraizntbtijzoyp`, from `js/core/config.js`). **It is not the Specbound Settings page** and not something this repository's code ever constructs — GoTrue owns this leg of the redirect entirely; the app only ever sees the *final* `redirectTo` (§1, §2) after GoTrue's own exchange completes.

Also confirm, while there:
- **Client ID / Client Secret** match what's entered in the Supabase dashboard (§2). Do not paste the secret anywhere outside the Supabase dashboard itself.
- **OAuth2 scopes**: not specified anywhere in this repo's code (`linkIdentity({ provider: "discord" })` passes no `scopes` option), so whatever Supabase's Discord provider requests by default is what's used. `sync_discord_identity()` (§1) expects `identity_data` to contain Discord's `global_name`/`user_name`/`full_name`/`avatar_url` claims — if a future scope change on either side stops providing these, `provider_username` would fall back to `null`, which the table's `check (char_length(trim(provider_username)) > 0)` constraint rejects outright, so the sync would fail loudly rather than silently store a blank username.

### Do not do this while working through this checklist

Do not paste, screenshot, commit, or otherwise record the Discord **Client Secret**, any Supabase **service-role key**, **access token**, **password**, or other credential anywhere — not in this repository, not in a terminal transcript, not in a PR. Everything above is either a public identifier (Client ID, project ref, redirect URL) or a boolean dashboard toggle; nothing in this checklist requires a secret value to leave the two dashboards it lives in.

---

## 4. Safe manual functional test (not performed by this task)

**This test was not run.** It requires a real, dedicated test account and real dashboard access this documentation task does not have and was explicitly scoped not to use. Perform it manually, once §2–§3 are confirmed correct, using an account that is not a real user's:

1. Sign in to Specbound with the test account.
2. Open Settings.
3. Click "Connect Discord".
4. Complete Discord's authorization screen.
5. Confirm the browser returns to the Specbound Settings page (not an error page, not a different domain).
6. Confirm the connected Discord username now appears in the Connected Accounts section.
7. Enable "Show on profile".
8. Open the account's public profile in a signed-out/incognito window.
9. Confirm the Discord link is visible and opens the correct Discord user (`https://discord.com/users/<id>`).
10. Disable visibility in Settings, reload the signed-out public profile, and confirm the Discord link no longer appears.
11. Use the "Refresh" control in Settings and confirm it completes without error.
12. Disconnect Discord.
13. Confirm the connection no longer appears in Settings, and that reloading the public profile (even if visibility was previously on) shows no Discord link.

---

## 5. Troubleshooting

| Symptom | Likely cause | Where to check |
|---|---|---|
| "Discord connections aren't turned on for this Specbound environment yet." (toast, immediately on click, no Discord screen shown) | Manual identity linking disabled | §2, "Allow manual linking of identities to any user" |
| "Discord sign-in isn't set up for this Specbound environment yet." (toast, immediately on click) | Discord provider disabled, or Client ID/Secret missing | §2, Providers → Discord |
| User completes Discord auth, lands somewhere other than Settings, no error shown | `redirectTo` not in the Redirect URLs allowlist (Supabase silently falls back to Site URL) | §2, Redirect URLs — confirm exact match, no trailing-slash mismatch |
| "Discord connection cancelled." | User closed/declined Discord's consent screen | Expected behavior, not a config problem |
| "This Discord account is already linked to a different Specbound account." | The Discord identity is already linked to another Specbound user (`identity_already_exists`) | Expected behavior — Discord identities are unique per Specbound account (`social_connections`'s `(provider, provider_user_id)` constraint) |
| Connect succeeds but username never appears / stays on "Loading" | `sync_discord_identity()` failing — check for a `provider_username` that resolved to empty (see §3's scopes note) | Supabase logs for the RPC call; confirm Discord scopes still return `global_name`/`user_name` |
| Everything above checks out but linking still fails | Discord Developer Portal redirect URI mismatch | §3 — confirm the exact `https://<project-ref>.supabase.co/auth/v1/callback` string, no typos, correct project ref |

---

## 6. Security and secret-handling requirements

- This app has no server or edge-function layer; it cannot and does not hold a Discord OAuth token or client secret at any point. That is a structural property of the implementation (§1), not a configuration choice that could be accidentally weakened.
- The only credentials this feature needs (Discord Client ID + Secret) live exclusively in the Supabase dashboard's Provider settings. They are never entered into, read from, or transmitted through this repository's code.
- `public.sync_discord_identity()` is `SECURITY DEFINER` specifically so it can read `auth.identities` (otherwise inaccessible to PostgREST/RLS) — but it is hard-scoped to `auth.uid()` in its own `WHERE` clause, never a caller-supplied parameter, so no caller can read another user's linked identity through it (migration `0026`, function body).
- RLS on `social_connections` never allows a stranger to read a private connection: the public-read policy explicitly requires `is_public = true` (migration `0026`, lines 89-91) as a second, independent policy — not a relaxation of the owner policy.
- Nothing in this guide, this task's diff, or the manual test in §4 requires exposing a Client Secret, service-role key, access token, or password in any repository file, terminal output, screenshot, commit, or pull request. If any step ever seems to require that, stop — it means something is being configured in the wrong place.
